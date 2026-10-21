# Offline S2 codec bootstrap for rd-cl 1.4.13+71

Application source baseline: `1be7642b56af58d3fb27c400e52a78200505e39b`.
Use the exact published **bootstrap tooling commit** from the handoff, which is
a descendant of that baseline containing only bootstrap scripts, tests and docs.
The application manifests, locks, dependency versions and existing verifier are
unchanged. This is a user-requested S2 prerequisite workflow, separate from cloud
or GitHub Actions builds. It never executes the product or contacts production.

## What is checked and preserved

Run on native Windows **S2**, with its existing owned NTFS snapshot/toolchain JSON.
Synchronize only published source through the existing source handoff first;
the snapshot HEAD and `.rd-cl-native-snapshot.json` source_commit must match the
full tooling SHA. Do not fabricate a marker for different source or discard dirty
work. Use the existing reviewed snapshot preparation procedure; return authored
changes to the source workstation. The scripts themselves never fetch source.

`windows-codec-bootstrap.ps1 -Mode Preflight` uses the unchanged native preflight
for source/profile/version, submodule, SDK22621, compiler, Rust/Flutter and existing
cache checks. It then checks the following **before codec compilation**:

- Existing triplet SHA256 must be either
  `e3cd9820386c639b8cbf844d43853cbc838f75a1488bfd4add98d5646c716538`
  or the canonical release-only hash. It is never edited. The new overlay is
  written with exact CRLF bytes, SHA256
  `323c6f88ab1a51ff02dacabd5d7f00e290fc5510acab1841d61ea3a8788e1a92`.
- Ten local source/patch archives, including Meson, must match the SHA512 pins
  in `windows-codec-bootstrap-inputs.json`. These come from the unchanged overlay
  ports, baseline ports and the two exact override trees in the build profile.
  Cached aom/libyuv Git archives are compared by full tar content to the pinned
  commits' existing local objects in `VCPKG_DOWNLOADS/git-tmp`. A filename alone
  is insufficient; missing objects are reported without fetching them.
- The pinned vcpkg recipe/history inputs must be available locally and unchanged.
  Its fresh install plan must contain exactly the sixteen pinned Windows ports
  and versions, with no removals, already installed packages or unknown dependency.
- The existing local vcpkg executable resolves CMake/Ninja/7zip/Git with asset
  origins disabled. Pinned CMake helpers check NASM, Perl, Python, Meson, Ninja,
  pkg-config and the exact MSYS closures used by the codecs. Helpers may unpack
  **local** archives only into the new private cache copy. Missing or incompatible
  inputs stop preflight; there is no pip, bootstrap-vcpkg, rustup install or fetch.
  The CMake chosen by vcpkg must match `paths.vcpkg_cmake` bytes; its actual local
  execution path and version are recorded.

This does **not** trust `vcpkg --only-downloads`: the pinned vcpkg tool can classify
an unintended portfile failure as DOWNLOADED. The dedicated helper audit fails on
the real CMake exit code instead. Offline flags/blocked asset origins/file-only
Git and process-local HTTP proxies remain active; these are tool policies, not an
OS firewall. No machine-wide network/security setting changes.

The isolated helper audit stages `vcpkg-cmake` before `vcpkg-cmake-get-vars` and
Meson, using the existing pinned local portfiles. An existing host installation
does not populate this separate audit root. The CMake integration regression
executes the published audit with synthetic helper ports and checks both dependency
availability and failure without it. On S2, set `RDCL_TEST_CMAKE` to the actual
installed CMake executable before the guard tests; an unavailable CMake is a
reported test skip on the coordinator, not a passing integration check.

Use an unused `Tools/codec-bootstrap/<name>` root. The script copies pinned local
vcpkg source/objects and its download cache there, with fresh native install,
package and buildtree locations. Existing installed codecs and download cache
are hashed before/after and never used as writable build destinations. The old
triplet, toolchain JSON, any compiled-cache receipt and previous verified delivery
remain untouched. The private copy is retained as the new reusable codec cache,
not a second application delivery. No cleanup or compression is performed.

The current input copies plus a 5 GiB free-space floor are required before the
first compilation; this is a minimum reserve, not a peak-space guarantee. A
reviewed `drive_alias` is reused to avoid spaces/MAX_PATH; no mapping is replaced.
Concurrent bootstrap invocations for the same root are refused by an exclusive
lock. After an interrupted invocation, inspect its lock/state; do not force-remove
it or silently replay compilation. A failed compilation is retained for diagnosis.

## Execute on S2

Fill only the three machine-local paths and the full published tooling SHA below.
Use native PowerShell, normal user privileges, and the **same reviewed drive alias**
as the existing native build. `paths.vcpkg_cmake` must explicitly name the already
installed codec CMake. Existing Brotli remains a later EXE packaging prerequisite;
this codec workflow neither reinstalls nor modifies it.

```powershell
$toolchain = '<existing S2 toolchain-local.json>'
$existingTriplet = '<existing S2 x64-windows-static.cmake>'
$snapshot = '<owned S2 snapshot at published tooling commit>'
$published = '<full published tooling SHA from handoff>'
$cfg = Get-Content -LiteralPath $toolchain -Raw | ConvertFrom-Json
$codecRoot = Join-Path $cfg.artifact_root 'Tools\codec-bootstrap\1.4.13-71-s2'
$output = Join-Path $cfg.artifact_root 'Builds\rd-cl\1.4.13+71\codec-bootstrap-s2'
$bootstrap = Join-Path $snapshot 'scripts\windows-codec-bootstrap.ps1'

# Confirm snapshot HEAD/profile/marker using the existing source handoff first.
& $cfg.paths.python -B -m unittest discover `
  -s (Join-Path $snapshot 'scripts\tests') -p test_windows_codec_bootstrap.py -v
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap guard tests failed' }

& $bootstrap -Mode Preflight -Toolchain $toolchain -SourceCommit $published `
  -OutputRoot $output -CodecRoot $codecRoot -ExistingTriplet $existingTriplet

# Run only after the exact preflight above passes. Compile repeats every check.
& $bootstrap -Mode Compile -Toolchain $toolchain -SourceCommit $published `
  -OutputRoot $output -CodecRoot $codecRoot -ExistingTriplet $existingTriplet
```

Preflight creates `codec-preflight.json` with status **PREFLIGHT_PASS_NOT_COMPILED**;
it is not a compiled-cache receipt. On missing input, retain the exact missing
path/hash and BLOCKED result. No download, cache purge, ABI edit, alternative
compiler/dependency version or fallback build is authorized by this workflow.

Compile executes a fresh `vcpkg install --no-downloads --no-binarycaching`, one
job, on S2. For aom, ffmpeg, libjpeg-turbo, libvpx, libyuv, mfx-dispatch and opus,
receipt generation requires fresh object files, static libraries and ABI records.
Compiler paths and compiler/linker/CMake executable hashes must match the checked
local tools. A successful process exit or copied .lib alone is insufficient.
The script checks preservation of the original installation/cache, source pins
and triplet, runs **the existing `require_verified_codecs()` without changes**,
and requires the existing installed-only dry-run plan guard to pass.

Only then does it publish `compiled-cache-receipt.json` plus a separate
`toolchain-codecs-local.json`. The latter selects the new codec root/CMake and
receipt; the original JSON is not edited. The receipt contains S2 object/library,
installed-tree/ABI, overlay and local tool hashes, compile log/step provenance and
the source commit. It is explicitly **codec-only**: it cannot enable the smaller
warm-application space reserve or claim a completed rd-cl/EXE build. No S1 receipt
is read, copied, rehashed or accepted as compilation proof.

## Resume the existing release workflow

After Compile PASS, use the generated local JSON for the existing S2 build:

```powershell
$codecToolchain = Join-Path $output 'toolchain-codecs-local.json'
$delivery = Join-Path $cfg.artifact_root 'Builds\rd-cl\1.4.13+71\delivery-s2'
& (Join-Path $snapshot 'scripts\windows-native-release.ps1') `
  -Mode Build -WithExe -Toolchain $codecToolchain `
  -SourceCommit $published -OutputRoot $delivery
```

This is a separate application build with all original guards/tests enabled.
Preserve the previous verified package until the new package passes its required
checks and the Office `office-release-maintenance` plan/apply/verify gate. Do not
install, launch, publish a release, deploy or connect to production as validation.

Return the exact source/tooling SHA, Preflight/Compile status, current log path,
receipt SHA256, actual compiler/CMake paths/versions, triplet SHA256, preserved
cache results and subsequent application build status. If blocked, return the
first failing input/command and exact exit code, without claiming compilation.
The reviewed scripts/stdlib tests on Linux do not establish native S2 success;
that remains NOT_RUN until these commands actually complete there.
