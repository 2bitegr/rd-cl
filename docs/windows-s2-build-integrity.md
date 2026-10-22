# S2 native build integrity after the 2026-10-22 audit

This tooling closes the four findings in the build audit. The subsequent
user-authorized installer fix/version change targets rd-cl 2.0.0+72; see
[Windows installer correction](windows-installer-2.0.0.md). Authentication and
dependency versions are unchanged.
The Windows CMake change selects the reviewed SDK, not product functionality.
Use these instructions only with their exact reviewed **published** commit;
local edits are not a source handoff. Native S2 validation is still required.

## Source and payload

The owned hbb_common snapshot must equal its pinned Git tree, either before or
with exactly the reviewed public patch. A temporary Git index constructs the
expected patched tree; tracked/staged extra changes, missing files, modified
patch additions and non-ignored untracked inputs fail before native tools. CRLF
normalization is accepted. The actual index/worktree is never reset or cleaned.
Original dirty checkouts remain untouched; prepare a separate clean owned
snapshot if necessary. The patched state is checked again after patching and
before Rust compilation.

The native compile receipt and runtime directory must have exactly the same
normalized path→SHA256 inventory. Extra/missing/changed files are rejected before
ZIP creation. ZIP contents are hashed against that inventory, and source payload
is rechecked before PASS metadata. EXE packaging also rechecks runtime inventory
after packer compilation. Link/reparse runtime entries are rejected.

## Compiler, SDK and triplet

`windows-native-profile.json` explicitly selects Windows SDK `10.0.22621.0`.
VsDevCmd receives `-winsdk=10.0.22621.0`; returned SDK variables and required
headers/libraries are checked. The SDK fingerprint includes the version and
Windows.h, sdkddkver.h, corecrt.h, kernel32.lib, ucrt.lib and libucrt.lib hashes. This is a
fingerprint of selected SDK inputs, not a full SDK distribution manifest.

Receipts now record `sdk_identity`. Reuse checks cl.exe, link.exe, lib.exe,
vcpkg.exe and codec CMake hashes, SDK identity, SDK-pinned triplet and the
existing manifest/overlay/installed codec/ABI hashes. Bootstrap checks SDK inputs
before/after compilation and withholds a receipt if they change. App compilation
rechecks codec/tool/SDK evidence after Flutter as well.

The release-only CRLF triplet adds:

```cmake
set(VCPKG_CMAKE_SYSTEM_VERSION 10.0.22621.0)
```

New triplet SHA256:
`6e5446ee9aa0ab97e61170013be186b2c03ea7bc9f63cb56fdff478f61448275`.
Legacy `323c6f88ab1a51ff02dacabd5d7f00e290fc5510acab1841d61ea3a8788e1a92`
and original `e3cd9820386c639b8cbf844d43853cbc838f75a1488bfd4add98d5646c716538`
are accepted as **preserved inputs**, not as the new compile/reuse triplet.

The builder exports RDCL_WINDOWS_SDK_VERSION for Flutter's CMake SDK selection
before project(). After Flutter, the generated runner/rustdesk.vcxproj must name
exactly the selected WindowsTargetPlatformVersion before compile provenance is
published. Actual compiler/SDK selection must also be reviewed in the S2 logs.

## Legacy receipt migration — no retroactive certification

The genuine receipt from def169 and the completed ad46 application build remain
valid historical evidence. Its SHA256 is
`3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97`.
That receipt has no SDK identity and used the earlier triplet. **Current tooling
rejects reuse**; it must not be edited, copied into a new schema or augmented with
current SDK hashes as if those proved historical compilation.

Preserve the old receipt, toolchain JSON, codec root/caches and completed EXE.
Prepare pinned inputs (required verified downloads are permitted), then run the
updated codec bootstrap Preflight and Compile using a **new unused** owned codec
root and output directory, matching the new published source/snapshot. Existing
original or legacy triplet input is inspected but never modified. Real fresh
compilation must produce the new receipt/SDK/tool/ABI evidence and derived
`toolchain-codecs-local.json`. Verify its actual new SHA256, record it separately,
and use that derived JSON for the app build. If the new compiler/SDK or local
inputs are unavailable/unverifiable, report BLOCKED; never fall back to the old
receipt. A later application-only change may reuse the **new matching** receipt.

## One locked release session

The public entrypoint remains:

```powershell
& (Join-Path $snapshot 'scripts\windows-native-release.ps1') `
  -Mode Build -WithExe -Toolchain $toolchain `
  -SourceCommit $sourceCommit -OutputRoot $delivery
```

The wrapper now forwards Build and installer selection to one Python process.
One invocation retains resource locks from before SUBST/generated/native mutation
through application build, ZIP and EXE/MSI packaging and alias cleanup. Direct
Build/Package/PackageExe/MSI/bootstrap invocations also acquire native resource
locks. Scope includes physical snapshot, output, effective Cargo target, Flutter
SDK, vcpkg root, optional codec root and drive alias, under the Windows user's
LOCALAPPDATA/ExantasBuildLocks/rd-cl. This coordinates this user's native jobs;
it is not a cross-user service or a machine-wide access-control mechanism.

A contender fails immediately without changing another owner's files. Locks
record PID/resource/random ownership token; partial acquisition releases only
this invocation's locks. Failed compile/packaging cannot report PASS, and owned
locks are released after normal failure cleanup. Changed ownership or a crashed
owner's stale lock is preserved for investigation. Do not delete a lock, reset
an alias or force a retry just because the file is old or the build is blocked;
verify owner/process and current consumers through the established source
workstation review. Do not launch Build and PackageExe independently in parallel.

## Verification

Guard suite includes real local Git trees/indices and real competing Python
processes, exact/CRLF patched source, extra tracked/staged/untracked edits,
extra/missing/mutated ZIP payload, recorded executable/SDK changes, untouched
legacy receipts and locks spanning both build and packaging/failure paths.
Run from the snapshot with its existing Python and canonical process TEMP/TMP:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
& $python -m unittest discover -s scripts/tests -p 'test_windows*.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Native guard suite failed' }
```

Use the existing S2 CMake for RDCL_TEST_CMAKE. Coordinator guard/CMake/PowerShell
checks cannot establish native Windows compilation, filesystem/SDK integration,
installation, upgrade or real session acceptance. Complete the S2 sequence and
artifact plan/apply/verify before delivering any new EXE. Preserve the last
verified delivery throughout; use unused output paths and actual package hashes.


## New-computer installation observation — 2026-10-22

The user supplied a screenshot showing `rd-cl v1.4.11`, an older-installation
warning and a stopped service. This is runtime evidence requiring investigation;
it does not establish which installer was used or that installation completed.
Do not relabel the historical packaging PASS as installation acceptance PASS.

The sidebar calls `mainGetVersion()`; `src/ui_interface.rs::get_version()` returns
`crate::VERSION`. Pinned hbb_common generates that constant from Cargo.toml;
current published Cargo.toml says 1.4.13. Thus 1.4.11 identifies the native core
loaded by that process, not the installer filename or Flutter build number.
The older-installation warning compares the running core BUILD_DATE against the
registry BuildDate (`is_installed_lower_version`), rather than comparing semantic
versions. A missing/stale registry date may also explain that warning. The
stopped-service indication alone cannot distinguish portable execution, incomplete
installation or a service failure.

For a separately authorized installation diagnostic, collect without modifying
services/registry or reinstalling:

1. Exact installer path, size and SHA256. The historical ad46 S2 installer was
   23,875,584 bytes with SHA256
   `0586a21a7c3df107475722b07bcb6536be80fbcff19f9659672a7ddae6a8b66b`.
   Compare this to the installer, never to the installed application executable.
2. Whether the screenshot preceded or followed completed installation; running
   process executable path and actually loaded librustdesk.dll path/hash. Record
   access-denied diagnostics if module enumeration is restricted; do not guess.
3. Compare the loaded DLL SHA256 to the corresponding original delivery
   EXE-INFO.json payload_sha256 / BUILD-INFO.json files entry. A matching installer
   hash alone cannot prove that its payload is the running process.
4. Service name/status/binary path and installed BuildDate/version metadata.
   Keep logs private; no service starts, reinstall, registry edits or production
   connections as a diagnostic shortcut. Investigate mismatches at the stage
   where evidence diverges: transferred installer, embedded payload, installed
   files or running process. A stale packaged DLL is a hypothesis until compared.

The completed installer remains historical packaging evidence; new-PC identity,
installation and service acceptance are unresolved pending these observations.
