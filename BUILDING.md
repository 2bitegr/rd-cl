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

## Windows cloud build (portable EXE and MSI)

The Windows MSI packaging lives in `res/msi`.

The checked-in WiX templates should not contain workstation-specific absolute
paths. Generate package variables from the actual build output directory during
the Windows build.

Run **Windows cloud build** manually from GitHub Actions on the desired source
ref after the workflow is present on the default branch. It uses a native
`windows-2022` x64 cloud runner; the Linux Codex environment coordinates the job.
No S2 machine, signing secret, production credentials or Dokploy deployment is
required. The workflow has no push, schedule or deployment trigger.

For the same build on an existing Windows runner, use PowerShell 7.4 or later:

```powershell
pwsh -NoProfile -File .\scripts\windows-cloud-build.ps1 -SourceDir . -BuildBase "$env:RUNNER_TEMP\rd-cl-build"
```

The build uses the selected checkout without cloning a moving branch. It discovers
Visual Studio C++ tools with `vswhere`, derives the app version from matching
Cargo/Flutter manifests, and preserves dependency lockfiles. Pins for Flutter,
Rust, the RustDesk custom engine, bridge generator and vcpkg live in
`scripts/windows-cloud-build.json`; the engine SHA-256 is pinned to the upstream
archive retrieved over verified HTTPS. The packer's Windows CPython 3.11 Brotli
wheel is pinned by version and SHA-256 in `scripts/windows-cloud-requirements.txt`.
Missing build prerequisites may be downloaded for this authorized cloud workflow.
Use existing runner C++/Windows SDK, LLVM, CMake, NuGet, Git, Python and Rustup.

SDKs, Pub/Cargo/NuGet and vcpkg/native build state are cached between runs.
The workflow limits native build parallelism to two jobs. Build logs and artifacts
use runner-local temporary directories; the coordinator retains downloaded
evidence outside source checkouts. No workstation-specific `C:\Tools`, `C:\vcpkg`
or Desktop path is required. `windows-release-build.ps1` delegates to this same
implementation for compatibility; its old clone/version override parameters
have been removed to prevent building or labeling a different source revision.

The script applies the public Exantas submodule/Flutter SDK patches, generates
bindings, builds the Flutter/Rust client, and packages both outputs under the
printed `ARTIFACT_DIR`. A failing native command aborts the run; patch failures
are not ignored. Checks cover EXE x64 PE headers, MSI architecture/ProductVersion,
unchanged dependency lockfiles and output SHA-256. Runtime acceptance on the new
computer remains a separate check.

The run's `ExantasSupport-windows-x64-<commit>` artifact contains:

- `ExantasSupport-<version>-x86_64-portable.exe`
- `ExantasInstaller-<version>-x86_64.msi`
- `SHA256SUMS` and `BUILD-INFO.json` with exact source, toolchain and checksums

Artifacts are retained for seven days; failure logs are retained separately.
These are build outputs, not a deployment or GitHub Release. Before final release
handoff, the coordinator verifies downloaded bytes and the shared artifact
maintenance plan/apply/verify gate. The workflow must complete successfully before
an EXE/MSI is described as built or tested.

The input and failure-handling guards can be tested on Linux or Windows without
downloading native prerequisites:

```powershell
pwsh -NoProfile -File ./scripts/tests/windows-cloud-build.tests.ps1
pwsh -NoProfile -File ./scripts/windows-cloud-build.ps1 -ValidateOnly
```

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
acknowledgement is lost. The current API returns `already_processed` for both
same-key and conflicting submissions, so that response requires Office review;
it must not be displayed as confirmation of this local note. The note remains
available through View in the local history. A synced report does not imply
email delivery.

Acceptance: close a test session and check the immediate dialog; save a
follow-up report with Office unreachable; restart and inspect Settings >
Support sessions; restore connectivity and verify a single work item. Repeat
with account switching, a moved/multiple-display window, and final-report
confirmation. Automated command/identity/concurrent-update tests run in the
Windows acceptance workflow. No Office schema/API deployment is required.
