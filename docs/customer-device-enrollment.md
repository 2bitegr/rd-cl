# Customer computer enrollment —2.0.1+73 candidate

User-authorized repair of the broken Office installation flow. The prior
2.0.0+72 EXE had an enrollment method with no reachable customer settings panel.
Office1.12.17 adds a public /install/:code page and read-only capability preview.
It advertises only an explicitly configured, verified compatible installer.
This source candidate requires a new S2 build; no native artifact is claimed.

## Customer path and authority

On Windows, the page transfers its existing capability through the registered
exantas-support-enroll://install action. A dialog previews the exact customer
without retyping and the technician completes the association. Settings → Account
also offers a recovery panel separate from staff sign-in. The customer has no
confirmation step. No Office staff credentials are requested. Non-Windows account UI is unchanged.

POST /api/v1/rustdesk-devices/installation-info checks an active link/customer
without consuming a use or creating a device. Contract1 returns enrollment_id,
customer_id, customer_name and unattended_enabled. Enrollment sends those exact
expected values under the existing server transaction. Old Office versions do
not satisfy this preview contract; deploy the coordinated API before live use.

The shared native auth fence serializes staff and customer identity changes.
Existing managed/staff/legacy identity or a pending enrollment blocks a new code.
The durable pre-request attempt captures API/peer/customer/link/access scope.
A timeout or unknown committed result is not retried after refresh or restart.
Known pre-write server rejections can clear the attempt. An unconfirmed result
with no returned grant requires support review, not another code redemption.

Confirmed metadata is durable before the device token is stored through the
existing DPAPI store. Credential completion uses the captured HTTPS API, exact
peer/token/attempt and one protected per-device password. An explicit completion
button resumes the same grant and secret after interrupted settings/credential
writes; it never enrolls again or clears existing access on a lost reply. The
API rejects active device-token replacement and foreign-customer reassignment;
same-customer revoked re-enrollment retains record identity with fresh credentials.
Malformed HTTP payloads are not printed because they may contain credentials.

## Build and verification boundary

Product/package candidate2.0.1+73 updates root/portable Cargo, Flutter and native
profile/product metadata only. Dependencies, locks other than product package
versions, remote session protocol/FFI, canonical icons and codec/tool/SDK pins are retained.
A separate Windows installer URI registration carries the existing link code to
a strict native preview dialog; it cannot mutate API origin or remote settings.
Cold/warm routing is required native acceptance; raw launch/URI logs are redacted.
The bootstrap product label changes; genuine matching codec evidence is reusable.
The new widget/preview tests are in the mandatory native Dart regression list.

Cloud guards82 PASS/8 platform SKIP and eight changed Dart files syntax PASS.
Widget behavior/analyzer and Windows build/EXE/runtime/DPAPI/service/installation
remain NOT_RUN here. The current source replaces the outstanding af37 handoff,
but cannot advance the last completed1c7cff12 build baseline without S2 receipts.
Preserve that completed2.0.0+72 package, failed b948 evidence and compatible warm
Cargo/Flutter/vcpkg/SDK22621 state. Follow windows-s2-build-handoff.md for one
exact published-SHA guarded build and verified package/maintenance gates.

Every S2 prompt for changed rd-cl also carries the latest-only hosting phase per
Office docs/rdcl-installer-hosting.md. After native build/maintenance and actual
owned Windows acceptance, use that reviewed publisher through existing verified
server access. API/Web share one dedicated read-only installer volume; API reads
current.json and verifies real bytes. Public HTTPS byte/hash check precedes the
atomic active pointer and removal of the sole previous manifest-owned EXE.
No old packages are retained on the hosting server; preserve them on S2 instead.
Native or server access gaps stay explicitly pending. No invented URL or old EXE
substitution is allowed. Existing MSI packaging is not selected:keep the supported
interactive EXE and its ownership/upgrade checks. Current baseline is unsigned;
report actual signing, do not imply a certificate was acquired.

No SQL migration, billing/report rewrite, email or remote session is part of this
repair. Already applied Office migrations must not be replayed. Final Dokploy
rollout remains the user's action and separate from scoped installer publication.
