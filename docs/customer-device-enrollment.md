# Automatic customer installation —2.0.2+74 candidate

The2026-10-28 user-approved automatic flow is specified in Office
docs/rdcl-automatic-enrollment.md and docs/rdcl-installer-hosting.md. Copy a device
link in the customer card,paste it in the customer browser,install the shared EXE.
Successful Windows install passes its peer-bound capability to the app;it enrolls
and acknowledges local setup automatically. Office confirms only after that ACK.
Many contacts/callers share one computer/token;no per-contact re-enrollment.
The common download has no enrollment context. Attended policy is the default.
No new SQL/dependencies/remote session protocol. Client HTTP completion is
idempotent;pre-POST bootstrap is protected/short-lived and post ambiguity never
replays enrollment. Confirmed-grant completion can safely resume on restart.

This source needs a new exact-SHA S2 build;completed4c6787922.0.1+73 remains the
retained baseline. Hosting after verified package/maintenance may record native
acceptance NOT_RUN;no unavailable VM prerequisite and no fabricated runtime PASS.
The following2.0.1 manual-link history remains compatible.

# Customer computer enrollment —2.0.1+73

User-authorized repair of the broken Office installation flow. The prior
2.0.0+72 EXE had an enrollment method with no reachable customer settings panel.
Office1.12.17 adds a public /install/:code page and read-only capability preview.
It advertises only an explicitly configured, verified compatible installer.
User S2 receipt received2026-10-28 confirms build/package/maintenance PASS at
4c6787926a46a2a981f1b251b0223c8853fce54b. Windows acceptance and hosting pending;
no new build for unchanged source. See the current handoff guide baseline.

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
remain NOT_RUN locally. User S2 receipt now advances the completed build baseline
to4c678792:Dart80PASS,analyzer0ERROR/0WARNING/30INFO,native/EXE/ZIP/integrity and
maintenance PASS;122checksum entries. This does not establish runtime acceptance.
Preserve that completed2.0.0+72 package, failed b948 evidence and compatible warm
Cargo/Flutter/vcpkg/SDK22621 state. Follow windows-s2-build-handoff.md for one
exact published-SHA guarded build and verified package/maintenance gates.

Every S2 prompt for changed rd-cl also carries the latest-only hosting phase per
Office docs/rdcl-installer-hosting.md. After verified native build/maintenance and honest native acceptance status, use that reviewed publisher through existing verified
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

## S2 analyzer correction —2026-10-27

Candidate87e01f40 was not built:analyzer reported4warnings (protected and
visibleForTesting for two external ChangeNotifier.notifyListeners calls).
The corrected source puts notifyListeners inside its owning subclass; the service
exposes Listenable for existing home-page listeners and a public notification
method for both producers. Subscription identity, synchronous notification and
finally behavior are preserved. Two application hashes change; version2.0.1+73,
codecs/SDK/tools/dependencies/icons are retained. Pinned S2 analyzer must pass
before native compilation; no local analyzer/native PASS is claimed.
The failed attempt is preserved. S2 also reports no disposable Windows VM and
live API1.12.16 without installer storage/config/route. Actual acceptance/hosting
remain pending; never replace the completed build baseline with this failure.

Fresh cloud correction checks:82guards PASS/8platform SKIP;3Dart files syntax
PASS. These do not run or replace the pinned Flutter analyzer.

User confirmed no disposable Windows environment;acceptance remains NOT_RUN and
hosting NOT_PUBLISHED. No rebuild is requested. Proposed automatic enrollment
from contact association/download is not in this package;current installation
link still supplies the activation capability. Copy/install of the shared EXE
alone and manual contact mapping do not install the managed-device token.
