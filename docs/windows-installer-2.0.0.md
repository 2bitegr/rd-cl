# Windows installer correction — rd-cl 2.0.0

Status: source changes prepared locally, not published or built on native S2.
Rust/app version is `2.0.0`; Flutter release is `2.0.0+72`, Windows installer
resource version `2.0.0.72`. Only the two local workspace Cargo.lock package
versions changed. Third-party dependency versions and authentication are unchanged.

## Failure and correction

The user reported a broken Desktop shortcut, no installation error, a stopped
service and core1.4.11 after using the historical S2 delivery. The submitted
SHA256SUMS equals the original delivery manifest; that alone does not establish
the actual installed/loaded files or installer bytes on the destination PC.

Source inspection found the branded shortcut/service target `Exantas Support.exe`
but the fresh-install copy left the source executable as `rustdesk.exe`. Both
fresh install and upgrade now share copy/rename/byte-verification commands before
registry metadata, shortcuts and service registration. The executable, native
core, Flutter DLL and AOT/data core files are compared byte-for-byte; all files
are copied by XCOPY, with continuation-on-error `/C` removed. This is not a full
cryptographic installed-tree verification; independently compare the runtime
inventory against the delivery manifest during native acceptance.

Space-containing service names, process names and registry keys are quoted.
Essential copy/move/FC/registry/shortcut/firewall/service-create/start commands
abort the install/update script on failure. The existing one-shot
`--import-config` service launch may return1053 because it exits without becoming
an SCM service; only that marked launch accepts1053. The real service start
continues to reject1053 and all other errors. Stop/delete/taskkill of absent old
services/processes remain best-effort; locked files still fail copy/verification.
The elevated result and failure marker are checked. Failed scripts/step records
are retained at the paths shown in the error. Interactive install errors display
a message and return failure rather than logging and exiting successfully.
A failed update does not run its success-path session restoration.

Fresh install/reinstall no longer recursively removes the old installation
folder first; unrelated existing files/configuration remain. Installation is
not transactional: a failed copy may have replaced some files and stopped the
old service. Do not claim rollback or automatically relaunch an uncertain payload.
An MSI-managed existing installation is rejected explicitly by the EXE installer
rather than silently bypassing Windows Installer ownership. Use its managed
migration procedure separately; this release does not add MSI migration support.

The native build checks generated Rust VERSION against the profile and checks
that Flutter's bundled librustdesk.dll equals the DLL from the selected Cargo
output. `native-core-identity.json` records those values and hashes. This is
compile/packaging evidence; it does not replace observing the actually loaded
DLL/version after installation.

## Native validation before accepting delivery

Run `python -m unittest discover -s scripts/tests -p 'test_windows*.py' -v` with
the existing pinned Rust available on PATH (or RDCL_TEST_RUSTC), CMake and pwsh.
The installer suite compiles/tests the real pure Rust command generator. Three
additional native Windows tests operate only in temporary synthetic folders:
rename/success with spaces, missing source DLL versus stale installed DLL, and
an exclusively locked installed DLL. They never install the product or touch
services/registry. Linux explicitly skips these three cmd/XCOPY/FC tests.

Build on S2 only after exact source publication, using the maintained handoff and
new SDK-bound codec receipt migration. Keep the old receipt/codecs/package intact.
Use a new unused OutputRoot under the actual Desktop hierarchy, e.g.
`Office-Workspace-Artifacts\Builds\rd-cl\2.0.0+72\delivery-s2-<source-sha>`.
The planned EXE is `rd-cl-2.0.0+72-windows-x64-install.exe` directly under that
OutputRoot. No such new EXE is established by these source checks.

Installation/runtime acceptance is separate from the build handoff. When
explicitly authorized, use a disposable native Windows test machine/snapshot:

- Clean install: default branded path containing spaces; verify shortcut resolves
  to an existing2.0.0 EXE, actual loaded DLL hash matches delivery, version2.0.0,
  service binary path/status as selected by installation options.
- Upgrade: old supported EXE installation with synthetic retained configuration;
  verify new binary/core/version, working shortcut, retained configuration and
  unrelated files, service startup according to prior options. Use an actual old
  build; synthetic copy tests cannot establish application upgrade acceptance.
- Failure: deny/lock a required payload or deny a mandatory step; require visible
  failure, retained step/script evidence and no success report. Never inject a
  failure into a real production installation.

Record installation, upgrade, service and runtime results separately with actual
paths/hashes. Preserve failed historical evidence. No automatic install, service
restart, production connection, signing or deployment is part of source/build work.
