// Native contract probe: production verifier/barrier bodies are inserted unchanged.
// No service, machine registration or production update barrier is executed.
#![allow(dead_code)]
mod hbb_common {
    pub use anyhow;
    pub use sodiumoxide;
    pub type ResultType<T> = Result<T, anyhow::Error>;
}
use anyhow::bail;
use hbb_common::{sodiumoxide::base64, ResultType};
use serde_json::{json, Value};
use std::{fs, path::{Path, PathBuf}, process::Command};
use std::os::windows::process::CommandExt;
#[path = "office_update_policy.rs"]
mod office_update_policy;
const VERSION: &str = "3.1.2";
const EVENT: &str = "Global\\ExantasRdclUpdateBarrier";
fn root() -> ResultType<PathBuf> {
    let path = PathBuf::from(std::env::var_os("RDCL_NATIVE_FIXTURE").ok_or_else(|| anyhow::anyhow!("fixture_missing"))?);
    if !path.is_dir() { bail!("fixture_missing"); }
    Ok(path)
}
fn verify_root() -> ResultType<()> { root().map(|_| ()) }
fn powershell() -> PathBuf { PathBuf::from("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe") }

// PRODUCTION_FUNCTIONS

fn actual_verifier_accepts_signed_bytes_and_rejects_malformed_or_tampered_inputs() {
    use sodiumoxide::crypto::sign;
    sodiumoxide::init().unwrap();
    let (public, secret) = sign::gen_keypair();
    let folder = root().unwrap();
    let key = base64::encode(&public.0, base64::Variant::Original);
    let machine = json!({"trusted_keys":{"fixture":key}});
    fs::write(folder.join("machine.json"), serde_json::to_vec(&machine).unwrap()).unwrap();
    let now = chrono::Utc::now();
    let payload = json!({"schema":1,"protocol":2,"platform":"windows-x64","version":"3.2.0",
        "verification":"office-ed25519-v1","sha256":"a".repeat(64),
        "url":format!("https://office.exantas.eu/downloads/rd-cl/rd-cl-3.2.0-{}-windows-x64-install.exe","a".repeat(12)),
        "issued_at":(now-chrono::Duration::seconds(1)).to_rfc3339(),
        "expires_at":(now+chrono::Duration::hours(1)).to_rfc3339(),
        "files":[{"path":"rustdesk.exe"},{"path":"librustdesk.dll"},{"path":"flutter_windows.dll"},
                 {"path":"data/app.so"},{"path":"data/icudtl.dat"}]});
    let bytes = serde_json::to_vec(&payload).unwrap();
    let signed = json!({"schema":1,"key_id":"fixture",
        "payload":base64::encode(&bytes,base64::Variant::Original),
        "signature":base64::encode(sign::sign_detached(&bytes,&secret).as_ref(),base64::Variant::Original)});
    let path = folder.join("envelope.json");
    fs::write(&path,serde_json::to_vec(&signed).unwrap()).unwrap();
    assert_eq!(verify_envelope(&path).unwrap()["version"],"3.2.0");
    let mut bad_machine = machine.clone();
    bad_machine["trusted_keys"]["fixture"] = json!("%malformed-private-input%");
    fs::write(folder.join("machine.json"),serde_json::to_vec(&bad_machine).unwrap()).unwrap();
    assert_eq!(verify_envelope(&path).unwrap_err().to_string(),"invalid_signer_encoding");
    bad_machine["trusted_keys"]["fixture"] = json!(base64::encode(&[1,2],base64::Variant::Original));
    fs::write(folder.join("machine.json"),serde_json::to_vec(&bad_machine).unwrap()).unwrap();
    assert_eq!(verify_envelope(&path).unwrap_err().to_string(),"invalid_signer");
    fs::write(folder.join("machine.json"),serde_json::to_vec(&machine).unwrap()).unwrap();
    for (field, value, error) in [
        ("payload","%malformed-private-input%".to_string(),"invalid_payload_encoding"),
        ("signature","%malformed-private-input%".to_string(),"invalid_signature_encoding"),
        ("signature",base64::encode(&[1,2],base64::Variant::Original),"invalid_signature_size"),
        ("payload",base64::encode(b"{}",base64::Variant::Original),"invalid_signature"),
    ] {
        let mut bad = signed.clone();bad[field] = json!(value);
        fs::write(&path,serde_json::to_vec(&bad).unwrap()).unwrap();
        assert_eq!(verify_envelope(&path).unwrap_err().to_string(),error,"{}",field);
    }
}

fn main() {
    actual_verifier_accepts_signed_bytes_and_rejects_malformed_or_tampered_inputs();
    println!("Seven actual envelope cases PASS; production barrier compiled but never executed");
}
