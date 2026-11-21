//! Office machine-scoped updates. No generic remote shell or upstream updater.
use hbb_common::{bail, config::Config, log, sodiumoxide::base64, ResultType};
use serde_derive::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::os::windows::{fs::OpenOptionsExt, process::CommandExt};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

const API: &str = "https://api-office.exantas.eu/api/v1/rustdesk-devices/updates";
const SCRIPT: &str = include_str!("../res/office-update.ps1");
const EVENT: &str = "Global\\ExantasRdclUpdateBarrier";

#[derive(Clone, Serialize, Deserialize)]
pub struct Registration {
    pub device_token: String,
    pub device_id: String,
    pub peer_id: String,
}
impl std::fmt::Debug for Registration {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("OfficeUpdateRegistration(<redacted>)")
    }
}

fn root() -> ResultType<PathBuf> {
    let program_data = std::env::var_os("ProgramData")
        .ok_or_else(|| hbb_common::anyhow::anyhow!("program_data_missing"))?;
    let root = PathBuf::from(program_data).join("ExantasRdclUpdates");
    if !root.is_absolute() {
        bail!("invalid_update_root");
    }
    Ok(root)
}

fn system() -> bool {
    crate::platform::is_process_running_as_system(std::process::id()).unwrap_or(false)
}

fn powershell() -> PathBuf {
    // Use the operating system executable, never an entry from PATH.
    PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into()))
        .join("System32/WindowsPowerShell/v1.0/powershell.exe")
}

fn verify_root() -> ResultType<()> {
    let script = r#"$ErrorActionPreference='Stop'; $p=Join-Path $env:ProgramData 'ExantasRdclUpdates';
      $x=Get-Item -LiteralPath $p -Force; while($null -ne $x){if($x.Attributes -band 1024){exit 1};$x=if($x -is [IO.DirectoryInfo]){$x.Parent}else{$x.Directory}};
      $a=Get-Acl -LiteralPath $p; if($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){exit 1};
      foreach($r in $a.Access){if($r.AccessControlType -eq 'Allow' -and $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){exit 1}}"#;
    if !Command::new(powershell())
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .creation_flags(0x08000000)
        .status()?
        .success()
    {
        bail!("untrusted_update_directory");
    }
    Ok(())
}

fn initialize_root() -> ResultType<PathBuf> {
    let root = root()?;
    if !root.exists() {
        fs::create_dir(&root)?;
        let icacls = PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into()))
            .join("System32/icacls.exe");
        let status = Command::new(icacls)
            .arg(&root)
            .args([
                "/inheritance:r",
                "/grant:r",
                "*S-1-5-18:(OI)(CI)F",
                "*S-1-5-32-544:(OI)(CI)F",
                "/setowner",
                "*S-1-5-18",
            ])
            .creation_flags(0x08000000)
            .stdout(Stdio::null())
            .status()?;
        if !status.success() {
            bail!("update_acl_failed");
        }
    }
    verify_root()?;
    Ok(root)
}

fn private_json(path: &Path, value: &Value) -> ResultType<()> {
    let temporary = path.with_extension("new");
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .share_mode(0)
        .open(&temporary)?;
    crate::platform::set_private_runtime_file_permissions(&temporary)?;
    file.write_all(&serde_json::to_vec(value)?)?;
    file.sync_all()?;
    drop(file);
    use winapi::um::winbase::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
    let from = wide(&temporary.to_string_lossy());
    let to = wide(&path.to_string_lossy());
    if unsafe {
        MoveFileExW(
            from.as_ptr(),
            to.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    } == 0
    {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(())
}

fn encrypt_machine(token: &str) -> ResultType<String> {
    use winapi::um::{
        dpapi::{CryptProtectData, CRYPTPROTECT_LOCAL_MACHINE, CRYPTPROTECT_UI_FORBIDDEN},
        winbase::LocalFree,
        wincrypt::DATA_BLOB,
    };
    let mut input = token.as_bytes().to_vec();
    let mut input = DATA_BLOB {
        cbData: input.len() as u32,
        pbData: input.as_mut_ptr(),
    };
    let mut output: DATA_BLOB = unsafe { std::mem::zeroed() };
    unsafe {
        if CryptProtectData(
            &mut input,
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            CRYPTPROTECT_LOCAL_MACHINE | CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        ) == 0
        {
            bail!("machine_protection_failed");
        }
        if output.pbData.is_null() {
            bail!("machine_protection_failed");
        }
        let encoded = base64::encode(
            std::slice::from_raw_parts(output.pbData, output.cbData as usize),
            base64::Variant::Original,
        );
        LocalFree(output.pbData as _);
        Ok(encoded)
    }
}

pub fn register(request: Registration) -> ResultType<()> {
    if !system()
        || !crate::platform::is_installed()
        || !crate::platform::is_cur_exe_the_installed()
        || crate::platform::is_msi_installed()?
        || request.peer_id != Config::get_id()
        || hbb_common::uuid::Uuid::parse_str(&request.device_id).is_err()
        || request.device_token.len() > 256
    {
        bail!("installed_device_required");
    }
    let root = initialize_root()?;
    if root.join("stop-requested").exists() {
        bail!("local_uninstall_requested");
    }
    let _lock = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .share_mode(0)
        .open(root.join("registration.lock"))?;
    let path = root.join("machine.json");
    let existing: Option<Value> = if path.exists() {
        Some(serde_json::from_slice(&fs::read(&path)?)?)
    } else {
        None
    };
    if let Some(ref existing) = existing {
        if existing["peer_id"] != request.peer_id || existing["device_id"] != request.device_id {
            bail!("update_identity_changed");
        }
        if existing["registered"] == true {
            return Ok(());
        }
    }
    let client = reqwest::blocking::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(15))
        .build()?;
    // Validate current device authority before accepting a new local candidate.
    let policy = client
        .get("https://api-office.exantas.eu/api/v1/rustdesk-devices/policy")
        .bearer_auth(&request.device_token)
        .send()?;
    if !policy.status().is_success() {
        bail!("office_registration_rejected");
    }
    let bytes = policy.take(65537).bytes().collect::<Result<Vec<_>, _>>()?;
    if bytes.len() > 65536 {
        bail!("office_response_too_large");
    }
    let policy: Value = serde_json::from_slice(&bytes)?;
    if policy["device"]["id"] != request.device_id || policy["device"]["peer_id"] != request.peer_id
    {
        bail!("office_device_mismatch");
    }
    let mut machine = match existing {
        Some(value) => value,
        None => {
            let token = format!(
                "rdu_{}",
                base64::encode(
                    hbb_common::sodiumoxide::randombytes::randombytes(32),
                    base64::Variant::UrlSafeNoPadding
                )
            );
            let token_hash = format!(
                "{:x}",
                Sha256::digest(format!("rdcl-update-v1:{token}").as_bytes())
            );
            json!({"schema":1,"installation_id":hbb_common::uuid::Uuid::new_v4().to_string(),"device_id":request.device_id,
                "peer_id":request.peer_id,"token_hash":token_hash,"encrypted_token":encrypt_machine(&token)?,"registered":false,"trusted_keys":{},
                "install_exe":crate::platform::get_install_info().3,"service_name":crate::get_app_name(),"host_path":""})
        }
    };
    // Save the candidate before bootstrap so retries do not rotate authority.
    private_json(&path, &machine)?;
    let response = client.post(format!("{API}/bootstrap")).bearer_auth(request.device_token)
        .json(&json!({"installation_id":machine["installation_id"],"token_hash":machine["token_hash"],"peer_id":machine["peer_id"]})).send()?;
    if !response.status().is_success() {
        bail!("office_registration_rejected");
    }
    let bytes = response
        .take(65537)
        .bytes()
        .collect::<Result<Vec<_>, _>>()?;
    if bytes.len() > 65536 {
        bail!("office_response_too_large");
    }
    let reply: Value = serde_json::from_slice(&bytes)?;
    if reply["registered"] != true || reply["update_protocol"] != 2 || reply["device_id"] != machine["device_id"] {
        bail!("office_registration_pending");
    }
    let keys = reply["trusted_keys"]
        .as_object()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("update_keys_missing"))?;
    if keys.is_empty() || keys.len() > 8 {
        bail!("update_keys_missing");
    }
    machine["trusted_keys"] = reply["trusted_keys"].clone();
    machine["registered"] = json!(true);
    private_json(&path, &machine)?;
    Ok(())
}

fn verify_envelope(path: &Path) -> ResultType<Value> {
    verify_root()?;
    let machine: Value = serde_json::from_slice(&fs::read(root()?.join("machine.json"))?)?;
    if fs::metadata(path)?.len() > 1500000 {
        bail!("envelope_too_large");
    }
    let envelope: Value = serde_json::from_slice(&fs::read(path)?)?;
    let key_id = envelope["key_id"]
        .as_str()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("key_missing"))?;
    let key = machine["trusted_keys"][key_id]
        .as_str()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("unknown_signer"))?;
    let key = base64::decode(key, base64::Variant::Original)
        .map_err(|_| hbb_common::anyhow::anyhow!("invalid_signer_encoding"))?;
    let key = hbb_common::sodiumoxide::crypto::sign::PublicKey::from_slice(&key)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_signer"))?;
    let raw = base64::decode(
        envelope["payload"].as_str().unwrap_or(""),
        base64::Variant::Original,
    ).map_err(|_| hbb_common::anyhow::anyhow!("invalid_payload_encoding"))?;
    let signature = base64::decode(
        envelope["signature"].as_str().unwrap_or(""),
        base64::Variant::Original,
    ).map_err(|_| hbb_common::anyhow::anyhow!("invalid_signature_encoding"))?;
    let signature = hbb_common::sodiumoxide::crypto::sign::Signature::from_bytes(&signature)
        .map_err(|_| hbb_common::anyhow::anyhow!("invalid_signature_size"))?;
    if !hbb_common::sodiumoxide::crypto::sign::verify_detached(&signature, &raw, &key) {
        bail!("invalid_signature");
    }
    let release: Value = serde_json::from_slice(&raw)?;
    let issued = chrono::DateTime::parse_from_rfc3339(release["issued_at"].as_str().unwrap_or(""))?;
    let expires =
        chrono::DateTime::parse_from_rfc3339(release["expires_at"].as_str().unwrap_or(""))?;
    let now = chrono::Utc::now();
    let url = release["url"].as_str().unwrap_or("");
    let hash = release["sha256"].as_str().unwrap_or("");
    let version = release["version"].as_str().unwrap_or("");
    if release["schema"] != 1
        || release["protocol"] != 2
        || release["platform"] != "windows-x64"
        || !crate::office_update_policy::own_signature_policy(
            release["verification"].as_str(), release.get("publisher_thumbprint").is_some())
        || hash.len() != 64
        || !hash
            .bytes()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
        || url != format!(
            "https://office.exantas.eu/downloads/rd-cl/rd-cl-{version}-{}-windows-x64-install.exe",
            &hash[..12]
        )
        || issued > now + chrono::Duration::seconds(60)
        || expires <= now
        || expires <= issued
        || (expires - issued).num_days() > 31
        || !crate::office_update_policy::newer(version, &crate::VERSION)
        || release["files"].as_array().map(|v| v.len()).unwrap_or(0) < 5
    {
        bail!("invalid_release");
    }
    let mut names = std::collections::HashSet::new();
    for file in release["files"]
        .as_array()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_inventory"))?
    {
        let path = file["path"].as_str().unwrap_or("");
        if !crate::office_update_policy::safe_path(path) || !names.insert(path.to_ascii_lowercase())
        {
            bail!("invalid_inventory");
        }
    }
    Ok(release)
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

pub fn blocked() -> bool {
    use winapi::um::{
        handleapi::CloseHandle,
        synchapi::{OpenEventW, WaitForSingleObject},
        winnt::SYNCHRONIZE,
    };
    unsafe {
        let event = OpenEventW(SYNCHRONIZE, 0, wide(EVENT).as_ptr());
        if event.is_null() {
            return std::io::Error::last_os_error().raw_os_error() != Some(2);
        }
        let result = WaitForSingleObject(event, 0);
        CloseHandle(event);
        result != 258 // timeout means the event is reset; errors fail closed.
    }
}

fn create_barrier() -> ResultType<usize> {
    // Never derive a connection fence from a pre-created user-owned journal.
    let protected_root = root()?;
    let trusted_state = protected_root.exists();
    if trusted_state {
        verify_root()?;
    }
    use winapi::{
        shared::{minwindef::LPVOID, sddl::ConvertStringSecurityDescriptorToSecurityDescriptorW},
        um::{
            minwinbase::SECURITY_ATTRIBUTES,
            synchapi::CreateEventW,
            winbase::LocalFree,
        },
    };
    let mut descriptor: LPVOID = std::ptr::null_mut();
    unsafe {
        if ConvertStringSecurityDescriptorToSecurityDescriptorW(
            wide("O:SYG:SYD:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x00100000;;;WD)").as_ptr(),
            1,
            &mut descriptor,
            std::ptr::null_mut(),
        ) == 0
        {
            bail!("barrier_acl_failed");
        }
        let mut attributes = SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: descriptor,
            bInheritHandle: 0,
        };
        // A retained journal blocks connections until the helper reconciles it.
        let journal = protected_root.join("journal.json");
        let pending = if trusted_state && journal.exists() {
            fs::read(journal)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
                .map(|value| {
                    !matches!(
                        value["phase"].as_str(),
                        Some("complete" | "rolled_back" | "cancelled" | "failed")
                    )
                })
                .unwrap_or(true)
        } else {
            false
        };
        let handle = CreateEventW(
            &mut attributes,
            1,
            if pending { 1 } else { 0 },
            wide(EVENT).as_ptr(),
        );
        LocalFree(descriptor as _);
        if handle.is_null() {
            bail!("barrier_creation_failed");
        }
        // CreateEvent ignores the supplied DACL when the object already exists.
        // Reject a pre-created user-owned event before an update can run.
        let check = r#"$ErrorActionPreference='Stop';$e=[Threading.EventWaitHandle]::OpenExisting('Global\ExantasRdclUpdateBarrier');try{
          $a=$e.GetAccessControl();if($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-18'){exit 1};
          foreach($r in $a.Access){if($r.AccessControlType -eq 'Allow' -and ($r.EventWaitHandleRights -band [Security.AccessControl.EventWaitHandleRights]::Modify) -and $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){exit 1}}
        }finally{$e.Dispose()}"#;
        if !Command::new(powershell())
            .args(["-NoProfile", "-NonInteractive", "-Command", check])
            .creation_flags(0x08000000)
            .status()?
            .success()
        {
            winapi::um::handleapi::CloseHandle(handle);
            bail!("barrier_owner_invalid");
        }
        Ok(handle as usize)
    }
}

pub fn start_service_worker() {
    if !system() {
        return;
    }
    let handle = match create_barrier() {
        Ok(handle) => handle,
        Err(_) => {
            log::error!("Office update barrier unavailable");
            return;
        }
    };
    std::thread::spawn(move || {
        let _retained_barrier_handle = handle;
        loop {
            let result = (|| -> ResultType<()> {
                let root = root()?;
                if !root.join("machine.json").exists() || root.join("stop-requested").exists() {
                    return Ok(());
                }
                verify_root()?;
                let script = root.join("worker.ps1");
                fs::write(&script, SCRIPT)?;
                crate::platform::set_private_runtime_file_permissions(&script)?;
                let (_, _, _, executable) = crate::platform::get_install_info();
                let entry = "& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $env:ProgramData 'ExantasRdclUpdates\\worker.ps1'))))";
                let mut child = Command::new(powershell())
                    .args(["-NoProfile", "-NonInteractive", "-Command", entry])
                    .env("RDCL_UPDATE_CORE", executable)
                    .env("RDCL_UPDATE_SERVICE", crate::get_app_name())
                    .creation_flags(0x08000000)
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()?;
                if !child.wait()?.success() {
                    bail!("update_worker_failed");
                }
                Ok(())
            })();
            if result.is_err() {
                log::warn!("Office update worker deferred; inspect protected update log");
            }
            std::thread::sleep(Duration::from_secs(60));
        }
    });
}

pub fn command(args: &[String]) -> Option<i32> {
    let mode = args.first()?.as_str();
    if !mode.starts_with("--office-update-") {
        return None;
    }
    let result = (|| -> ResultType<Value> {
        if mode == "--office-update-disable" || mode == "--office-update-enable" {
            if !crate::platform::is_elevated(None)? || !crate::platform::is_cur_exe_the_installed()
            {
                bail!("administrator_required");
            }
            let root = root()?;
            if !root.join("machine.json").exists() {
                return Ok(json!({"configured":false}));
            }
            verify_root()?;
            if blocked() {
                bail!("update_still_fenced");
            }
            let script = if mode == "--office-update-enable" {
                r#"$ErrorActionPreference='Stop';$p=Join-Path $env:ProgramData 'ExantasRdclUpdates\stop-requested';
                  if(Test-Path -LiteralPath $p){$f=Get-Item -LiteralPath $p -Force;if(($f.Attributes -band 1024) -or $f.Length -gt 8 -or [IO.File]::ReadAllText($p) -cne 'stop'){exit 1};Remove-Item -LiteralPath $p}"#
            } else {
                r#"$ErrorActionPreference='Stop';$r=Join-Path $env:ProgramData 'ExantasRdclUpdates';$m=Get-Content -Raw (Join-Path $r 'machine.json')|ConvertFrom-Json;
                  $j=Join-Path $r 'journal.json';if(Test-Path $j){$j=Get-Content -Raw $j|ConvertFrom-Json;if($j.phase -in @('replacing','replaced','restoring','restored','verifying') -or ($j.pending_action -and $j.pending_action.action -eq 'permit')){exit 1}};
                  $p=Join-Path $r 'stop-requested';if(!(Test-Path -LiteralPath $p)){$s=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$b=[Text.Encoding]::ASCII.GetBytes('stop');$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()}};
                  $lock=$null;for($i=0;$i -lt 20;$i++){try{$lock=[IO.File]::Open((Join-Path $r 'worker.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);break}catch{Start-Sleep -Milliseconds 500}};if(!$lock){exit 1};
                  try{$t=Get-ScheduledTask -TaskName 'Exantas rd-cl update recovery' -ErrorAction SilentlyContinue;
                    if($t){$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';
                      $a='-NoProfile -NonInteractive -Command "& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $env:ProgramData ''ExantasRdclUpdates\worker.ps1''))))"';
                      if($t.Description -cne ('ExantasRdclUpdates/'+$m.installation_id) -or @($t.Actions).Count -ne 1 -or $t.Actions[0].Execute -ine $ps -or $t.Actions[0].Arguments -cne $a -or $t.Principal.UserId -notin @('SYSTEM','S-1-5-18')){exit 1};
                      Unregister-ScheduledTask -TaskName 'Exantas rd-cl update recovery' -Confirm:$false}
                  }finally{$lock.Dispose()}"#
            };
            if !Command::new(powershell())
                .args(["-NoProfile", "-NonInteractive", "-Command", script])
                .creation_flags(0x08000000)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .status()?
                .success()
            {
                bail!("update_recovery_cleanup_deferred");
            }
            return Ok(json!({"configured":true}));
        }
        if mode == "--office-update-register" {
            let mut bytes = Vec::new();
            std::io::stdin().take(4097).read_to_end(&mut bytes)?;
            if bytes.len() > 4096 {
                bail!("registration_too_large");
            }
            let request: Registration = serde_json::from_slice(&bytes)?;
            let runtime = hbb_common::tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            return runtime.block_on(async {
                let mut stream = crate::ipc::connect_service(1000).await?;
                stream
                    .send(&crate::ipc::Data::OfficeUpdateRegister(request))
                    .await?;
                match stream.next_timeout(20000).await? {
                    Some(crate::ipc::Data::OfficeUpdateReply(reply))
                        if reply["registered"] == true =>
                    {
                        Ok(reply)
                    }
                    _ => bail!("registration_unconfirmed"),
                }
            });
        }
        if !system() {
            bail!("system_service_required");
        }
        if mode == "--office-update-verify" && args.len() == 2 {
            verify_root()?;
            let config: Value = serde_json::from_slice(&fs::read(root()?.join("machine.json"))?)?;
            let expected = config["host_path"].as_str().unwrap_or("");
            if !crate::platform::is_cur_exe_the_installed()
                && fs::canonicalize(std::env::current_exe()?)? != fs::canonicalize(expected)?
            {
                bail!("trusted_update_host_required");
            }
            return verify_envelope(Path::new(&args[1]));
        }
        if !crate::platform::is_cur_exe_the_installed() {
            bail!("installed_core_required");
        }
        if mode == "--office-update-register-version" {
            use winreg::{
                enums::{HKEY_LOCAL_MACHINE, KEY_SET_VALUE},
                RegKey,
            };
            let (subkey, _, _, _) = crate::platform::get_install_info();
            let subkey = subkey
                .strip_prefix("HKEY_LOCAL_MACHINE\\")
                .ok_or_else(|| hbb_common::anyhow::anyhow!("invalid_install_key"))?;
            let key =
                RegKey::predef(HKEY_LOCAL_MACHINE).open_subkey_with_flags(subkey, KEY_SET_VALUE)?;
            key.set_value("DisplayVersion", &crate::VERSION)?;
            key.set_value("Version", &crate::VERSION)?;
            key.set_value("BuildDate", &crate::BUILD_DATE)?;
            let numbers: Vec<u32> = crate::VERSION
                .split('.')
                .map(|n| n.parse().unwrap_or(0))
                .collect();
            for (i, name) in ["VersionMajor", "VersionMinor", "VersionBuild"]
                .iter()
                .enumerate()
            {
                key.set_value(name, &numbers.get(i).copied().unwrap_or(0))?;
            }
            return Ok(json!({"registered":true}));
        }
        if mode == "--office-update-restore-tray" {
            if blocked() {
                bail!("update_still_fenced");
            }
            crate::platform::run_as_user(vec!["--tray"])?;
            return Ok(json!({"restored":true}));
        }
        if mode == "--office-update-probe" {
            let runtime = hbb_common::tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            return runtime.block_on(async {
                let mut stream = crate::ipc::connect(1000, "").await?;
                stream.send(&crate::ipc::Data::OfficeUpdateProbe).await?;
                match stream.next_timeout(2000).await? {
                    Some(crate::ipc::Data::OfficeUpdateReply(reply))
                        if reply["version"] == crate::VERSION =>
                    {
                        Ok(reply)
                    }
                    _ => bail!("idle_unconfirmed"),
                }
            });
        }
        bail!("invalid_update_command")
    })();
    match result {
        Ok(value) => {
            println!("{value}");
            Some(0)
        }
        Err(_) => {
            eprintln!("office_update_check_failed");
            Some(1)
        }
    }
}
