# Office-managed sequential silent updates

This is an unreleased source change. No new application/EXE has been built or
installed and no recovery task/service has been created by development tests.
The existing delivered 3.1.2 package lacks this updater and needs a one-time
normal upgrade. Authenticode signing is not a requirement for the user-approved
Office update channel.

The full coordinator, hosting, migration, policy and activation contract lives in
Office `docs/rdcl-silent-updates.md`. Producer/consumer source:

- `flutter/lib/models/exantas_update_registration.dart`: optional installed-client
  bootstrap through stdin; portable and technician contexts are excluded.
- `src/office_update.rs`: protected service enrollment, separate machine authority,
  public-key verification, update admission barrier and constrained helper commands.
- `res/office-update.ps1`: signed extraction, exact inventory, durable journal,
  previous-runtime recovery, verified alternating host slots and owned startup task.
- `libs/portable`: extraction-only mode, with checked decompression and no product
  installation/GUI launch. The normal interactive installation path stays available.
- Incoming/outgoing session admission, ID-reset reservation and manual installer
  batch paths participate in the same update fence. Machine network registration
  does not stall the service's session-maintenance loop.

Update payloads/reports use protocol 2 and the explicitly signed policy
`office-ed25519-v1`. The native verifier rejects absent/unknown policies and legacy
publisher-thumbprint metadata. Protocol-1 clients are ineligible for new permits.
The Ed25519 signature authenticates the exact package/runtime hashes; an unsigned
Windows EXE can then be extracted. Unknown/missing signatures never fall back to
hash-only or generic execution. Windows security policies stay effective; policy
errors fail/stop the rollout, without security exclusions or trust-store edits.

Private signing keys stay encrypted on S1, outside repositories and customer/server
storage. Passphrases travel only through protected stdin. Before activation, keep a
separate protected encrypted backup and separately stored recovery passphrase, and
verify the backup derives the same public key. No production key is made by tests.

The machine token and journal live under SYSTEM/Administrators-only
`C:\ProgramData\ExantasRdclUpdates`. Diagnostic exports must exclude credentials.
Do not remove the journal or force an unknown fleet result to successful. A lost
ACK never authorizes a second physical installation. A changed customer/peer or
parent enrollment invalidates authority instead of silently rebinding it. Root
signing keys are pinned at bootstrap; use an already trusted key for subsequent
releases. Root key rotation requires its own reviewed trust rollout.

Manual install/update/service-removal/uninstall batches first stop only the owned
worker and recovery task through the existing elevated path. A physical operation
already underway prevents that action. Reinstall clears only the owned stop marker.
Recovery/history/configuration are retained. No UAC bypass or global policy change
is used. A changed install path or enrollment needs explicit binding review.

## Targeted verification and acceptance matrix

| Scenario | Local proof | Real Windows acceptance |
| --- | --- | --- |
| Bootstrap stdin, timeout, denied/late process, portable/technician exclusion | New Dart unit fixtures; affected identity/enrollment suites | NOT_RUN |
| Canonical increasing versions and Windows-safe paths | Native Rust policy unit tests | Full application compile NOT_RUN |
| Atomic file replacement, locked file, corrupt hash, unknown files, hardlink alias | Native PowerShell temporary-file fixtures | Installed runtime/AV interference NOT_RUN |
| Four two-file old/new power-cut mixtures, new-only removal, unrelated customer data | Real recovery function with mocked product services/API | Physical power-cut/reboot NOT_RUN |
| Independent host promotion and unrelated task preservation | Native fixture, task APIs mocked | LocalSystem boot task NOT_RUN |
| Lost permit and success replies, durable action ID, no repeated replacement | Native fixture + real isolated Office PostgreSQL transactions | Customer network interruption NOT_RUN |
| One global slot, pilot/soak, expiry, unknown hold, pause, revoke | Office PostgreSQL fixture and admin browser fixture | Live API/DB NOT_RUN |
| Busy/admitting sessions, ID reset, manual install/uninstall fence | Source integration and targeted existing tests | Real concurrent process/session races NOT_RUN |
| Office-signed metadata, unsigned EXE extraction, exact source/inventory/hosting manifest | Office crypto/encrypted-key tests; native mocked extraction and Windows-policy rejections | Real package clean-install/upgrade and Windows policies NOT_RUN |
| Version/service/identity/profile preserved, rollback, tray restart | Source contract and synthetic recovery | Customer acceptance NOT_RUN |

`python -m unittest discover -s scripts/tests -p test_windows_office_updates.py`
runs the native synthetic recovery suite on Windows. It creates only an owned
TEMP fixture, mocks task/service/network operations, binds the result to the source
SHA256 and removes only that fixture. Non-Windows execution is explicitly skipped.
The new Dart registration test is included in `windows-native-build.py`'s pinned
regression list. Reuse compatible existing tools/caches; no downloads or bootstrap
are needed merely to run these new isolated tests.

S2 must eventually compile the published Windows source and package a new version
through the normal single build invocation, source/codec/SDK/ABI and artifact gates.
Only packages with accepted native installation/upgrade and Office-signed metadata
qualify for fleet distribution. Authenticode may be absent. Plain unsigned
interactive hosting remains possible under the existing honest NOT_RUN policy. Before production rollout, run real
clean-install/upgrade/rollback, active-session, identity/configuration, boot-recovery,
manual uninstall/reinstall and interruption acceptance on the selected pilot.
No such build, installation, activation or rollout is authorized by this source task.

## 3.1.3 source publication — 2026-11-17

This is the first updater-capable baseline, coordinated with Office 1.12.60. The
completed 3.1.2/babdbfc0 package remains the previous verified S2 delivery and has
no updater. Upgrade a selected installation normally before testing the channel.
Source publication is not a new EXE or native acceptance. S2 must build this exact
published source once, reuse verified compatible tool/codec/application caches,
verify all package and maintenance gates and host the common interactive EXE.
Do not attach silent-update metadata without actual matching clean-install and
upgrade acceptance. S1's encrypted private signing key and recovery secret stay
on S1; S2 receives only public keys or already signed metadata. Runtime/DB policy
stays OFF/paused until separate explicit activation.
