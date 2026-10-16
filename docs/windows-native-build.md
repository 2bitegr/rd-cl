# Pinned native Windows x64 build

Use `scripts/windows-native-build.ps1` and its reviewed
`windows-native-profile.json`. The legacy `windows-release-build.ps1` is not the
accepted repeatable workflow: it uses moving refs, an unlocked pub resolve,
fixed tool paths and a suppressed SDK patch failure.

The source checkpoint is `5eec99577ca4faa36bfae127022af62e85377aff`, product
`1.4.12+70`. The reviewed profile includes the approved runtime-version and
staff-only sign-in UI changes, product version metadata, and the separately
approved, uncommitted Flutter lock correction. A build must disclose this delta; the commit alone
is not the full build input.

## Offline dependency policy

The native wrapper uses **existing local tools and caches only** in every mode.
There is no automatic download/online fallback. Reuse the reviewed toolchain JSON,
owned NTFS source snapshot, Cargo target, Pub cache, installed vcpkg codecs and
NuGet cache. Do not create a fresh clone/cache or clean existing caches for a
repeat build. Missing prerequisites stop the invocation; report the exact missing
item before seeking separate authorization for any acquisition.

- Cargo metadata/builds use `--frozen`; child Cargo processes inherit
  `CARGO_NET_OFFLINE=true`. Existing pinned Rust binaries bypass rustup auto-install.
- Flutter uses the existing Dart/tool snapshot directly after cache/stamp checks,
  bypassing bootstrap SDK downloads and tool `pub upgrade`. Its locked package
  resolve uses `--offline --enforce-lockfile`; tests/build use `--no-pub`.
- FRB skips its convenience dependency check/automatic build_runner launch. The
  reviewed manifests/locks and tool versions remain checked; build_runner runs
  directly from its cached Dart entrypoint and existing package configuration,
  preserving FRB1.80.1's `--enable-experiment=class-modifiers` argument to avoid
  unnecessary asset-graph invalidation.
- vcpkg verifies local pinned history/override objects instead of fetching them.
  An install `--dry-run --no-downloads --only-binarycaching` must report only
  already installed codecs; no install/remove/rebuild action is executed. Asset
  origins and external binary sources are disabled. An ABI/cache miss or unknown
  plan stops the run before installed libraries can change. The retained successful
  cache receipt must also match the current compiler/linker/CMake,27 codec ABI/library
  hashes and reviewed overlay sources; an application-only change does not invalidate
  this independent codec proof.
- Git permits only local file transport and disables lazy fetch. Process-only
  loopback HTTP proxies and local Flutter/Rustup origins defend helper processes.
  This is an inspected tool policy, not an operating-system network sandbox.
- MSI restore and SDK resolution use only the existing local NuGet packages feed;
  a missing WiX/extension package fails. NuGet auditing is disabled for this offline
  restore. No user/global NuGet, proxy, SDK, firewall or security settings change.

`Logs/<run>/offline-policy.json` records the effective cache roots/policy. Failed
steps produce `result.json` with `BLOCKED` and step-specific stdout/stderr. JSON receipts are replaced atomically so a failed disk write preserves the previous
receipt. Errors remain visible on stderr if the result JSON cannot be written;
constructor failures release only the drive mapping they created. Compiler outputs and delivery packages still consume space; offline mode is not zero-write
mode and does not authorize cleanup.

The standard-library guard regressions run with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p test_windows_native_offline.py -v
```

## Machine-local prerequisites

Keep the current application checkout intact. Reuse the existing owned native
Windows snapshot, with the exact recorded `hbb_common` commit and the
approved lock bytes. Source hashes, the submodule public Exantas patch and SDK
patch are checked explicitly. Generated bindings remain in this build copy.

Resolve the actual local Desktop with the Windows Known Folder API, then use
`Office-Workspace-Artifacts/Tools`, `Scratch`, `Reports`, `Builds/rd-cl`. Keep the
machine-local toolchain JSON outside Git. Its schema contains:

- `artifact_root`: verified physical local Desktop artifact root.
- `source`: absolute native source-copy path under its Scratch folder, with an
  owned `.rd-cl-native-snapshot.json` marker recording source repository/commit.
  Main checkouts and unrelated output directories are rejected.
- `paths`: explicit `git`, `flutter` (SDK root), `cargo`, `rustc`, `python`
  (venv executable), `codegen`, `vcpkg` (root), `vswhere`, `engine_archive`; optional `vcpkg_cmake` pins
  the codec helper CMake independently of Flutter/VS CMake.
- `environment`: isolated `RUSTUP_HOME`, `CARGO_HOME`, `RUSTUP_TOOLCHAIN`,
  optional `CARGO_TARGET_DIR`, `PUB_CACHE`, `VCPKG_ROOT`, `VCPKG_DEFAULT_HOST_TRIPLET`, `LIBCLANG_PATH`,
  `LLVM_PATH`, concurrency limits and `VCPKG_BINARY_SOURCES=clear`.
- Optional `drive_alias`: an unused `D:` through `Z:` drive and its physical
  artifact-root `target`. A transient `subst` alias avoids Cargo/libgit2
  `MAX_PATH` failures in the locked WezTerm/Harfbuzz dependency. No files move,
  and no Windows registry/security settings change. An occupied drive is never
  replaced. A mapping created by the invocation is removed on exit.

The following reviewed tools must already exist in versioned folders. This
wrapper does not install or download them:

| Tool | Reviewed profile |
| --- | --- |
| Visual Studio | Build Tools 2022; `Microsoft.VisualStudio.Workload.VCTools`, `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, `Microsoft.VisualStudio.Component.VC.CMake.Project`, `Microsoft.VisualStudio.Component.Windows11SDK.22621` |
| Flutter | Windows 3.24.5, SDK revision `dec2ee5c1f98f8e84a7d5380c05eb8a3d0a81668`, Dart 3.5.4 |
| Rust | Isolated 1.75.0, minimal MSVC host/target, plus rustfmt; declared MSRV is a minimum and full compilation remains the authority |
| Python | Isolated 3.11.9 full installer, build venv; no global pip or PATH change |
| Git | Portable Git for Windows, record actual version/download digest |
| Bridge | Official Windows x64 FRB codegen 1.80.1; Cargo/Dart runtime 1.80.1 |
| LLVM | Versioned libclang 15.0.7 with built-in headers and license, explicit `--llvm-path` |
| vcpkg | Baseline `120deac3062162151622ca4860575a33844ba10b`; retained manifests and overlays |

Verify vendor checksums where published, Authenticode for the VS/Python
installers, download/asset IDs, actual versions, license locations and installer
exit/reboot status. Save these in the machine-local report. Do not overwrite
existing tools, change default toolchains, silently reboot or suppress UAC.

A shallow vcpkg checkout is insufficient for the older pinned overrides.
Provision checks the existing history and reviewed override trees locally,
with lazy fetch disabled. Missing history/blobs stop the run; the wrapper never
unshallows or hydrates them from a remote source.

## Engine and SDK patches

Pin the engine asset by immutable GitHub asset ID `210168939`, SHA-256
`ec8cabf36ee4ff24c8d98de25b00e70781eb03876265aee84d0fe554a110036e`.
Do not use the moving `releases/download/main` URL.

The immutable engine tag workflow at
`bc374ca81eae3f77329ebf7bc98efadfde10018e` uses 3.24.4, while the newer repository
head workflow uses 3.24.5. Preserve this distinction in provenance. SDK 3.24.4
and 3.24.5 share Dart revision
`88c9758ef131d430d8ce595c6bfb4c90574d3ddd`; the actual custom `gen_snapshot`
reports Dart 3.5.4. The developmentPC synthetic native AOT probe passed against
SDK 3.24.5. This proves snapshot compatibility for the probe, not product GUI
or remote-session acceptance. The full native application Flutter AOT stage also
passed on developmentPC. The real Rust1.75/MSVC release DLL, virtual-display
component, Flutter/C++ x64 executable, portable ZIP and WiX4.0.5 MSI then passed.
A second full Build -WithMsi invocation also passed; 90 of91 runtime files were
byte-identical; the executable differs only in two PE timestamp fields. These build checks do not establish GUI/provider acceptance.

Apply the tracked dropdown filter patch to this isolated Windows SDK with
forward-check/apply or reverse-check; fail otherwise. Apply the tracked public
Exantas submodule patch with the same fail-closed/idempotent policy. Never hide
an error with `|| true` or alter production endpoints/configuration anew.

## Modes and invocation

In native Windows PowerShell, use explicit paths:

```powershell
& '<native-source>\scripts\windows-native-build.ps1' `
    -Mode Preflight `
    -Toolchain '<Desktop-artifacts>\Reports\<run>\toolchain-local.json' `
    -SourceCommit 5eec99577ca4faa36bfae127022af62e85377aff `
    -OutputRoot '<Desktop-artifacts>\Builds\rd-cl\<new-run>'
```

- **Preflight** checks actual source/submodule/input hashes, manifest versions,
  VS/SDK discovery, MSVC, CMake, Flutter revision, Rust host/version, FRB version
  and vcpkg baseline, plus existing tool/cache files and SDK stamps. It records
  source dirty state rather than claiming a clean
  commit build. It neither launches the product nor installs tools globally.
- **Provision** prepares the already installed pinned tools for this snapshot:
  local vcpkg version-history objects, existing Windows engine artifacts, the
  locally archived custom release engine, SDK/submodule patches and
  `pub get --offline --enforce-lockfile`. No fetch/precache step runs. Native plugin symlinks
  require Developer Mode or the legitimate Windows symlink privilege. The
  optional `-ElevateProvision` flag requests real UAC for this prerequisite mode;
  it does not enable Developer Mode or elevate the product/Build mode.
- **Build** runs Provision, generates FRB bindings, existing native Dart
  regressions, frozen Windows Cargo metadata, existing release-only static vcpkg
  codecs (a no-action `--dry-run --no-downloads --only-binarycaching` plan),
  `cargo build --frozen --release -p dylib_virtual_display -j 1`, then
  `cargo build --frozen --features flutter,hwcodec,vram --lib --release -j 1`,
  then `flutter build windows --release --no-pub`. Native Dart regressions use
  `--concurrency=1` to limit memory pressure. Every exit is checked.
- **Package** accepts only a previously completed native compile receipt with
  matching source/lock/payload hashes. It requires the exact `rustdesk.exe`,
  x64 PE architecture, Rust/engine/virtual-display DLLs and Flutter runtime data.
  It produces a portable ZIP, verifies its CRCs and writes `BUILD-INFO.json`
  and `SHA256SUMS`. It refuses to overwrite an existing package.

For initial plugin symlinks, run **Provision with `-ElevateProvision`** if the
normal locked resolve specifically reports missing symlink support. Flutter3.24
also prepares Linux plugin links when that desktop platform is enabled. The
reviewed Provision explicitly prepares both Windows and Linux plugin links
inside the owned snapshot/cache (17 +15 on developmentPC), without changing
global platform/security settings. After this
prerequisite passes, run **Build without elevation**. Reuse the same isolated
source/dependency caches, but choose a new output directory for each delivery.
Never elevate Build as a substitute for fixing an unrelated error. Use the
same wrapper/toolchain JSON and drive alias for Provision and Build: resolving
directly through C: and then building through R: changes generated plugin paths
and can require symlink creation again. The developmentPC wrapper Provision
with real UAC passed for the reviewed R: profile; Developer Mode remains unchanged.

The wrapper supplies process-only executable search paths, Windows `PATHEXT`
and `RUST_LOG=info` (the old FRB binary accepts only info/debug). It imports
`VsDevCmd` in memory without logging a full environment. A release-only
`x64-windows-static` overlay triplet preserves x64/static CRT/static libraries
while avoiding unneeded debug intermediates; one job limits resource pressure.

On developmentPC, the large Cargo target cache is below the separately approved
compressed Cargo folder; the wrapper copies only the exact required runtime
DLLs into the isolated source target path for existing CMake packaging. Other
source/runtime inputs are preserved. Identical custom engine payloads are not
rewritten; regenerated bindings retain their previous timestamps only when their
bytes match exactly. This avoids unnecessary Rust/LTO work on repeat builds.

Build checks a 1.5 GiB minimum floor before launching any tools, then validates
the exact cold/warm reserve during preflight and rechecks before native compile.
A cold guarded build needs at least 5 GiB free before generators/tests start. The local `compiled_cache_receipt` is required for installed-codec reuse; it also
controls the warm resource reserve. A 1.5 GiB warm reserve applies only when a completed native Cargo/virtual
component cache has matching source/generated-binding, DLL, codec ABI/library,
compiler and engine checksums. Every compile/test/package check still runs; the
receipt changes only the resource reserve, never artifact acceptance.
On developmentPC the first codec build has already completed and the Cargo
target directory inherits the explicitly approved NTFS compression. The guard
is a minimum reserve, not a guarantee of peak-space availability.
Do not delete unrelated data to bypass it. Storage compression or cleanup must
have a separate explicit scope/approval and preserve build inputs.

## Acceptance and current limits

A passing installer, locked resolve, metadata/preflight or AOT probe is not a
passing rd-cl binary build. Record actual stage statuses and command/exit/log
locations. Existing Windows Companion tests use synthetic data and real DPAPI;
Dart tests run without Office login or a RustDesk session. Full runtime, physical
provider, GUI acceptance and signing remain separate gates.

Do not change Cargo/pubspec dependencies or functional source to bypass a
compiler failure. Prepare an exact isolated candidate diff and obtain its
specific approval first. No commits, push, release publication, product
installation/startup, production connection or deployment are part of this
workflow.

Build reports and the concrete developmentPC repeat command live under its
Desktop report folder. Machine-specific paths/caches/logs never belong in Git.

## ZIP and MSI orchestration

`scripts/windows-native-release.ps1` wraps the same core modes and adds
`-WithMsi` after a successful Build, or `-Mode PackageMsi` for an existing
verified OutputRoot. It never elevates installer compilation. Use the same
Toolchain, SourceCommit and OutputRoot parameters.

The MSI adapter requires the native compile receipt, unchanged runtime hashes
and the already verified portable ZIP. Product identity comes from the source
Runner resource; version/build date come from manifests and generated Rust
version metadata. The small optional `res/msi/preprocess.py --build-date` flag
avoids product execution when provided alongside `--version`. The accepted
adapter always supplies both; existing callers retain the legacy defaults. A
native synthetic regression confirms that supplied metadata performs zero
product process calls and rejects an explicitly empty date.

The existing WiX4.0.5 SDK/extensions and DUtil/WcaUtil references are restored
with full .NET Framework MSBuild, `-t:Restore -p:RestorePackagesConfig=true`,
using the existing task-owned NuGet cache/config with only its local packages
feed. There is no public source or online fallback.
No package reference, application dependency or global NuGet configuration
changes. Installer source templates are taken from the pinned Git commit; only
recognized task-generated template changes can be reset in the owned native
snapshot. Git archive explicitly uses core.eol=lf so Windows export cannot
change the verified source-template bytes. Main checkout installer sources remain untouched except the small
reviewed metadata argument.

MSI verification opens the database read-only to inspect product/version and
its x64 summary template. It never invokes msiexec, installs the product or
executes a custom action. A synthetic native database probe validates this
reader separately from actual MSI acceptance. MSI-INFO.json and SHA256SUMS
record the real installer only after its build and static checks pass.

The initial WSL codec prebuild used LF triplet bytes; the native Windows wrapper
writes CRLF. Vcpkg hashes exact bytes, so that one-time difference invalidated
the initial cache. The canonical native triplet SHA256 is
`323c6f88ab1a51ff02dacabd5d7f00e290fc5510acab1841d61ea3a8788e1a92`.
Keep the same native representation on repeat invocations. A version-only
`vcpkg install --dry-run` does not establish ABI reuse; verify the real install
output and installed ABI manifests. Do not edit ABI records to bypass rebuilds.

The Windows wrappers wait for the exact child process, cache its process handle
before waiting, and reject an unavailable exit code. They do not wait for
unrelated descendant compiler daemons. Native synthetic exit0/exit7 checks
confirmed that failures propagate. Build logs retain existing compiler warnings;
no functional source corrections or warning suppression were introduced.
