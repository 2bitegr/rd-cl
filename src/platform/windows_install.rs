//! Pure command generation shared by Windows installation and upgrade.
//! Kept free of platform dependencies so the payload/guard contract is testable.

pub(super) fn payload_commands(
    source_exe: &str,
    source_dir: &str,
    source_name: &str,
    target_exe: &str,
    target_dir: &str,
    flutter: bool,
) -> String {
    // /C would continue after copy errors. Locked/missing payloads must fail.
    let mut commands = format!(
        "XCOPY \"{source_dir}\" \"{target_dir}\" /Y /E /H /I /K /R /Z\n"
    );
    let copied_exe = format!("{target_dir}\\{source_name}");
    if !copied_exe.eq_ignore_ascii_case(target_exe) {
        commands.push_str(&format!("move /Y \"{copied_exe}\" \"{target_exe}\"\n"));
    }
    // Verify the installed executable bytes before publishing registry/shortcuts.
    commands.push_str(&format!("fc /b \"{source_exe}\" \"{target_exe}\" >nul\n"));
    if flutter {
        for file in ["librustdesk.dll", "flutter_windows.dll", "data\\app.so", "data\\icudtl.dat"] {
            commands.push_str(&format!(
                "fc /b \"{source_dir}\\{file}\" \"{target_dir}\\{file}\" >nul\n"
            ));
        }
    }
    commands
}

pub(super) fn checked_commands(script: &str) -> String {
    let mut result = String::new();
    let mut config_import_start = false;
    for (index, line) in script.lines().enumerate() {
        result.push_str(line);
        result.push('\n');
        let command = line.trim().to_ascii_lowercase();
        // Stop/delete/taskkill are deliberately best-effort for absent old installs.
        // Their failure cannot mask a later locked-file copy or byte comparison.
        let required = ["xcopy ", "copy /y ", "move /y ", "fc /b ", "reg add ",
                        "cscript ", "sc create ", "sc start ", "netsh advfirewall firewall add "]
            .iter().any(|prefix| command.starts_with(prefix));
        if required {
            // The one-shot --import-config process is not an SCM service: 1053
            // is expected after it exits. Never allow that for the real service.
            let condition = if config_import_start && command.starts_with("sc start ") {
                "if errorlevel 1 if not \"%errorlevel%\"==\"1053\""
            } else {
                "if errorlevel 1"
            };
            result.push_str(&format!(
                "{condition} (\n>\"%RDCL_INSTALL_FAILURE%\" echo Required installation step {} failed\nexit /b 1\n)\n",
                index + 1
            ));
        }
        config_import_start = command == "rem rdcl_config_import_start";
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn branded_target_is_renamed_and_compared_before_success() {
        let script = payload_commands(r"C:\Input\rustdesk.exe", r"C:\Input", "rustdesk.exe",
            r"C:\Program Files\Exantas Support\Exantas Support.exe",
            r"C:\Program Files\Exantas Support", true);
        assert!(!script.contains(" /C"));
        let rename = script.find("move /Y").unwrap();
        let compare = script.find("fc /b").unwrap();
        assert!(rename < compare);
        assert!(script.contains(r#""C:\Program Files\Exantas Support\Exantas Support.exe""#));
        assert!(script.contains("librustdesk.dll"));
        assert!(script.contains("data\\app.so"));
    }

    #[test]
    fn already_named_source_is_not_moved_onto_itself() {
        let script = payload_commands(r"C:\Input\Exantas Support.exe", r"C:\Input",
            "Exantas Support.exe", r"C:\Target\Exantas Support.exe", r"C:\Target", false);
        assert!(!script.contains("move /Y"));
        assert!(script.contains("fc /b"));
        assert!(!script.contains("librustdesk.dll"));
    }

    #[test]
    fn config_import_timeout_exception_does_not_apply_to_real_service() {
        let script = checked_commands("rem RDCL_CONFIG_IMPORT_START\nsc start \"Exantas Support\"\nsc start \"Exantas Support\"\n");
        assert_eq!(script.matches("if not \"%errorlevel%\"==\"1053\"").count(), 1);
        assert_eq!(script.matches("if errorlevel 1 (\n").count(), 1);
    }

    #[test]
    fn required_steps_abort_but_absent_old_install_is_allowed() {
        let checked = checked_commands("sc stop \"Exantas Support\"\nXCOPY x y\nreg add x\ncscript x\nsc create x\nsc start x\ncopy /Y a b\nmove /Y a b\nfc /b a b\n");
        assert!(checked.starts_with("sc stop \"Exantas Support\"\nXCOPY"));
        assert_eq!(checked.matches("exit /b 1").count(), 8);
        assert!(checked.contains("step 2 failed"));
    }
}
