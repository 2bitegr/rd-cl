# Office native sign-in source preparation

## Windows account entry point (2026-10-22)

Settings → Account is the only Windows Office sign-in form. It accepts Office
email/password and delegates to the existing companion login/pair/native-lease
flow. Home retains status, Account navigation and Reports; no Office login,
switch-user, confirmation or logout action runs there on Windows. Account changes
refresh the Home status even when native confirmation fails after pairing.

Account shows the current Office identity, native readiness, explicit confirmation
after uncertain issuance, and Office logout. It serializes UI submissions, clears
the password after a submitted action, displays progress and keeps failures visible.
It does not automatically retry issuance on a timer. Unknown local state blocks
the form; refresh reads local state only. Existing service/daemon authority,
technician/admin checks, DPAPI lease and revocation fences remain unchanged.
An Office user may use multiple personal computers; no shared native password or
fixed technician-to-computer assignment is introduced by this UI change.

If a legacy native access_token exists, the Office form is replaced by an explicit
legacy logout action. This path requires the pinned native logout contract's
HTTP 200 JSON null response before clearing local native credentials. A timeout,
invalid response or rejection preserves them and blocks Office login. A server
acknowledgement is not independent proof of database ownership release: the
existing foreign-owner guard still rejects any unresolved binding. No automatic
user/peer deletion, ID regeneration, SQL edit or ownership adoption is performed.
If a binding remains without a local token, use a separately reviewed legacy
recovery procedure; do not bypass the guard. Native address-book/group login
features outside this Office flow are not migrated by this change.

Non-Windows Account/Home behavior stays as before. Plain-text/HTML HTTP failures
from Office/proxies now produce an HTTP-status error rather than FormatException;
invalid successful responses are rejected. This does not repair a backend 502.

New widget and response tests are included in windows-native-build.py's mandatory
Dart regression list. Native S2 build and Windows UI/DPAPI, legacy migration,
clean Office login/logout, multi-PC and real remote-session acceptance remain
required before claiming delivery/runtime success. No product/dependency version,
server endpoint, schema, production setting or credential change is needed.

Office remains the technician identity. On Windows the paired companion obtains a
five-minute native JWT through the new Office/native-API contract; no separate
RustDesk password is requested. The entire native lease uses the existing Windows
DPAPI store and a distinct local key. Legacy native access_token remains separate.
Preflight checks owner, source ID, Office/native API and expiry before desktop
launch. Refresh/logout serialize with account changes and uncertain issuance
requires explicit confirmation. Reports, enrollment and customer history remain.

Non-Windows targets retain the previous native reader and Office pairing; the new
unified lease is Windows-only until a platform secure-store implementation is
reviewed. No plaintext Office native lease fallback is introduced.

Canonical producer/consumer and disabled configuration contract:
Office docs/OFFICE_RUSTDESK_NATIVE_AUTH.md. New clients require both new server
endpoints before unified auth can succeed. Existing native server MUST_LOGIN and
JWT checks stay enforced. Stateless server revocation is bounded by token expiry
plus server clock tolerance; established sessions are not forcibly disconnected.

Source tests use installed tools/caches only. The specific declined hbb_common
ID-persistence test remains BLOCKED and unchanged. Full native DLL build/DPAPI
integration and real incoming-call/session/audit acceptance are separate gates.
No version bump, download, installation, commit/push or production change here.

Remote Flutter processes reload the encrypted lease from disk to observe refresh
and logout. Native AddressBook/Groups and non-Windows Account headers keep legacy scope;
only native audit calls opt in. Office-native audit ownership uses retained login
history rather than current peer ownership. Bridge JWT lifetime is five minutes;
the client accepts at most 30 seconds of positive clock skew in its upper-bound
check, without changing signed exp. Historical source checks: Windows Flutter32 PASS,
pure Rust1.75/MSVC policy PASS; expanded Dart analysis has no errors and retains
existing warning/info findings. Full native DLL/DPAPI integration remains NOT_RUN.
