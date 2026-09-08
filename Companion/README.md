# Exantas RustDesk Technician Companion

## Office account lifecycle update

The native client uses the same Office account for management and support.
The local `codex/office-account-pairing` change calls authenticated
`POST /rustdesk-companion/logout` before clearing local credentials. Deploy
the compatible Office endpoint before distributing a new client. If the server
cannot confirm logout, credentials are retained so the user can retry or revoke
the pairing in Office. Logout does not terminate a RustDesk control session.
The Office recovery reference PowerShell companion separately scopes offline
reports to an Office URL/user UUID. This folder has not been synchronized with
that reference change; do not distribute its old helper as the updated helper.
Native Dart/Flutter build and Windows acceptance are still pending.

## Artifact-only Windows acceptance build

`.github/workflows/office-acceptance-windows.yml` builds only Windows x64
and its Linux bridge/Windows helper dependencies, following the existing
Flutter workflow at base commit `e79a8f1`. It runs on pushes to
`codex/office-account-pairing`; it does not change the main branch or publish
tags, releases, MSI installers, or deployments. All jobs have read-only repository
permissions and do not receive production secrets. Artifacts expire after three days.
This intentionally scoped copy leaves the existing multi-platform release pipeline
unchanged; compare its toolchain/dependency steps with that pipeline before reuse.

Download the `exantas-support-1.4.10-office-test-windows-x64-<run>` artifact
from the successful run. Extract the whole archive, not just `rustdesk.exe`.
Every downloadable Companion change increments both the product version and
the Flutter build number. The acceptance workflow rejects mismatched version
sources before building the package.
`OFFICE-ACCEPTANCE.txt` identifies the source commit/run and `SHA256SUMS.txt`
identifies the executable. This is an unsigned test build, not a new production
release. Do not overwrite an existing installation. The default Office API is
still the online service: verify/configure the test Office destination before
running or logging in. Download/build success does not prove Windows acceptance.

This folder contains the transition/reference technician-side companion source.

The production target is native companion functionality inside the Exantas
Support RustDesk client. Until that native implementation fully replaces this
folder, this PowerShell/WinForms companion remains in the public source tree so
that distributed helper behavior has corresponding source available.

The companion is intentionally a user-session app, not a Windows Service.
Windows services run in session 0 and cannot reliably show the technician
comment popup in the logged-in desktop session.

## Files

- `technician-companion.ps1`: tray companion, Office pairing, pending sessions,
  popup, WebSocket wake-up listener, offline queue, and comment submission.
- `install-technician-companion.vbs`: hidden launcher for installing/running the
  companion without a visible console window.
- `install-technician-companion.cmd`: console fallback launcher.

## Security

The companion stores scoped Office companion tokens under:

```text
%APPDATA%\Exantas\RustDeskCompanion
```

Tokens and queued comments are protected with Windows DPAPI for the current
Windows user. The Office password is used only during pairing and is not stored.

Do not add Office admin credentials, production API tokens, or unattended
passwords to this folder.

## Runtime Contract

The companion calls:

```text
POST /rustdesk-companion/pair
POST /rustdesk-companion/sessions/sync
GET /rustdesk-companion/sessions/pending
POST /rustdesk-companion/sessions/{id}/comment
GET /rustdesk-companion/ws
```

Command prefixes:

- plain text: final result, close and email the customer report
- `~ text`: explicit final result
- `# text`: pending work item, keep the customer case open
- `-` or `- text`: no action and no email

## Native Replacement Target

The native companion must provide the same behavior inside Exantas Support:

- Office login/pairing
- device policy sync
- tray status
- pending session notes
- WebSocket wake-up plus authenticated HTTP polling
- offline queue
- revoke/rotate handling
- diagnostics and log access
