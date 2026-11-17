//! Dependency-free decisions shared by the Windows integration and fixture tests.
pub fn newer(next: &str, current: &str) -> bool {
    fn parts(version: &str) -> Option<Vec<u32>> {
        let parts: Option<Vec<u32>> = version
            .split('.')
            .map(|p| {
                if p.is_empty()
                    || p.len() > 9
                    || (p.len() > 1 && p.starts_with('0'))
                    || !p.bytes().all(|b| b.is_ascii_digit())
                {
                    None
                } else {
                    p.parse().ok()
                }
            })
            .collect();
        parts.filter(|p| p.len() == 3)
    }
    match (parts(next), parts(current)) {
        (Some(a), Some(b)) => a > b,
        _ => false,
    }
}

/// Only the explicitly signed Office policy is supported; no hash-only fallback.
pub fn own_signature_policy(value: Option<&str>, legacy_publisher: bool) -> bool {
    value == Some("office-ed25519-v1") && !legacy_publisher
}

pub fn safe_path(path: &str) -> bool {
    !path.is_empty()
        && path.len() <= 240
        && !path.contains('\\')
        && path.split('/').all(|part| {
            let lower = part.to_ascii_lowercase();
            let base = lower.split('.').next().unwrap_or("");
            !part.is_empty()
                && part != "."
                && part != ".."
                && !part.ends_with('.')
                && !part.ends_with(' ')
                && part
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_. -".contains(&b))
                && ![
                    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6",
                    "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7",
                    "lpt8", "lpt9",
                ]
                .contains(&base)
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn versions() {
        assert!(newer("3.2.0", "3.1.2"));
        assert!(!newer("3.1.2", "3.1.2"));
        assert!(!newer("3.0.0", "3.1.2"));
    }
    #[test]
    fn invalid_versions() {
        for v in [
            "3.1",
            "3.1.2.3",
            "x.1.2",
            "3..2",
            "3.1.-1",
            "03.1.2",
            "1000000000.1.2",
        ] {
            assert!(!newer(v, "3.1.2"));
        }
    }
    #[test]
    fn signature_policy() {
        assert!(own_signature_policy(Some("office-ed25519-v1"), false));
        for value in [None, Some(""), Some("none"), Some("hash-only"), Some("authenticode")] {
            assert!(!own_signature_policy(value, false));
        }
        assert!(!own_signature_policy(Some("office-ed25519-v1"), true));
    }
    #[test]
    fn paths() {
        assert!(safe_path("data/flutter_assets/assets/icon.png"));
        for p in [
            "../x", "C:/x", "a\\b", "a//b", "CON.txt", "nul", "a/b.", "x:stream",
        ] {
            assert!(!safe_path(p), "{}", p);
        }
    }
}
