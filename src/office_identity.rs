//! Office-authorized local ID maintenance. No UI/CLI flag grants this authority.
use hbb_common::{config::Config, rand::Rng, tokio};
use serde_derive::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    fmt,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

const OFFICE_API: &str = "https://api-office.exantas.eu/api/v1";

#[derive(Clone, Serialize, Deserialize)]
pub struct Request {
    pub api_base: String,
    pub companion_token: String,
    pub office_user_id: String,
    pub expected_id: String,
}

impl fmt::Debug for Request {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("OfficeIdentityRequest(<redacted>)")
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Outcome {
    pub status: String,
    pub code: String,
    pub office_signed_out: bool,
    pub old_id: String,
    pub new_id: String,
    pub backup_path: String,
}

impl Outcome {
    pub fn error(code: &str, signed_out: bool) -> Self {
        Self {
            status: "error".into(),
            code: code.into(),
            office_signed_out: signed_out,
            old_id: String::new(),
            new_id: String::new(),
            backup_path: String::new(),
        }
    }
}

fn valid_request(r: &Request) -> bool {
    r.api_base.trim_end_matches('/') == OFFICE_API
        && r.companion_token.starts_with("rcomp_")
        && (40..=128).contains(&r.companion_token.len())
        && r.companion_token
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        && hbb_common::uuid::Uuid::parse_str(&r.office_user_id).is_ok()
        && (6..=10).contains(&r.expected_id.len())
        && r.expected_id.bytes().all(|b| b.is_ascii_digit())
}

fn confirms_authority(body: &Value, r: &Request) -> bool {
    // Office's existing capabilities handler checks active support role and the
    // unrevoked pairing, even when workflow-v2 itself is disabled.
    body["status"] == "ok"
        && body["office_user_id"].as_str() == Some(r.office_user_id.as_str())
        && body["pairing_id"]
            .as_str()
            .and_then(|s| hbb_common::uuid::Uuid::parse_str(s).ok())
            .is_some()
}

async fn response_json(response: reqwest::Response) -> Result<Value, &'static str> {
    if !response.status().is_success() {
        return Err("office_login_required");
    }
    let mut response = response;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "office_unavailable")? {
        if bytes.len() + chunk.len() > 65536 {
            return Err("office_response_invalid");
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| "office_response_invalid")
}

static RESET_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

// Reserve the operation without holding a mutex across network awaits. Dropping
// the request (including cancellation) releases this reservation.
struct ResetReservation<'a>(&'a AtomicBool);
impl<'a> ResetReservation<'a> {
    fn try_new(state: &'a AtomicBool) -> Option<Self> {
        state
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .ok()
            .map(|_| Self(state))
    }
}
impl Drop for ResetReservation<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

fn ready(r: &Request) -> Result<(), &'static str> {
    if !crate::common::is_server() || !crate::platform::is_installed() {
        return Err("installed_service_required");
    }
    if Config::get_id() != r.expected_id {
        return Err("id_changed");
    }
    if !crate::updater::has_no_active_conns() {
        return Err("active_sessions");
    }
    Ok(())
}

pub(crate) async fn reset(r: Request) -> Outcome {
    if !valid_request(&r) {
        return Outcome::error("office_login_required", false);
    }
    // Reject overlapping submissions rather than queueing an old authorization.
    let operation = match ResetReservation::try_new(&RESET_IN_PROGRESS) {
        Some(reservation) => reservation,
        None => return Outcome::error("operation_in_progress", false),
    };
    if let Err(code) = ready(&r) {
        return Outcome::error(code, false);
    }
    let client = match reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(10))
        .build()
    {
        Ok(client) => client,
        Err(_) => return Outcome::error("office_unavailable", false),
    };
    let token = r.companion_token.clone();
    let check_request = r.clone();
    let old_id = r.expected_id.clone();
    let write_request = r.clone();
    perform(
        r,
        move |logout| {
            let client = client.clone();
            let token = token.clone();
            async move {
                let request = if logout {
                    client
                        .post(format!("{OFFICE_API}/rustdesk-companion/logout"))
                        .json(&json!({}))
                } else {
                    client.get(format!(
                        "{OFFICE_API}/rustdesk-companion/workflow-capabilities"
                    ))
                };
                let response = request
                    .bearer_auth(token)
                    .send()
                    .await
                    .map_err(|_| "office_unavailable")?;
                response_json(response).await
            }
        },
        || ready(&check_request),
        move |new_id| {
            let new_id = new_id.to_owned();
            async move {
                // Filesystem/ACL work belongs on the blocking pool, not the
                // service's async transport executor. No Config lock crosses await.
                tokio::task::spawn_blocking(move || {
                    // Retain ownership even if the async caller is cancelled
                    // after dispatch; another reset cannot overlap this worker.
                    let _reservation = operation;
                    ready(&write_request)?;
                    let backup = Config::reset_id_with_backup(
                        &old_id,
                        &new_id,
                        crate::platform::set_private_runtime_file_permissions,
                    )
                    .map_err(|_| "config_write_failed")?;
                    crate::rendezvous_mediator::RendezvousMediator::restart();
                    Ok(backup.to_string_lossy().into_owned())
                })
                .await
                .map_err(|_| "config_write_failed")?
            }
        },
    )
    .await
}

async fn perform<Send, Response, Check, Write, WriteResponse>(
    r: Request,
    send: Send,
    check: Check,
    write: Write,
) -> Outcome
where
    Send: Fn(bool) -> Response,
    Response: std::future::Future<Output = Result<Value, &'static str>>,
    Check: Fn() -> Result<(), &'static str>,
    Write: FnOnce(&str) -> WriteResponse,
    WriteResponse: std::future::Future<Output = Result<String, &'static str>>,
{
    if let Err(code) = check() {
        return Outcome::error(code, false);
    }
    match send(false).await {
        Ok(body) if confirms_authority(&body, &r) => {}
        Ok(_) => return Outcome::error("office_login_required", false),
        Err(code) => return Outcome::error(code, false),
    }
    if let Err(code) = check() {
        return Outcome::error(code, false);
    }
    // Close the old peer pairing before writing. Ambiguous logout is not retried.
    if !matches!(send(true).await,Ok(ref body) if body["status"]=="ok") {
        return Outcome::error("logout_unconfirmed", true);
    }
    if let Err(code) = check() {
        return Outcome::error(code, true);
    }
    let new_id = loop {
        let id = hbb_common::rand::thread_rng()
            .gen_range(1_000_000_000u64..2_000_000_000)
            .to_string();
        if id != r.expected_id {
            break id;
        }
    };
    match write(&new_id).await {
        Ok(backup_path) => Outcome {
            status: "ok".into(),
            code: "id_generated".into(),
            office_signed_out: true,
            old_id: r.expected_id,
            new_id,
            backup_path,
        },
        Err(code) => Outcome::error(code, true),
    }
}

pub(crate) async fn request(r: Request) -> Outcome {
    let outcome = async {
        let mut connection = match crate::ipc::connect(1000, "").await {
            Ok(connection) => connection,
            Err(_) => return Some(Outcome::error("installed_service_required", false)),
        };
        if connection
            .send(&crate::ipc::Data::Config((
                "office-identity-reset-version".into(),
                None,
            )))
            .await
            .is_err()
        {
            return Some(Outcome::error("installed_service_required", false));
        }
        match connection.next_timeout(3000).await {
            Ok(Some(crate::ipc::Data::Config((name, Some(version)))))
                if name == "office-identity-reset-version" && version == "1" => {}
            _ => return Some(Outcome::error("installed_service_required", false)),
        }
        connection
            .send(&crate::ipc::Data::OfficeIdentityReset(r))
            .await
            .ok()?;
        match connection.next_timeout(30000).await.ok()? {
            Some(crate::ipc::Data::OfficeIdentityResetResult(result)) => Some(result),
            _ => None,
        }
    }
    .await;
    // The daemon may have committed even if its reply was lost. The UI must
    // require inspection and a fresh login, with no automatic retry.
    outcome.unwrap_or_else(|| Outcome::error("result_unconfirmed", true))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn request_fixture() -> Request {
        Request {
            api_base: OFFICE_API.into(),
            companion_token: format!("rcomp_{}", "x".repeat(43)),
            office_user_id: "28f1ddbf-1c8c-4992-8292-9bbd2e1be40c".into(),
            expected_id: "1234567".into(),
        }
    }
    #[test]
    fn operation_reservation_rejects_overlap_and_releases_on_drop() {
        let state = AtomicBool::new(false);
        let first = ResetReservation::try_new(&state).unwrap();
        assert!(ResetReservation::try_new(&state).is_none());
        drop(first);
        assert!(ResetReservation::try_new(&state).is_some());
        assert!(!state.load(Ordering::Acquire));
    }
    #[test]
    fn authority_is_live_server_identity_not_local_role_text() {
        let r = request_fixture();
        let mut body = json!({"status":"ok","office_user_id":r.office_user_id,"pairing_id":"6dc76020-01ea-4fac-96dc-4cc047a9b302","enabled":false});
        assert!(confirms_authority(&body, &r));
        body["office_user_id"] = json!("different-user");
        assert!(!confirms_authority(&body, &r));
        assert!(!confirms_authority(
            &json!({"status":"ok","support_role":"technician"}),
            &r
        ));
    }
    #[test]
    fn rejects_untrusted_origins_and_malformed_credentials() {
        let mut r = request_fixture();
        assert!(valid_request(&r));
        for url in [
            "http://api-office.exantas.eu/api/v1",
            "https://evil.invalid/api/v1",
            "https://api-office.exantas.eu/api/v1?redirect=1",
        ] {
            r.api_base = url.into();
            assert!(!valid_request(&r));
        }
        r = request_fixture();
        r.companion_token = "rdev_customer".into();
        assert!(!valid_request(&r));
        r = request_fixture();
        r.expected_id = "..\\config".into();
        assert!(!valid_request(&r));
    }
    #[tokio::test]
    async fn expired_authority_never_logs_out_or_writes() {
        let writes = std::cell::Cell::new(0);
        let sends = std::cell::Cell::new(0);
        let result = perform(
            request_fixture(),
            |_| {
                sends.set(sends.get() + 1);
                async { Err("office_login_required") }
            },
            || Ok(()),
            |_| async {
                writes.set(writes.get() + 1);
                Ok(String::new())
            },
        )
        .await;
        assert_eq!(result.code, "office_login_required");
        assert_eq!(writes.get(), 0);
        assert_eq!(sends.get(), 1);
    }
    #[tokio::test]
    async fn uncertain_logout_does_not_write_or_replay() {
        let r = request_fixture();
        let actor = r.office_user_id.clone();
        let writes = std::cell::Cell::new(0);
        let sends = std::cell::Cell::new(0);
        let result=perform(r, |logout| {
            sends.set(sends.get()+1);let actor=actor.clone();
            async move {if logout {Err("office_unavailable")} else {Ok(json!({"status":"ok","office_user_id":actor,"pairing_id":"6dc76020-01ea-4fac-96dc-4cc047a9b302"}))}}
        }, || Ok(()), |_| async {writes.set(writes.get()+1);Ok(String::new())}).await;
        assert_eq!(result.code, "logout_unconfirmed");
        assert!(result.office_signed_out);
        assert_eq!(sends.get(), 2);
        assert_eq!(writes.get(), 0);
    }
    #[tokio::test]
    async fn active_connection_after_logout_prevents_identity_write() {
        let r = request_fixture();
        let actor = r.office_user_id.clone();
        let checks = std::cell::Cell::new(0);
        let result=perform(r, |logout| {let actor=actor.clone();async move {Ok(if logout {json!({"status":"ok"})} else {json!({"status":"ok","office_user_id":actor,"pairing_id":"6dc76020-01ea-4fac-96dc-4cc047a9b302"})})}},
            || {checks.set(checks.get()+1);if checks.get()==3 {Err("active_sessions")} else {Ok(())}},
            |_| async {panic!("must not write with active sessions")}).await;
        assert_eq!(result.code, "active_sessions");
        assert!(result.office_signed_out);
    }
    #[tokio::test]
    async fn confirmed_authority_and_logout_write_once() {
        let r = request_fixture();
        let actor = r.office_user_id.clone();
        let writes = std::cell::Cell::new(0);
        let result=perform(r, |logout| {let actor=actor.clone();async move {Ok(if logout {json!({"status":"ok"})} else {json!({"status":"ok","office_user_id":actor,"pairing_id":"6dc76020-01ea-4fac-96dc-4cc047a9b302"})})}},
            || Ok(()), |id| {assert!(id.parse::<u64>().unwrap()>=1_000_000_000);async {writes.set(writes.get()+1);Ok("synthetic-backup".into())}}).await;
        assert_eq!(result.status, "ok");
        assert_eq!(writes.get(), 1);
        assert!(result.office_signed_out);
    }
    #[test]
    fn bridge_rejects_incomplete_request_without_contacting_service() {
        let reply = crate::flutter_ffi::main_regenerate_office_id("{}".into());
        let reply: Value = serde_json::from_str(&reply).unwrap();
        assert_eq!(reply["code"], "office_login_required");
        assert_eq!(reply["office_signed_out"], false);
    }
    #[tokio::test]
    async fn bridge_never_creates_a_nested_runtime() {
        let reply = crate::flutter_ffi::main_regenerate_office_id(
            serde_json::to_string(&request_fixture()).unwrap(),
        );
        let reply: Value = serde_json::from_str(&reply).unwrap();
        assert_eq!(reply["code"], "invalid_call_context");
        assert_eq!(reply["office_signed_out"], false);
    }
    #[test]
    fn request_debug_never_exposes_credentials() {
        let r = request_fixture();
        assert!(!format!("{r:?}").contains(&r.companion_token));
    }
}
