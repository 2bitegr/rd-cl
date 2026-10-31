//! Pure native credential boundary, independent of persistence/platform APIs.
pub fn current(expiry: u64, now: u64, owner: &str, actor: &str, source: &str, peer: &str, issuer: &str, api: &str) -> bool {
    !actor.is_empty() && !peer.is_empty() && !api.is_empty() && owner == actor && source == peer
        && issuer.trim_end_matches('/') == api.trim_end_matches('/')
        && expiry > now && expiry <= now.saturating_add(330)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn owner_peer_provider_and_expiry_are_all_required() {
        assert!(current(1100,1000,"a","a","p","p","https://native.invalid","https://native.invalid/"));
        assert!(!current(1100,1000,"a","b","p","p","https://native.invalid","https://native.invalid"));
        assert!(!current(1100,1000,"a","a","p","q","https://native.invalid","https://native.invalid"));
        assert!(!current(1100,1000,"a","a","p","p","https://native.invalid","https://other.invalid"));
        assert!(!current(1100,1100,"a","a","p","p","https://native.invalid","https://native.invalid"));
        assert!(!current(1100,769,"a","a","p","p","https://native.invalid","https://native.invalid"));
        assert!(!current(1100,1000,"","","p","p","https://native.invalid","https://native.invalid"));
    }
}
