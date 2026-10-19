# Office native sign-in source preparation

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
and logout. General native Account/AddressBook/Groups headers keep legacy scope;
only native audit calls opt in. Office-native audit ownership uses retained login
history rather than current peer ownership. Bridge JWT lifetime is five minutes;
the client accepts at most 30 seconds of positive clock skew in its upper-bound
check, without changing signed exp. Current source checks: Windows Flutter32 PASS,
pure Rust1.75/MSVC policy PASS; expanded Dart analysis has no errors and retains
existing warning/info findings. Full native DLL/DPAPI integration remains NOT_RUN.
