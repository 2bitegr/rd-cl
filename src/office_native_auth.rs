//! Windows DPAPI / Android Keystore reader for the Office native lease. The existing native
//! access_token option and native account UI remain independent.
use hbb_common::config::{Config, LocalConfig};
use serde_derive::Deserialize;
use std::time::{SystemTime, UNIX_EPOCH};

pub const LEASE_KEY: &str = "exantas.office.native_lease";
pub const READY_KEY: &str = "exantas.office.native_ready";

#[derive(Deserialize)]
struct Lease {
    access_token: String,
    expires_at: u64,
    office_user_id: String,
    pairing_id: String,
    peer_id: String,
    native_api_base: String,
    office_api_base: String,
}

#[cfg(windows)]
fn unprotect(stored: &str) -> Option<String> {
    use hbb_common::sodiumoxide::base64;
    use winapi::um::{dpapi::{CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN}, wincrypt::DATA_BLOB, winbase::LocalFree};
    use std::{ptr, slice};
    let payload = stored.strip_prefix("dpapi:v1:")?;
    if payload.len() > 32768 { return None; }
    let mut bytes = base64::decode(payload, base64::Variant::Original).ok()?;
    let mut input = DATA_BLOB { cbData: bytes.len() as u32, pbData: bytes.as_mut_ptr() };
    let mut output = DATA_BLOB { cbData: 0, pbData: ptr::null_mut() };
    unsafe {
        if CryptUnprotectData(&mut input, ptr::null_mut(), ptr::null_mut(), ptr::null_mut(), ptr::null_mut(), CRYPTPROTECT_UI_FORBIDDEN, &mut output) == 0 { return None; }
        if output.pbData.is_null() { return None; }
        let plain = String::from_utf8(slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec()).ok();
        LocalFree(output.pbData as _);
        plain
    }
}

#[cfg(target_os = "android")]
fn unprotect(stored: &str) -> Option<String> {
    if !stored.starts_with("keystore:v1:") || stored.len() > 32768 { return None; }
    scrap::android::office_unprotect(stored)
}

// Remote Flutter windows are separate processes: reload the encrypted lease
// rather than keeping the token cached before a refresh/logout/account switch.
pub fn access_token() -> String {
    let actor = LocalConfig::get_option_from_file("exantas.office.user_id");
    if actor.is_empty() { return LocalConfig::get_option("access_token"); }
    // An Office owner cannot silently inherit a different native account.
    if LocalConfig::get_option_from_file("exantas.office.companion_token").is_empty() { return String::new(); }
    let Some(plain) = unprotect(&LocalConfig::get_option_from_file(LEASE_KEY)) else { return String::new(); };
    let Ok(lease) = serde_json::from_str::<Lease>(&plain) else { return String::new(); };
    let configured = LocalConfig::get_option_from_file("exantas.office.api_base");
    let office_api = if configured.is_empty() { "https://api-office.exantas.eu/api/v1" } else { &configured };
    if lease.office_api_base != office_api { return String::new(); }
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|v| v.as_secs()).unwrap_or(0);
    let api = crate::get_api_server(Config::get_option("api-server"), Config::get_option("custom-rendezvous-server"));
    if crate::office_native_policy::current(lease.expires_at, now, &lease.office_user_id, &actor,
            &lease.peer_id, &Config::get_id(), &lease.native_api_base, &api)
        && !lease.access_token.is_empty() && !lease.pairing_id.is_empty() {
        lease.access_token
    } else { String::new() }
}
