# Exantas RustDesk Technician Companion

## Office account lifecycle update

The native client uses the same Office account for management and support.
The local `codex/office-account-pairing` change calls authenticated
`POST /rustdesk-companion/logout` before clearing local credentials. Deploy
the compatible Office endpoint before distributing a new client. If the server
cannot confirm logout, credentials are retained so the user can retry or revoke
the pairing in Office. Logout does not terminate a RustDesk control session.
The PowerShell companion now scopes encrypted v2 markers and offline queue
holds to the canonical Office API, authenticated principal, pairing and peer.
It hydrates existing configuration only from authenticated capabilities; missing
scope fails closed. V2-bound/unassigned/pending/excluded rows never fall through
to legacy report submission. Old v1 queued payloads retain their original meaning
and remain encrypted while held for Office review. Full native Windows client
build and physical acceptance are still pending.

## Local Windows acceptance builds

All eleven GitHub Actions workflows are removed from this fork's source at the
user's request (2026-10-10). Pushes and tags have no repository workflow build,
artifact upload or release pipeline defined here. Actions were also disabled
for `2bitegr/rd-cl` through repository settings, with a fresh API verification
`enabled=false` on 2026-10-10. Historical runs/artifacts are retained. Workflow
file deletions await the approved commit checkpoint; no push was performed.

The former 1.4.10 Office acceptance artifacts are historical; they are not a
build of this workflow-v2 source. Current source is 1.4.11+69. A local Windows
client build and physical acceptance must be carried out separately before
shipping a package. No installer, production release or deployment is created
by this source change. Verify the test Office destination before any login or
support acceptance; local unit checks do not prove real support connectivity.

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
