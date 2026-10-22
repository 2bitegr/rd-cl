> Historical continuation and investigation at ad46. Current source/payload,
> tool/SDK and release-lock requirements are in
> [S2 build integrity](windows-s2-build-integrity.md). The old genuine receipt is
> preserved historical evidence and is no longer reusable by hardened tooling:
> run a new isolated bootstrap with SDK identity/new triplet. Do not execute the
> historical reuse-only instructions below against the updated builder.

# S2 application continuation with a shallow vcpkg checkout

Scope: rd-cl 1.4.13+71, source/tooling branch
`codex/s2-codec-bootstrap-1.4.13`, following the genuine S2 codec compilation
at `def169111cfdb42591497955c60db4c35457522d`. No application, authentication,
dependency or production changes. No coordinator application build.

## Completion update

The user reports full native S2 application/EXE packaging PASS on 2026-10-21 at
`ad46faef58b5773fc662f021c00ed2f92a9c675a`, with 53 guard tests, 50 Dart tests,
object/ABI/installed-only checks, Rust/Flutter, 91 embedded runtime files and the
release-maintenance gate PASS. Genuine codec receipt remained unchanged.
The completed EXE baseline/path/hash and maintained next-build prompt are in
[the S2 handoff guide](windows-s2-build-handoff.md). Earlier BLOCKED/NOT_RUN
application results below describe the resolved investigation, not current
packaging status. Installation, upgrade and real runtime acceptance remain NOT_RUN;
this coordinator has not independently accessed the Windows artifact bytes.

## Why ancestry is unnecessary for this path

Inspected vcpkg-tool [2025-07-21 registries.cpp](https://github.com/microsoft/vcpkg-tool/blob/2025-07-21/src/vcpkg/registries.cpp):
`git_checkout_baseline` reads `<baseline>:versions/baseline.json`;
`BuiltinGitRegistry::get_port_entry` reads the working versions database;
`BuiltinGitRegistryEntry::try_load_port` selects its `git-tree` by version.
[VcpkgPaths::git_checkout_port / git_read_tree](https://github.com/microsoft/vcpkg-tool/blob/2025-07-21/src/vcpkg/vcpkgpaths.cpp)
extract that tree. These operations require commit/path/tree/blob objects, not
parent commits or the commits that originally introduced override trees.
A shallow repository can contain all of those objects; shallow=false alone also
cannot prove they exist. This conclusion applies to the pinned builtin registry
and the reviewed Windows x64 installed-only dependency closure, not arbitrary
registries, platforms or future manifests. An unfamiliar plan remains BLOCKED.

`windows-native-build.py` now checks, before engine extraction or pub/generators:

- The existing codec verifier, unchanged: manifest, actual compiler/linker/CMake,
  installed codec/ABI file hashes and overlay hashes must still match the receipt.
- Exact pinned vcpkg HEAD/baseline commit and baseline JSON.
- Unmodified tracked versions/ports/scripts/triplets versus that HEAD.
- The 16 reviewed versions from the **invoked source commit's**
  `scripts/windows-codec-bootstrap-inputs.json`. Six receipt-verified local overlays
  bypass registry recipe selection and must match their reviewed versions. The
  other ten ports use the builtin registry: eight baseline versions must match
  the pinned baseline, and two overrides use their older pinned versions. Each
  selected registry versions entry must resolve uniquely.
- Both override trees must equal the profile's immutable tree IDs; every selected
  tree, descendant subtree and blob must be present locally with the correct type.
- Before Rust native compilation, the codec verifier runs again and the vcpkg
  dry-run must contain exactly those 16 installed packages, versions and static
  host/target triplet. New/rebuilt/removed/missing/unknown dependencies fail closed.

The process retains GIT_NO_LAZY_FETCH=1, file-only Git protocols, blocked asset
origins, cleared binary sources and offline Cargo/Pub. It also disables Git replace
objects and reapplies process-only offline policy after importing VsDevCmd.
There is no unshallow, fetch, receipt synthesis, codec rebuild or cache deletion.
`vcpkg-objects.json` records the selected tree IDs only after a successful audit.
An absent object fails with the corresponding named step/error log. Stop and
return its exact object/path; do not fetch, modify .git/shallow or bypass the check.

## Keep the verified root after VsDevCmd

S2 reported at `1590e8381b3af15dc6a47e4e680adedb78292dcc`: guard tests
51 PASS/1 Linux-only SKIP, Preflight/object audit/ABI/exact installed-only plan
PASS, 50 Dart regressions PASS and virtual-display build PASS. Main Rust DLL
compilation failed with exit 101 because hwcodec searched Visual Studio's bundled
vcpkg for `libavutil/pixfmt.h`; the header exists in the verified codec root.
Flutter and EXE packaging were NOT RUN. S2 reports the genuine receipt and all
424 installed codec/ABI files unchanged. This is reported S2 evidence, not an
independently accessed Windows build on the coordinator.

The tool previously imported every VsDevCmd variable over the configured
process environment. Its receipt verifier and vcpkg CLI used `paths.vcpkg`, while
pinned hwcodec [`778df1f99597722473b29443bac22ae6c23946fe` build.rs](https://github.com/rustdesk-org/hwcodec/blob/778df1f99597722473b29443bac22ae6c23946fe/build.rs)
reads `VCPKG_ROOT` directly. Therefore the checks could pass while the Rust child
used a different root. After successful VsDevCmd import, the tool now removes
case aliases of that variable and sets exactly one `VCPKG_ROOT` from
`self.tools['vcpkg']`, the configured root after the existing drive-alias mapping.
VS compiler/SDK PATH, INCLUDE and LIB are retained. No global environment changes
or dependency edits are made. `native-vcpkg-root.json` records only the selected
root/source, not an environment dump or a claim that codec verification passed.
The existing receipt, object audit, offline policy and installed-only guards
still run before native compilation.

Retry the normal application workflow below using the newly published tooling
SHA and the same genuine codec root/receipt. Do not rerun codec bootstrap,
clear Cargo targets or edit hwcodec. Keep the failed run's resumable state and
compact diagnostics. Verify `native-vcpkg-root.json` names the configured codec
root and that native build logs no longer select Visual Studio's vcpkg. A further
failure remains BLOCKED and requires its actual diagnostics.

## Reviewed verification

Stdlib command, from the snapshot root, using its existing Python:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
& $python -m unittest discover -s scripts/tests -p 'test_windows*.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Guard tests failed' }
```

Coordinator Linux result: 53 PASS, 1 existing CMake integration SKIP (CMake is
absent; no download). The 11 new tests use real Git objects, including a shallow
boundary with its parent object removed, a selected override tree different from
HEAD's recipe, missing baseline commit/JSON/versions/tree/subtree/blob, a missing
promisor blob without lazy fetch, changed metadata, wrong versions/override IDs,
overlay precedence, exact installed-plan rejection and failure before provisioning
side effects. The eight non-override builtin versions were also compared with the
pinned baseline JSON; all match.
Two additional regressions exercise the real VsDevCmd import and child runner
with synthetic process output: a foreign/absent root and mixed-case inherited
roots cannot redirect Cargo; compiler/SDK settings remain, and failed VsDevCmd
stops without root-selection evidence. These are guard tests, not a native
Windows application build. On S2 use its
existing `RDCL_TEST_CMAKE` and canonical process-local TEMP/TMP; do not weaken
platform or dependency checks. The latest S2 completion is recorded above; these coordinator guard tests alone
do not establish native application success.

## S2 continuation

Use the full published tooling SHA supplied in the coordinator's handoff as
`$sourceCommit`, never the moving branch name. Read the published scripts and
AGENTS.md. Safely import only that published source into the owned snapshot;
verify HEAD, profile, input hashes, pinned hbb_common and public patch before
updating its ownership marker. Preserve dirty checkouts/submodules. No source
corrections, dependency downloads, Actions, installation or deployment on S2.

Discover the actual native Windows Desktop and verify existing metadata. The
reported artifact root is:

`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts`

Reuse these existing siblings beneath it:

- `Builds\rd-cl\1.4.13+71\codec-bootstrap-s2\toolchain-codecs-local.json`
- `Builds\rd-cl\1.4.13+71\codec-bootstrap-s2\compiled-cache-receipt.json`

Receipt SHA-256 must remain
`3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97`.
Do not edit the receipt, codec root/markers, installed files, original triplet,
caches, original JSON or previous verified package. The new application SHA does
not invalidate a matching codec-only receipt. Do not rerun codec bootstrap.

Set `$snapshot`, `$toolchain`, `$python`, `$delivery` from verified existing local
metadata. Preserve the established process-only drive alias and canonical TEMP/TMP.
Use the existing delivery directory below only after confirming it contains no
previous verified package that this build could replace; otherwise select an
owned unused sibling and report the resulting absolute EXE destination.

`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\1.4.13+71\delivery-s2`

Run the tests above, then:

```powershell
$receipt = Join-Path (Split-Path $toolchain) 'compiled-cache-receipt.json'
$expectedReceipt = '3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97'
if ((Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedReceipt) {
    throw 'Existing genuine S2 receipt differs; preserve it and report BLOCKED'
}
& (Join-Path $snapshot 'scripts\windows-native-build.ps1') `
  -Mode Preflight -Toolchain $toolchain -SourceCommit $sourceCommit -OutputRoot $delivery
& (Join-Path $snapshot 'scripts\windows-native-release.ps1') `
  -Mode Build -WithExe -Toolchain $toolchain -SourceCommit $sourceCommit -OutputRoot $delivery
```

Stop immediately on an exception/nonzero phase; do not proceed to packaging after
failure. Repeat the receipt SHA check after execution, including a blocked run.
The release wrapper propagates core build failure and performs EXE packaging only
after application success. Native compiler/CMake/ABI verification and an exact
installed-only vcpkg plan must pass; existing libraries are not proof alone.

On success verify runtime ZIP, BUILD-INFO.json, EXE-INFO.json, source/version/x64
PE and SHA256SUMS; complete Office release-maintenance plan/apply/verify with only
inspected authorized disposable candidates (zero candidates is valid). Preserve
source, reusable build state and previous verified delivery. Report actual
application and EXE results separately from codec success and update the existing
`delivery-s2\BUILD-STATUS.md` with exact evidence and retained paths.

Planned EXE, **not an existing verified artifact**:

`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\1.4.13+71\delivery-s2\rd-cl-1.4.13+71-windows-x64-install.exe`

Return the real absolute directory, EXE filename/path and SHA-256, source commit,
version, tests, object audit, receipt/ABI/installed-only results and artifact gate.
Missing local prerequisites produce one consolidated BLOCKED report with exact
logs; never claim a new EXE exists before byte/hash verification.

## Published Office native authentication contract

Verified by both local Git tree and live GitHub Contents API on 2026-10-21:

- Repository: `2bitegr/Office`, published main commit
  `bfac7d178dcb046922a7f32862cf6fdba0feaf35`.
- Case-sensitive path: `docs/OFFICE_RUSTDESK_NATIVE_AUTH.md`.
- [Immutable published contract](https://github.com/2bitegr/Office/blob/bfac7d178dcb046922a7f32862cf6fdba0feaf35/docs/OFFICE_RUSTDESK_NATIVE_AUTH.md).
- Git blob: `9048f479223b385dd1d544c6529cac307b5ce3e9`.
- SHA-256: `04310f01d0876ad8a6be16afd37d157b2a70e48f8940b64c7ed8d366eaabcf1b`.

It belongs to Office, not rd-cl. Inspect the actual Office Git root, exact commit,
`git ls-tree`/`git show`, sparse-checkout and local object availability if absent
on S2; do not replace it with a different contract or change authentication.
