# rd-cl build tasks

- SOURCE CHECKPOINT (2026-10-19): user-authorized commit and Git synchronization
  of the current rd-cl branch, covering technician ID maintenance and unified
  native sign-in source/tests. Native version remains1.4.12+70. Current native
  auth files match the15-file tested source receipt; full native DLL/DPAPI and
  real-session acceptance remain NOT_RUN, and the declined hbb_common test stays
  BLOCKED. Office API/native-issuer publication and rollout are separate; the new
  sign-in consumer is not deployment-ready until both producers are delivered.
  Retain the dirty upstream hbb_common checkout; its reproducible local changes
  are carried by patches/hbb_common-exantas-config.patch. No build, dependency
  download, installation or production action belongs to this Git checkpoint.

- SOURCE IMPLEMENTED / NATIVE ACCEPTANCE PENDING (2026-10-18): user-approved
  unified Office/native sign-in source/tests.
  New Windows DPAPI lease, native connection/audit reader, preflight/refresh/logout
  and identity/ambiguity fences. Native access_token/non-Windows behavior retained.
  Contract: docs/office-native-auth.md and Office producer contract. No native
  installation, version bump, downloads, Git or live actions. Pure Rust policy
  and Flutter regression checks recorded by Office; full native integration pending.
  The existing declined hbb_common ID-persistence test remains BLOCKED.

- BUILD PACKAGED / NATIVE ACCEPTANCE PENDING (2026-10-18): Technician-only Settings ID regeneration.
  Native daemon rechecks the existing Office workflow-capabilities authority,
  closes the old pairing, rejects active sessions/stale IDs and persists a new
  numeric ID with a recovery snapshot in the existing protected config folder.
  UI/legacy IPC paths stay guarded; no API/schema change or live reset.
  Flutter Settings/report26, bridge generation and affected Dart analysis PASS.
  Full build Dart regression suite44 PASS on2026-10-18, existing dependencies only.
  Final10 native tests NOT RUN: compiler stopped below1.5GiB C: reserve; caches
  and targets retained. Atomic reservation/blocking worker respect Tokio rules.
  Config tests BLOCKED by existing
  webrtc-util dev dependency versus installed Rust1.75. Exact isolated test-only
  exclusion declined by the user on2026-10-18; keep this test BLOCKED. Proposal
  not applied; no dependency/tool workaround authorized. No version bump,
  downloads, installation, commit/push or deployment performed.
  Resume2026-10-18: approved C1-C7 exact10 files removed,722034645 logical
  bytes; measured C: free-space gain722042880 bytes. Existing deliveries/tools/
  caches retained. Build began at5.02GiB, bridge/Dart44 PASS, then stopped at
  unchanged5GiB guard with4.97GiB before Rust compilation; no package/download.
  Exact C8-C9 then approved/applied:91 redundant MSI-payload files plus
  Popup1.4.4 installer,126326536 logical bytes; measured free gain126410752.
  Build resumed at5.08GiB: bridge/Dart44/codecs/frozen Rust1.75-MSVC/Flutter
  Windows/ZIP/MSI PASS. Independent ZIP91 member hashes, PE1.4.12+70, MSI
  x64/1.4.12.70 and artifact plan/apply/verify PASS. Delivery:
  Builds/rd-cl/1.4.12+70-identity-settings; dirty-source manifest records canonical
  b7a995a/native5eec995 plus19 reviewed feature files. C: minimum3.29GiB,
  final3.99GiB; compiler processes finished/owned R: removed. New MSI staging
  retained under only-C8-C9 deletion scope. No install/ID/production/Git action;
  config test remains BLOCKED, native10 not rerun after prior disk failure.

- PAUSED checkpoint (2026-10-16): User stops after CallerPopup1.4.1 live setup
  and authorizes publishing the current rd-cl1.4.12+70 source/build tooling.
  Native runtime version/staff-role sign-in UI and removal of Enroll are ready;
  retained device credentials and server/API contracts are unchanged. Existing
  16 stdlib offline guards freshly PASS with only an owned loopback HTTP fixture;
  the initial sandbox-only socket denial passed on the permitted local rerun.
  Earlier37 Dart/native build/MSI/ZIP evidence remains applicable to unchanged
  functional source. Full staff pairing/GUI/remote-session acceptance is pending.
  No new build/download/install/customer-PC or production operation for this
  Git checkpoint. Earlier no-commit statements below describe those build runs.

- PASS (2026-10-16): User-approved exact storage candidates7–10 removed (214files,
  255935996bytes); retained recovery ZIPs/current apps/source/toolchains/caches.
  Native1.4.12+70 Build -WithMsi with existing inputs only PASS;37 Dart tests,
  codec ABI/installed-only plan, Rust/Flutter and ZIP/MSI/PE/hash checks PASS.
  Recorded dirty UI/version delta plus previous approved lock/tooling inputs.
  Artifact plan/apply/verify PASS0 extra removals; sole current MSI input retained
  because generated Includes.wxi/components still reference its protected runtime
  assets. Previous1.4.11+69 rollback retained. No install/product launch/signing,
  production/customer-PC change, dependency download, commit or push.
  Receipt: <ARTIFACT_ROOT>/Reports/2026-10-16/live-support-scenario/rd-cl-build-result.json.

- DONE (2026-10-15): Removed eight superseded build-run folders and verified
  MsiPayload/Triplets staging; retained latest ZIP/MSI, sources and offline caches.
  Updated Office/rd-cl AGENTS.md artifact-retention policy. Compact historical
  evidence/deletion manifest is in the Desktop rd-cl-artifact-cleanup report.
- DONE (2026-10-15): Second pass of the existing-cache native Windows workflow.
  Fixed constructor drive-alias cleanup, ENOSPC root-error reporting, installed
  codec/tool/overlay verification with a no-action vcpkg dry-run, and the exact
  cached FRB build_runner language-experiment argument.
- PASS: 16 stdlib guard tests on Linux and native Windows (no native skips),
  real Windows subst cleanup after injected initialization ENOSPC, 37 Flutter
  tests, frozen Cargo metadata/build, native Windows release and ZIP/MSI for
  1.4.11+69 x64. Package SHA-256 and portable ZIP CRC verified. Product launch,
  installation/signing, Windows runtime and Linux release build were not run.
- PASS: No added/removed/size-changed cache inventory entries; installed codec
  ABI/library27, overlay53 and generated bridge4 hashes match the prior receipt.
  All942 original tracked-file hashes and preexisting dirty changes preserved.
  The first pass's low-space block is superseded by this successful full build;
  early space guards and atomic receipt writes remain active.
- User cancelled Windows-only conversion/Linux cleanup: both platforms retained.
  Downloads stay disabled and missing dependencies stop. No dependency changes,
  Linux deletion, product installation/launch, commit/push or production actions.
  Procedure: docs/windows-native-build.md. Private second-pass evidence/packages
  are in the verified Desktop artifact root under Reports/2026-10-15 and
  Builds/rd-cl/offline-second-pass-b7a0c912.
