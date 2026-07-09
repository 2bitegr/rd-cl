# Exantas RustDesk Technician Companion

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
