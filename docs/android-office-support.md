# Android remote support with Office

2026-10-31 source candidate with a verified local arm64 debug APK. Impact: platform-critical (Office/native credentials,
exact session provenance and existing financial finalization). Not an APK release
or evidence of an Android/provider session. No production session, billing,
configuration, SQL migration, deployment, commit or push was performed.

## Source and architecture

The published rd-cl native implementation is on
`codex/s2-codec-bootstrap-1.4.13`, baseline
`ef1cfefb9c67f149deae3f9e62b1b18a62e6b2ce`. The older rd-cl main
`83c2a29a5` does not contain that implementation. Office baseline is main
`bedf468`. User explicitly approved this task's development/local tests on S2;
existing workstation restrictions still apply to Git publication/deployment.

The Android Support tab reuses the existing Office account widget, RustDesk
RemotePage, touch/mouse/keyboard controls and self-hosted defaults. No telephony,
Caller Popup application, incoming-call notification or automatic launch was added.
The existing generic Android connect gateway also requires Office/native readiness.
Both Android paths reject direct-IP/URI/server overrides, which would bypass the
existing provider audit, while accepting numeric/custom RustDesk IDs.

The existing native staff login (`/desktop/auth/login`, stable phone installation UUID), pairing and native-session/native-logout contracts are reused. Android login does not rotate Web or another native installation's session. Windows continues to call its original login endpoint.
The phone remains signed in across idle time, token expiry, network loss and app
termination until the technician explicitly logs out. No password is retained.
POST `/rustdesk-companion/staff-session` renews a five-minute support-only Office
JWT from the existing unrevoked pairing, without creating admin session rows or
renewing/revoking Windows/Web sessions. The API admits this distinct token type
only to the eight support operations listed in Office's staff-session adapter;
current pairing/actor/role checks apply on every request and mutations recheck
and lock them inside the existing work transaction. Pairing revocation or role
removal still denies access; failure never silently discards the saved login.
Android stores its persistent companion token, renewable support grant, native lease and journals as
AES-256-GCM ciphertext under an application AndroidKeyStore key (API23+).
Flutter's asynchronous storage adapter and Rust's JNI lease reader share this
key. Android22 fails before credentials are submitted. Missing keys, tampering,
plaintext and uncertain native issuance fail closed. Windows continues to use
its existing DPAPI implementation; legacy native credentials stay separate.
No key export, shared password, credential logging or dependency was added.
Android backup is disabled; restored ciphertext without its key is not usable.
Official API reference: https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec

## Session/work authority

Customer search, existing/new work and current connectable computer metadata come
from the existing Office staff APIs. Device authority is reloaded before launch.
A native peer_info event records the exact native session ID as a string in the
existing encrypted lifecycle journal, scoped to actor/API/source/target. A local
close is an observation, never verified duration. Android financial decisions
wait for the imported provider record and `timing_quality=verified` with known
positive duration and end. No client timer or attempt creates an Office session.

After audit import the existing companion work-context/claim APIs link only the
exact audited source to the explicitly selected work, checking original revision,
operator, participant and customer/device/site authority. There is no Windows
handoff, timestamp matching, target-only association or guessed customer.
Lost claim responses resolve through the authoritative exact context. Reconnects
retain distinct native IDs. Unknown peers remain unassigned until an authorized
Office customer/device association and explicit exact work claim are established.
If termination occurs before native identity capture, the local entry remains
unresolved; provider pending records can still be recovered without guessing.

## Four decisions

- **Κανονική χρέωση** sends automatic mode to the existing Office preview and
  finalization endpoints. The user reviews authoritative verified time, net/VAT/
  gross and explicitly confirms the entire work. Prices, overlap, minimum,
  rounding, bands and agreements remain server-owned.
- **Χωρίς χρέωση** uses the same preview/finalization with free mode. Office's
  existing zero-payable report behavior is retained; Android posts no debit.
- **Αργότερα** is the default. Closing the dialog preserves pending state and
  locally encrypted text, without remote finalization or email.
- **Εξαίρεση** on a linked work uses existing ignore/source suppression semantics.
  On an unassigned personal/test source it requires the existing administrator
  permission, a reason and a separate explicit source-exclusion confirmation.
  That existing exclusion covers the source-phone/target pair including future
  connections; customer conflicts are not auto-confirmed. Original audits survive.

The screen uses only the technician's own entered description; choosing an action
explicitly confirms that text/mode for preview. Imported notes are never copied
or interpreted automatically. Preview warnings or incomplete linked sessions
remain pending. Finalization can publish the existing Office report; this mobile
flow explicitly requests no email. Finalization acts on the entire existing work,
including its linked sessions, and the confirmation says so.

Before finalization, the existing journal durably reserves the original request
key/intent. An unconfirmed response blocks a second financial POST. Recovery uses
only the existing GET request endpoint; not_found stays unresolved. Work creation
uses the same durable reservation/recovery mechanism. Existing Office state,
revisions, locks, ledger and source ownership remain authoritative. A later exact
published Office report resolves the phone's pending decision without another
charge. No new billing/session business API, database schema or rustdesk-api change is needed; the support-only authentication lease endpoint is additive.

## Validation and remaining gates

See Office `docs/android-support-validation.md` for the exact source/local results
and manual acceptance. Synthetic Flutter/Node tests, a Kotlin helper compilation
and pure Rust policy tests are complemented by successful current-source native,
full Kotlin/Flutter and arm64 APK builds. Static CRC/signature/provenance/16KB
alignment checks and native Windows artifact maintenance pass. They do not
establish JNI/Keystore execution, installed-app compatibility or provider timing.
Do not package an old librustdesk.so as if it contained this native lease reader.

## Manual acceptance (separate authorization/environment required)

1. Verify the local current-source APK in Desktop Builds/rd-cl/AndroidSupport-20261030
   against BUILD-INFO.json and SHA256SUMS; detailed provenance/manual gates are in
   Office docs/android-support-validation.md. Do not rebuild unchanged passing
   bytes or substitute an older native binary. Install only with authorization on
   the Xiaomi15Ultra/Android16 test phone. Preserve existing app data/signing identity.
2. On an authorized test backend, verify existing Office native-auth/workflow
   prerequisites, provider instance and audited UTC timing. Sign in as a synthetic
   technician on Android23+; test native confirmation failure, legacy logout,
   revoked role/pairing and logout. Inspect only ciphertext persistence; test key
   loss/tampering without resetting any customer's identity.
3. Select a test customer/work/PC; connect over Wi-Fi and cellular and exercise
   mouse, touch, keyboard and remote reboot/reconnect. Confirm exact source phone,
   target, technician, provider/native ID and work link in Office.
4. Disconnect; delay the provider end, kill/restart the app and interrupt network.
   Evidence must remain pending until actual provider completion. Replay duplicate
   events and use two technicians/reconnections; verify one source per exact tuple,
   correct participants and existing overlap rules. No time-proximity linking.
5. Test an unrecognized manual peer and a wrong-customer work: no automatic claim.
   Authorize its device/customer mapping separately, then explicitly claim the
   exact session. Test administrator-only source exclusion with reason/history.
6. On disposable financial fixtures, exercise all four decisions. Compare normal
   preview to Office Web (policy/bands/minimum/rounding/overlap/VAT/agreement).
   Cancel/close/default must not finalize. Free must create no payable debit;
   exclusion must preserve audit and suppress through existing semantics.
7. Drop the finalize/create response after server commit, restart, and recover by
   the original key. Verify one work/report/charge/debit/outbox identity as applicable.
   Finish a deferred work in Office and verify phone reconciliation. Recheck Windows
   DPAPI/native login, Caller Popup handoff, Office Web and portal reporting.

No Definition-of-Done claim is made until these Android/provider acceptance gates
have actual evidence. Production billing, real customer sessions, migrations and
rollout remain separately authorized actions.


## Android home and source registration — code2076

The mobile home now displays this phone's native ID with copy, account/native
readiness, quick connect, and three sections: recent connections, customers and
pending decisions. Recent entries reuse RustDesk's existing recentPeersModel,
including alias/platform/availability; availability is not verified support time.
A recent connection follows the manual-peer path and does not inherit a customer
or work assignment. The account controls remain the existing implementation.

Outgoing-only Android does not run the incoming-service sysinfo sync. Before
requesting a new native lease, Android now submits this installation's actual
native ID and UUID to the provider's existing /api/sysinfo endpoint and requires
its acknowledgement. It sends no Office credentials or target/customer/work
identity, fences account changes, and preserves the native bridge's ownership
checks. Windows flow is unchanged. A network/registration failure retains login.

Read-only runtime inspection found the Office staff-session adapter absent from
the active API: this causes the customer-search Route not found response. APK
installation alone cannot add that route. See Office docs/android-support-api-handoff.md.
The new source-registration preflight is locally verified; the reported phone502
is not declared resolved until a phone/native-provider retest succeeds.

Code2076 is an arm64 debug upgrade, same package and signing certificate as2075.
Retain app data; never uninstall to force an update. The earlier2075 package is
retained for identified rollback/comparison. Current focused verification covers
23 unique synthetic cases (source5, home4, response7, native-auth7), analyzer
0errors/0warnings, build and APK CRC/signature/16KB checks. Physical Android,
Keystore execution, live provider audit and financial acceptance remain pending.


## Mobile home refinement — code2077

Android account/home UI now reads the existing native-confirmation fence
separately from native readiness. Normal five-minute native-lease expiry leaves
Office signed in, shows automatic renewal in Account, and does not show a manual
confirmation CTA. The existing connect path still renews before connecting.
An unconfirmed issuance keeps its explicit retry and never gains automatic
issuance replay. Android passes the new presentation flag explicitly; unspecified
Account status preserves the existing Windows behavior. No credential, lease,
provider, duration or financial policy changes.

The existing Material home uses quieter surfaces, a compact Office/phone-ID
summary, prominent ID entry, equal-width recent/customer/pending sections and
readable native recent-peer rows. Source history/availability/association semantics
are unchanged. User-facing errors omit the redundant Exception prefix. No new
assets, dependencies or separate history store. References reviewed:
https://rustdesk.com/docs/en/client/android/ and
https://support.anydesk.com/anydesk-overview .

Six widget scenarios cover320/390/430 light/dark with1.3text at320, ID copy,
manual/recent connect and section switching. Separate busy/recovery checks plus
existing Account regressions and two new lease-expiry/recovery checks give
16focused passing cases. Physical Xiaomi16 acceptance remains separate.
