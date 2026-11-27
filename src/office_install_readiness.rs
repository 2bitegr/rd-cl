//! Installer diagnostics and a closed set of locally confirmed service repairs.
//! No remote shell, registry cleanup, credential reset or automatic reboot.
use hbb_common::{bail, ResultType};
use serde_json::{json, Value};
use std::{
    io::Read,
    os::windows::process::CommandExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

pub const LIBRARY: &str = include_str!("../res/office-readiness.ps1");

fn configuration(target: Option<&str>) -> Value {
    let (_, directory, _, executable) = crate::platform::get_install_info();
    json!({"installed":crate::platform::is_installed(),
        "msi":crate::platform::is_msi_installed().ok(),
        "expected_exe":executable,"target_dir":target.unwrap_or(&directory)})
}

fn powershell() -> PathBuf {
    PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into()))
        .join("System32/WindowsPowerShell/v1.0/powershell.exe")
}

fn script(config: &Value, action: Option<(&str, &str)>) -> ResultType<String> {
    use hbb_common::sodiumoxide::base64::{encode, Variant};
    let input = encode(&serde_json::to_vec(config)?, Variant::Original);
    let call = match action {
        None => "Get-OfficeInstallReadiness $c".to_owned(),
        Some((action, fingerprint)) => {
            if !["start_service", "automatic_service"].contains(&action)
                || fingerprint.len() != 64
                || !fingerprint
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            {
                bail!("invalid_repair");
            }
            format!("Repair-OfficeInstallReadiness $c '{action}' '{fingerprint}'")
        }
    };
    Ok(format!("$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);\n{LIBRARY}\n$c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{input}'))|ConvertFrom-Json;try{{$r={call};$r|ConvertTo-Json -Depth 8 -Compress}}catch{{exit 1}}"))
}

fn encoded(script: &str) -> String {
    use hbb_common::sodiumoxide::base64::{encode, Variant};
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    encode(&bytes, Variant::Original)
}

fn run(script: &str) -> ResultType<Value> {
    if script.encode_utf16().count() > 11000 {
        bail!("readiness_command_too_large");
    }
    let mut child = Command::new(powershell())
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-EncodedCommand",
            &encoded(script),
        ])
        .creation_flags(0x08000000)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("readiness_output_missing"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("readiness_error_missing"))?;
    let out = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        stdout.take(65537).read_to_end(&mut bytes).map(|_| bytes)
    });
    let err = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        stderr.take(8193).read_to_end(&mut bytes).map(|_| bytes)
    });
    let start = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break Some(status);
        }
        if start.elapsed() > Duration::from_secs(25) {
            let _ = child.kill();
            let _ = child.wait();
            break None;
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    let bytes = out
        .join()
        .map_err(|_| hbb_common::anyhow::anyhow!("readiness_reader_failed"))??;
    let errors = err
        .join()
        .map_err(|_| hbb_common::anyhow::anyhow!("readiness_reader_failed"))??;
    if !status.map(|s| s.success()).unwrap_or(false) || bytes.len() > 65536 || errors.len() > 8192 {
        bail!("readiness_unconfirmed");
    }
    let value: Value = serde_json::from_slice(&bytes)?;
    if value["schema"] != 1 {
        bail!("readiness_schema_invalid");
    }
    Ok(value)
}

pub fn local(target: Option<&str>) -> ResultType<Value> {
    let mut report = run(&script(&configuration(target), None)?)?;
    if crate::office_update::blocked() {
        report["repair_fingerprint"] = Value::Null;
        report["repair_target"] = Value::Null;
        report["checks"]
            .as_array_mut()
            .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_checks"))?
            .push(json!({"code":"update_in_progress","status":"pending","action":null}));
    }
    Ok(report)
}

/// Called only after the existing active-session service IPC authorization.
pub async fn service() -> ResultType<Value> {
    let mut report = hbb_common::tokio::task::spawn_blocking(|| local(None)).await??;
    let health: ResultType<Value> = async {
        let mut stream = crate::ipc::connect(1000, "").await?;
        stream.send(&crate::ipc::Data::OfficeUpdateProbe).await?;
        match stream.next_timeout(3000).await? {
            Some(crate::ipc::Data::OfficeUpdateReply(value)) => Ok(value),
            _ => bail!("runtime_unconfirmed"),
        }
    }
    .await;
    let checks = report["checks"]
        .as_array_mut()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_checks"))?;
    match health {
        Ok(value) => {
            checks.push(json!({"code":"runtime_idle","status":if value["idle"]==true {"ok"}else{"pending"},"action":null}));
            checks.push(json!({"code":"runtime_identity","status":if value["peer_id"]==hbb_common::config::Config::get_id() {"ok"}else{"blocked"},"action":null}));
            checks.push(json!({"code":"runtime_installation","status":if value["install_mode"]=="exe" && value["version"]==crate::VERSION {"ok"}else{"unknown"},"action":null}));
            report["installed_version"] = value["version"].clone();
        }
        Err(_) => {
            checks.push(json!({"code":"runtime_unconfirmed","status":"unknown","action":null}))
        }
    }
    // Credential and trust evidence is inspected inside SYSTEM and never returned.
    let remote = hbb_common::tokio::task::spawn_blocking(crate::office_update::readiness).await;
    report["office"] = match remote {
        Ok(Ok(value)) => value,
        _ => json!({"schema":1,"state":"unknown","reasons":["office_unconfirmed"]}),
    };
    Ok(report)
}

pub fn command(args: &[String]) -> Option<i32> {
    let mode = args.first()?.as_str();
    if ![
        "--office-install-readiness",
        "--office-install-repair",
        "--office-install-repair-elevated",
    ]
    .contains(&mode)
    {
        return None;
    }
    let result = (|| -> ResultType<Value> {
        if mode == "--office-install-readiness" {
            if args.len() > 2 {
                bail!("invalid_readiness_request");
            }
            if crate::platform::is_cur_exe_the_installed() {
                let runtime = hbb_common::tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()?;
                let report: ResultType<Value> = runtime.block_on(async {
                    let mut stream = crate::ipc::connect_service(1000).await?;
                    stream
                        .send(&crate::ipc::Data::OfficeInstallReadiness)
                        .await?;
                    match stream.next_timeout(45000).await? {
                        Some(crate::ipc::Data::OfficeUpdateReply(report))
                            if report["schema"] == 1 =>
                        {
                            Ok(report)
                        }
                        _ => bail!("readiness_unconfirmed"),
                    }
                });
                if report.is_ok() {
                    return report;
                }
            }
            let mut report = local(args.get(1).map(String::as_str))?;
            report["office"] =
                json!({"schema":1,"state":"unknown","reasons":["post_install_check_required"]});
            Ok(report)
        } else {
            if args.len() != 3
                || crate::office_update::blocked()
                || !crate::platform::is_installed()
                || crate::platform::is_msi_installed()?
            {
                bail!("repair_not_available");
            }
            // Validate all arguments before elevation; no supplied shell or path.
            let repair = script(&configuration(None), Some((&args[1], &args[2])))?;
            if mode == "--office-install-repair-elevated" {
                if !crate::platform::is_elevated(None)? {
                    bail!("administrator_required");
                }
                run(&repair)
            } else {
                hbb_common::log::info!("Office installer service repair requested: {}", args[1]);
                let executable = std::env::current_exe()?;
                let executable = executable
                    .to_str()
                    .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_executable"))?;
                let status = runas::Command::new(executable)
                    .args(&["--office-install-repair-elevated", &args[1], &args[2]])
                    .show(false)
                    .force_prompt(true)
                    .status()?;
                if !status.success() {
                    bail!("repair_not_confirmed");
                }
                Ok(json!({"schema":1,"applied":true}))
            }
        }
    })();
    match result {
        Ok(value) => {
            if mode == "--office-install-repair-elevated" {
                hbb_common::log::info!("Office installer service repair applied: {}", args[1]);
            }
            println!("{value}");
            Some(0)
        }
        Err(_) => {
            if mode == "--office-install-repair" || mode == "--office-install-repair-elevated" {
                hbb_common::log::warn!("Office installer service repair unconfirmed");
            }
            eprintln!("office_install_check_unconfirmed");
            Some(1)
        }
    }
}
