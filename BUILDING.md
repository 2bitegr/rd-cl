# Building Exantas Support

This file documents the public build inputs needed to reproduce and modify the
Exantas Support client. Private signing and release automation are intentionally
not included.

## Repository

Public source repository:

```text
https://github.com/2bitegr/rd-cl
```

Fetch submodules after cloning:

```bash
git submodule update --init --recursive
scripts/apply-exantas-submodule-patches.sh
```

`libs/hbb_common` is an upstream RustDesk submodule. Exantas-specific public
submodule changes are kept as patches under `patches/` so the complete
Corresponding Source is available without relying on a private submodule fork.

## Public Build Defaults

The default Exantas self-hosted RustDesk routing values are public and are safe
to keep in source:

- ID server: `desk.exantas.eu:21116`
- Relay server: `desk.exantas.eu:21117`
- API server: `https://desk-api.exantas.eu`
- Server public verification key: see `config/exantas.example.toml`

The server private key, Office credentials, signing certificate, update signing
keys, and per-device unattended credentials are not public build inputs.

## Windows MSI

The Windows MSI packaging lives in `res/msi`.

The checked-in WiX templates should not contain workstation-specific absolute
paths. Generate package variables from the actual build output directory during
the Windows build.

On Windows, run the release build from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-release-build.ps1
```

The script uses persistent Windows tool locations by default:

- `C:\Tools` for Flutter and RustDesk engine artifacts
- `C:\vcpkg` for vcpkg
- `C:\Build\rd-cl` for clean build directories and release artifacts

It clones the public repository, applies public Exantas submodule patches,
generates Flutter Rust Bridge bindings, builds the Flutter Windows release,
then produces both portable EXE and MSI outputs under the printed
`ARTIFACT_DIR`.

Expected production output:

- `Exantas Support.exe`
- `Exantas Support.msi`

Unsigned development builds are allowed until a code-signing certificate is
available. Release notes must state that unsigned builds can trigger SmartScreen.

## Portable Windows Build

The portable package must contain the same Exantas source, branding, public
server defaults, source-code link, and no shared unattended credential.

Portable mode supports basic attended support without Office enrollment.
Managed unattended support still requires Office enrollment.

Basic attended support uses the public Exantas RustDesk server defaults plus ID
and numeric one-time password. Office login is only for Exantas support users;
final-customer device enrollment still requires an Office install link or code.

## Companion

Companion functionality is native inside the Exantas Support client. Office
login resolves the user's `admin` or `technician` role and permissions. The
PowerShell companion under `Companion/` is retained only as transition/reference
source.

## Validation Before Public Release

Run:

```bash
scripts/check-public-release.sh
scripts/apply-exantas-submodule-patches.sh
```

Then run the relevant Rust, Flutter, and Windows packaging checks for the files
changed in the release.

## Local support report acceptance

After upgrading to the local report queue, sign in to Office again in the
Companion so the existing pairing response supplies the stable `office_user_id`.
Remote session start/close events are handled by the main window. Closing the
last view opens the report without waiting for Office; moving a view does not
end the session. The main window must remain running for background retries.

Reports are written individually under the application support directory in
`office-reports`, using Windows DPAPI and flushed temporary-file replacement.
The queue is scoped to Office API origin and Office user ID. Sign-out retains
the files; signing back in as the same Office user resumes them. Do not remove
these files or switch Windows users while testing recovery.

Matching requires the exact RustDesk session ID (a string, never a floating
point number), source peer, destination peer and Office technician. Ambiguous
matches remain local. The existing pending endpoint returns up to 50 mapped
sessions; unmapped, already processed elsewhere or older sessions outside that
window require investigation in Office. No approximate time/peer matching is
performed. A saved remote ID and fixed idempotency key permit retries after an
acknowledgement is lost. A synced report does not imply email delivery.

Acceptance: close a test session and check the immediate dialog; save a
follow-up report with Office unreachable; restart and inspect Settings >
Support sessions; restore connectivity and verify a single work item. Repeat
with account switching, a moved/multiple-display window, and final-report
confirmation. Automated command/identity/concurrent-update tests run in the
Windows acceptance workflow. No Office schema/API deployment is required.
