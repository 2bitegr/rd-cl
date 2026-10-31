//! The shared EXE is unchanged per customer. Only a short-lived, peer-bound
//! installation capability travels in its download name; never a device token.

fn installer_stem(name: &str) -> Option<String> {
    let name = name.rsplit(['/', '\\']).next()?.to_ascii_lowercase();
    let stem = name.strip_suffix(".exe")?;
    let stem = if let Some((base, suffix)) = stem.rsplit_once(" (") {
        let number = suffix.strip_suffix(')')?;
        if number.is_empty() || number.len() > 3 || !number.bytes().all(|b| b.is_ascii_digit()) { return None; }
        base
    } else { stem };
    Some(stem.to_owned())
}
pub fn is_installer_filename(name: &str) -> bool {
    installer_stem(name).map(|n| n.ends_with("install")).unwrap_or(false)
}
pub fn enrollment_code(name: &str) -> Option<String> {
    let stem = installer_stem(name)?;
    let value = stem.strip_suffix("-install")?;
    let (prefix, code) = value.split_once("-auto-")?;
    let version = prefix.strip_prefix("rd-cl-")?;
    if version.is_empty() || !version.bytes().all(|b| b.is_ascii_digit() || [b'.', b'+'].contains(&b)) { return None; }
    let parts: Vec<_> = code.split('-').collect();
    if parts.len() != 4 || parts[0] != "exa" || !parts[1..].iter().all(|p| p.len() == 6 && p.bytes().all(|b| b.is_ascii_hexdigit())) { return None; }
    Some(code.to_ascii_uppercase())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scoped_name_and_browser_duplicate_preserve_the_code() {
        for n in ["rd-cl-2.0.2+74-auto-EXA-000001-000002-000003-install.exe", "rd-cl-2.0.2+74-auto-EXA-000001-000002-000003-install (1).exe"] {
            assert!(is_installer_filename(n));assert_eq!(enrollment_code(n).as_deref(),Some("EXA-000001-000002-000003"));
        }
    }
    #[test]
    fn generic_or_malformed_files_never_supply_an_enrollment() {
        assert!(is_installer_filename("rd-cl-2.0.2+74-windows-x64-install.exe"));
        for n in ["rd-cl-2.0.2+74-windows-x64-install.exe", "rd-cl-auto-EXA-000001-000002-000003-install.exe", "rd-cl-2.0.2-auto-EXA-000001-000002-000003;bad-install.exe", "rd-cl-2.0.2-auto-EXA-000001-000002-000003-install (x).exe"] { assert!(enrollment_code(n).is_none()); }
    }
}
