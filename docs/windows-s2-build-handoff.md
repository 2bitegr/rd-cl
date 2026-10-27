# One complete rd-cl build prompt for S2

Trigger: when the user requests Office commit/push, inspect both repositories
before publication. Include related reviewed task-owned rd-cl changes in that
coordinated publication unless the user explicitly limits scope. Apply each
repository's live-ref, source review and cleanup Git gates; preserve unrelated
work. Office and rd-cl require their own commits/pushes. Never treat an Office
push as publishing local rd-cl changes or silently build the old remote source.
After successful publication (also when reported by the user), verify both live
refs and compare the published rd-cl target with the last completed application/
EXE baseline. Return one complete S2 prompt in the same response if pending;
otherwise NO_RDCL_BUILD_NEEDED. A blocked necessary publication is reported as
BLOCKED; never fill a build handoff with unpublished or invented SHAs. Unknown
completed state means BASELINE_UNKNOWN. Do not duplicate an outstanding handoff
for the same SHA unless explicitly retrying.

The first execution phase in the prompt is safe pull/synchronization of the
published Office instructions and rd-cl source, then exact commit/submodule
verification, then build preparation. S2 consumes published commits; it never
creates commits or pushes. Use fast-forward only, preserving dirty/diverged work
without reset/rebase/clean/auto-stash. Build only the supplied immutable target
in a matching owned snapshot, never a moving branch HEAD.

Read current `scripts/windows-native-profile.json`, `windows-native-release.ps1`,
`windows-native-build.py`, [native build](windows-native-build.md) and
[codec bootstrap](windows-s2-codec-bootstrap.md) and
[build integrity/migration](windows-s2-build-integrity.md). Verify current wrapper parameters
and product/package versions before generating the handoff. Do not substitute
older source or bump versions to build. Record the last handoff/source/package
receipt and update it on explicit retry rather than duplicating work.

Produce one self-contained prompt in Greek. Fill the source/version/diff fields
below from live evidence before returning it; do not leave moving refs or invented
SHAs. Use verified machine-local paths from current S2 reports when available;
otherwise direct S2 to discover/prepare them locally in the same prompt. All normal
phases proceed without another prompt when their prerequisites pass. A real
failure blocks dependent phases and returns exact diagnostics; it never licenses
guard changes or source corrections on S2. Since 2026-10-22 required pinned
downloads are allowed during preparation; explicit offline tasks still prohibit
network acquisition. Guarded build/codec invocations remain offline unchanged.
Older offline execution guides describe that guarded phase; their historical
no-download wording does not reinstate the removed preparation policy ban.



### Continuation after a blocked S2 build

Every future prompt must distinguish the last completed delivery from the latest
attempt and record the attempted SHA, exact failed gate, artifact status, newest
genuine receipt/toolchain and warm application targets. A compiled/packaged EXE
with failed analyzer or maintenance is BLOCKED, never the completed baseline.
For source corrections, verify and supply both full published SHAs before issuing
an executable replacement-build prompt. If the fix remains local, provide only
preservation/read-only preparation with WAITING_FOR_PUBLISHED_FIX; do not point
S2 at the failing SHA as a corrected target or invent a future SHA.
Preserve the failed attempt and previous verified delivery. Use an unused owned
snapshot/output for the corrected SHA, while reusing independently verified
codec receipts and compatible Cargo/Flutter caches. Application-only corrections
do not justify FFmpeg/codec bootstrap. Recheck the exact receipt/tool/SDK/ABI
inputs; real incompatibility blocks reuse rather than fabricated proof.
Schedule the pinned analyzer as soon as generated/package prerequisites are
verified and before expensive native compilation where the reviewed tooling
supports it. Preserve its complete command, exit code and all diagnostics; no
suppression/fatality-flag changes or source edits on S2. A successful old stage
is useful cache evidence, not permission to skip checks for a changed source.
Required approvals remain covered by the explicit scoped approval block, with
mandatory platform mechanisms intact. Publication/deployment/real installation
and customer acceptance remain separate.

### Explicit user approval in every S2 build prompt

User instruction (2026-10-24): include an explicit user-approval block in every
future rd-cl S2 build handoff. Approval covers the specified published-source
synchronization, owned snapshot/config preparation, required pinned downloads
and prerequisite provisioning (including necessary native UAC), existing-receipt/
cache verification and reuse, tests/analyzer, application build, packaging,
hashes/reports and reviewed task-owned cleanup under the existing gates. Proceed
through those authorized phases without asking the user to approve them again.
For an already running job, continue from its actual stage with the same approved
SHAs/config/outputs; do not restart, change source or repeat completed phases
merely to apply this approval. Preserve active processes, source and caches.
The2026-10-27 hosting policy also authorizes scoped verified artifact publication
and native acceptance only inside an owned disposable Windows environment.
This is not permission for product installation on the S2 host or customer PCs,
deployment, production DB changes, real customer sessions, source/guard changes,
credential disclosure, Git publication on S2 or unrelated destructive operations.
It does not override sandbox/tool/UAC approval mechanisms: use required approvals
normally, never disable/bypass them or claim a prompt removes them. When mandatory
platform approval is still needed, explain the concrete action and platform rule;
when automatic review rejects it, report its reason and preserve dependent work.

## Mandatory latest-only server phase —2026-10-27

For every changed-rd-cl build handoff include the reviewed hosting phase from
Office docs/rdcl-installer-hosting.md. The technician operates the install on the
customer computer; no customer confirmation or staff login on that PC is needed.
After verified EXE/native acceptance, use existing verified server access and the
exact Office publisher to stage/check the new public HTTPS file, atomically
activate it and remove only the old manifest-owned EXE. Hosting retains only the
latest approved installer; keep rollback delivery/caches on S2. Missing access,
shared mounts, rollout or native evidence blocks only that dependent phase and
must be reported. No guessed URL/receipt, broad cleanup, SQL, S2 Git publication
or automatic Dokploy rollout. Carry this phase in the single prompt; do not ask
for another prompt merely because build and hosting are separate steps.

## New customer installation candidate —2026-10-27

Version2.0.1+73 adds the customer enrollment panel and guarded technician preview/
recovery flow coordinated with Office1.12.17. See customer-device-enrollment.md.
It also includes published b948/af37 native lifecycle/analyzer corrections since
completed1c7cff12. New source SHA comes from the coordinated publication receipt;
never build an unpublished candidate or substitute the older2.0.0 EXE. This
candidate supersedes the outstanding af37 handoff, not the completed baseline.
Require the new exantas_device_enrollment_test.dart along with existing Dart
regressions/analyzer before native compilation. Preserve SDK-aware codec receipt,
ABI/SDK/tool pins and warm caches; product version change is not codec drift.
No new SQL migration. The resulting EXE needs an agreed HTTPS hosting location
and matching Office installer descriptor before customer download is enabled.

## Latest attempt: b94834c7 — analyzer BLOCKED, 2026-10-26

User S2 report: owned snapshot/pins, codec reuse and tools/SDK/ABI/plan PASS;
guards89 PASS/1 Linux-only SKIP; application Preflight PASS. Analyzer exit2:
common.dart:3:8 UNUSED_IMPORT dart:math (0 ERROR,1 WARNING,47 INFO).
Native compilation/ZIP/EXE and maintenance NOT_RUN; EXE NOT_PRODUCED.
Keep this failed attempt's evidence and completed1c7cff12 package unchanged.
Source correction removes only the unused import and refreshes its integrity
hash. New published SHA and separate owned output are required; analyzer runs
before native compilation, with unchanged diagnostics policy. Reuse genuine
receipt784aba54...6572 and compatible warm application caches; no codec rebuild
is justified by this import-only correction. Office remains74142de7...234e4.

## Current completed application/EXE baseline

Latest S2 completion, user report on 2026-10-24. Package/log bytes on Windows
were not independently accessed here; these are reported native S2 results.

- Source/tooling: `1c7cff1289438b84788b3b2b78ab30c05ce25202`, branch
  `codex/s2-codec-bootstrap-1.4.13`; Office `09e6bb1f4cda905ec249f02a23fc2852314d8442`.
- Version/target: `2.0.0+72`, Windows x64; existing unsigned EXE format, no MSI reported.
- Directory: `C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.0+72\delivery-s2-1c7cff12`.
- Filename: `rd-cl-2.0.0+72-windows-x64-install.exe`; size `24312320` bytes.
- SHA256: `e567886417f4d779299937ff626ca7da31aee790b4f33c4a9e6ffa417080d088`.
- PASS: guards89/1 Linux-only skip; Dart70; analyzer exit0, no WARNING/ERROR,
  10 retained INFO; codec reuse/Preflight/Rust/Flutter/EXE; exact93 runtime-file
  ZIP/embedded inventory, core DLL/x64/canonical icons; maintenance plan/apply/verify.
- Release invocation16m06s; Flutter138.4s. This is not total agent elapsed time.
- Cleanup removed4 redundant wrapper logs,3767 bytes; previous deliveries/caches retained.
- Toolchain SHA256: `0b07fdfce291343d7a5f51b26275858c70faaed277da39347f61c18dcdbe0b70`.
- SDK-aware receipt SHA256: `784aba5498e0a84922367ff58e506940c60b445958bc8ceda1ccf0b0e4796572`.
  Discover the actual current config path from the completed manifest/BUILD-STATUS;
  do not infer the filename or mutate the receipt.
- Siblings: ZIP, manifests, SHA256SUMS, analyzer log, BUILD-STATUS.md, INSTALLATION-EL.md.
- Installation/upgrade, GUI/DPAPI/services/auth/real remote connections: NOT_RUN.
  Production SQL, deployment and automatic billing: NOT_RUN.
- Preserve earlier completed a23ec301 and blocked d029c35d evidence. The final
  checksum helper initially misresolved a portable prefix; the report records a
  corrected local read-only helper using the published prefix, not a source/guard change.
- No repeat build for this completed source. This report/documentation update
  does not itself authorize another build or installation.

Preserve the previous ad46faef58b5773fc662f021c00ed2f92a9c675a/1.4.13+71
historical delivery and its evidence. Its historical packaging PASS and failed
user installation do not establish acceptance of the new installer.

Before the next build, assess the latest successful application target and
compatible Flutter state for reuse; never allocate a cold target solely because
source SHA/delivery path changed. Keep new source snapshots/deliveries separate.
The a23ec301 run used a cold target because the previous native cache was ambiguous,
not because codecs were missing. Preserve that successful target; verify exact
paths/tool/SDK/codec provenance locally. Do not reuse an ambiguous old cache or
change -j1 locally. See windows-native-build.md for measured timings and limits.

Historical codec inputs to preserve (SDK identity is absent; current hardened
tooling requires new isolated compilation before reuse):

- Toolchain:
  `C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\1.4.13+71\codec-bootstrap-s2\toolchain-codecs-local.json`.
- Sibling `compiled-cache-receipt.json`, SHA-256:
  `3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97`.
- Known codec CMake: `C:\Program Files\CMake\bin\cmake.exe`.

These are reported S2 paths, not a universal username/Desktop assumption. The
codec root is selected by the JSON; the `codec-bootstrap-s2` receipt directory
is not necessarily that root. Keep this completed delivery unchanged. Future
builds use an unused owned output directory (even at the same product version),
not this occupied verified `delivery-s2` folder. Update this compact baseline only
when the user returns a newer completed application/package report. Record a
pending handoff separately; issuing a prompt cannot advance completed state.
If the live target SHA still equals this source, return NO_RDCL_BUILD_NEEDED.

## Historical d029c35d attempt: BLOCKED, superseded by completed 1c7cff12

User report2026-10-24 for source d029c35d3771be508376a1986251d66d8351fa82:
codec reuse PASS, guards89 PASS/1 Linux-only SKIP, Dart70 PASS, native application
and EXE compilation PASS. Analyzer FAIL (remote_page.dart catchError returned
Null for Future<MultiWindowCallResult>); final maintenance NOT_RUN. Keep the
installer under delivery-s2-d029c35d as BLOCKED and do not install it or advance
a completed baseline. The later 1c7cff12 run passed; keep this failure historical. See office-session-close.md for exact hash/size.

The reported SDK-aware codec receipt SHA256 is
784aba5498e0a84922367ff58e506940c60b445958bc8ceda1ccf0b0e4796572.
Its toolchain JSON is reported at:
C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.0+72\delivery-s2-d029c35d\toolchain-codecs-d029c35d-local.json
Verify those bytes, root and actual local tool/SDK/ABI identities on S2. Preserve
and reuse this receipt plus successful Cargo/Flutter targets for the type-only
source correction. No codec rebuild is justified by that correction. A retry
needs a newly published source SHA and separate owned delivery; run analyzer
with existing pinned tools before expensive compilation when generated inputs
are ready. Never ignore diagnostics, reuse the blocked EXE as corrected output,
change guards or mutate source on S2. Preserve diagnostics and normal gates.

## Required branding for the next handoff

Use [canonical Windows icons](windows-branding.md), pinned to immutable
cf634df336de55daf3d67273a91194e427369e31 with exact per-file hashes. Source
publication must restore/verify all five assets before a new branding-compliant
handoff. A rule alone does not change the source assets. S2 verifies the published
snapshot; it does not cherry-pick/copy historical icons locally. Preserve running
historical builds/provenance and compatible codec evidence. Verify tray, runner,
installer and Desktop icon selection; separate runtime appearance acceptance.

## Required tooling behavior learned on S2

Read [the reviewed tooling explanation](windows-s2-shallow-vcpkg.md). Preserve:

- Local helper dependency order: vcpkg-cmake before get-vars/Meson; strict
  separation of the exact empty compiler probe from actual codec outputs.
- Actual pinned baseline/version/tree/subtree/blob checks, overlay precedence,
  no lazy fetch and the exact 16-port installed-only closure for this profile.
  Shallow state alone neither rejects nor proves readiness.
- Hardened cl/link/lib/CMake/vcpkg and SDK/triplet/codec/ABI verification. The
  historical receipt requires migration through a new actual isolated compile.
  Once that new receipt exists, application-only SHA changes do not require
  another codec rebuild. Preserve the old root/receipt/package unchanged.
- Exact pinned hbb_common plus reviewed patch; extra tracked/staged/untracked
  source is rejected. Exact runtime/ZIP inventories; no extra payload files.
- Single locked release session across Build and EXE/MSI. A busy/changed/stale
  lock is investigated, never deleted automatically.
- After VsDevCmd, exactly one `VCPKG_ROOT` must come from the configured,
  drive-aliased `paths.vcpkg`. Inspect `native-vcpkg-root.json` and native logs;
  do not accept Visual Studio's bundled vcpkg or patch hwcodec on S2.
- Canonical process-local TEMP/TMP, the existing drive alias, offline/frozen
  package commands and all original guards. Do not clear reusable targets.

## Prompt content

```text
ΕΓΚΡΙΣΗ ΧΡΗΣΤΗ: Έχεις τη ρητή έγκρισή μου για όλα τα αναγκαία βήματα
αυτού του συγκεκριμένου build: ασφαλή συγχρονισμό των δοσμένων published SHAs,
owned snapshot/config, απαιτούμενες pinned λήψεις και prerequisite provisioning
(με αναγκαίο UAC), επαλήθευση/επαναχρησιμοποίηση receipts και caches, tests,
analyzer, compilation, packaging, hashes/reports και ελεγμένο task-owned cleanup
με τα υποχρεωτικά gates. Συνέχισε χωρίς να ζητάς ξανά την ίδια έγκριση.
Αν το build ήδη εκτελείται, συνέχισε από το πραγματικό τρέχον στάδιο με τα ίδια
εγκεκριμένα SHAs/config/outputs. Μην το επανεκκινήσεις, αλλάξεις source ή
επαναλάβεις ολοκληρωμένα στάδια μόνο εξαιτίας αυτής της έγκρισης.
Η έγκριση δεν καλύπτει εγκατάσταση προϊόντος, deployment, production SQL,
πραγματικές συνδέσεις πελάτη, source/guard edits ή commit/push στον S2.
Οι υποχρεωτικές εγκρίσεις sandbox/tools/UAC εξακολουθούν να ισχύουν· μην τις
παρακάμψεις ή απενεργοποιήσεις. Αν απαιτηθούν, εξήγησε τη συγκεκριμένη ενέργεια
και τον κανόνα της πλατφόρμας. Πραγματική αποτυχία σταματά τα εξαρτώμενα στάδια.

Προετοίμασε τα απαιτούμενα pinned inputs και εκτέλεσε το πλήρες build/package
του rd-cl στον native Windows S2. Επιτρέπονται οι αναγκαίες λήψεις κατά την
προετοιμασία, με TLS, signatures/checksums και ακριβή lockfile/Git/version pins.
Τα υπάρχοντα guarded build/codec scripts παραμένουν offline/frozen.

Office publication: <verified Office repository/ref/full SHA>
rd-cl repository/ref: <verified repository and published ref>
Ακριβές rd-cl SourceCommit: <full published SHA>
Version: <manifest/profile version including Flutter build number>
Target: Windows x64, EXE installer και το υπάρχον verified runtime ZIP.
Τρόπος: <initial build ή continuation από συγκεκριμένο failed gate>
Τελευταία ολοκληρωμένη προσπάθεια: 1c7cff1289438b84788b3b2b78ab30c05ce25202, PASS build/package.
Ιστορικό d029c35d: BLOCKED analyzer, δεν χρησιμοποιείται ως διορθωμένο EXE.
Νεότερο reported SDK-aware receipt:
784aba5498e0a84922367ff58e506940c60b445958bc8ceda1ccf0b0e4796572
Current toolchain SHA256:
0b07fdfce291343d7a5f51b26275858c70faaed277da39347f61c18dcdbe0b70
Εντόπισε το πραγματικό config από τα manifests της delivery-s2-1c7cff12.
Επαλήθευσε πραγματικό path/hash/tool/SDK/ABI στον S2 και κράτησέ τα αμετάβλητα.
Αυτό είναι ανεξάρτητο codec proof, όχι επιτυχής εφαρμογή ή νέο completed baseline.
Προηγούμενο completed application/EXE baseline: 1c7cff1289438b84788b3b2b78ab30c05ce25202
Baseline version: 2.0.0+72
Baseline EXE SHA-256: e567886417f4d779299937ff626ca7da31aee790b4f33c4a9e6ffa417080d088
(Ο αποστολέας ενημερώνει αυτά τα baseline πεδία από την τελευταία completed αναφορά.)
Αλλαγές rd-cl: <verified comparison and changed source/build-input paths>
Προγραμματισμένος κατάλογος EXE: <verified S2 Desktop OutputRoot, or discover as below>

Διάβασε τα AGENTS.md και docs/windows-native-build.md,
docs/windows-s2-codec-bootstrap.md και docs/windows-s2-build-integrity.md.
Το ιστορικό receipt χωρίς sdk_identity διατηρείται αλλά δεν χρησιμοποιείται
ως σύγχρονο proof. Υπάρχει νεότερο reported SDK-aware receipt παραπάνω:
έλεγξε/επαναχρησιμοποίησέ το πρώτα. Μην ξεκινήσεις το βήμα5 απλώς επειδή
άλλαξε το application source ή υπάρχει παλιό receipt.
Χτίσε την έκδοση του δημοσιευμένου source χωρίς δικό σου version bump.
Διατήρησε λειτουργικότητα, authentication και guards.
Αν το ζητούμενο SHA έχει ήδη παραδοθεί επιτυχώς, μην επαναλάβεις build·
επέστρεψε NO_RDCL_BUILD_NEEDED με το existing EXE evidence.

1. ΠΡΩΤΑ pull/συγχρονισμός των δημοσιευμένων commits, ΜΕΤΑ build.
   Επιβεβαίωσε native Windows host S2, Git roots/remotes και τοπική κατάσταση.
   Κάνε ασφαλές fast-forward-only pull/sync των Office οδηγιών και του rd-cl
   από τα ακριβή repositories/branches/SHAs που δίνονται παραπάνω. Έλεγξε live
   refs· μην υποθέσεις ότι το Office push δημοσίευσε και το rd-cl. Αν δεν είναι
   διαθέσιμο το ακριβές commit ή υπάρχει dirty/diverged σύγκρουση, διατήρησε την
   εργασία και επέστρεψε BLOCKED. Μην δημιουργήσεις commit και μην κάνεις push,
   reset/clean/rebase ή auto-stash στον S2.
   Επαλήθευσε τα ακριβή full SHAs, source/profile hashes και pinned submodule/patch.
   Προετοίμασε το owned snapshot στο δοσμένο rd-cl SourceCommit, ακόμη αν το
   remote branch προχώρησε. Ενημέρωσε ownership marker μόνο μετά την επαλήθευση
   του πραγματικού snapshot HEAD και των περιεχομένων του. Μετά συνέχισε όλα τα
   ακόλουθα στάδια χωρίς νέο prompt όταν περνούν οι προϋποθέσεις.

2. Εντόπισε το πραγματικό Desktop/artifact root, το owned snapshot και τα τοπικά
   toolchain JSON/receipts από υπάρχοντα Reports, Tools, Scratch και metadata.
   Αν λείπει config ή snapshot, προετοίμασέ το από επαληθευμένα τοπικά εργαλεία
   και τα ακριβή published source objects, όπως ορίζει η διαδικασία. Πλέον
   επιτρέπεται να κατεβάσεις όσα pinned inputs λείπουν από επίσημες/έμπιστες
   πηγές, χωρίς νέα εξαίρεση. Κατέγραψε προέλευση/έκδοση/hashes και επαλήθευσέ τα
   πριν το build. Μην αλλάξεις dependency versions, lockfiles ή working toolchains.
   Αν ζητείται ρητά offline/no-download εργασία, χρησιμοποίησε μόνο τοπικά inputs.
   Μην επινοήσεις διαδρομές ή δημιουργήσεις εικονικά caches. Συγκέντρωσε όλα τα
   πραγματικά missing inputs και προετοίμασε τα απαιτούμενα πριν επιστρέψεις
   BLOCKED για όσα παραμένουν unavailable/unverifiable· μην ζητάς διαδοχικά
   διαδρομές που μπορείς να εντοπίσεις ή να προετοιμάσεις τοπικά.
   Κατέγραψε τις επαληθευμένες διαδρομές στις $snapshot και $toolchain,
   και το υπάρχον config.paths.python στην $python. Όρισε επίσης
   $sourceCommit στο ακριβές full SHA που δόθηκε στην αρχή του prompt.
   Το γνωστό artifact root από την τελευταία παράδοση είναι:
   C:\Users\Support-2\Desktop\Office-Workspace-Artifacts
   Το γνωστό υπάρχον toolchain είναι:
   C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.0+72\delivery-s2-d029c35d\toolchain-codecs-d029c35d-local.json
   Επαλήθευσε αυτά τα δεδομένα στο μηχάνημα· μην μαντέψεις άλλον root.

Πριν ορίσεις application CARGO_TARGET_DIR, έλεγξε τον τελευταίο επιτυχή
   target και τη συμβατή Flutter cache. Μην δημιουργήσεις cold target ανά SHA
   χωρίς πραγματική ασυμβατότητα/ambiguity. Κράτησε ξεχωριστά snapshot/delivery,
   όλους τους guards/locks και τα κανονικά compile/test/package invocations.
   Κατέγραψε αιτία κάθε αναγκαστικού cold rebuild και χρόνους ανά στάδιο.

3. Επιβεβαίωσε όλα τα pinned τοπικά prerequisites, SDK, CMake/compiler, Python
   Brotli, Flutter/Rust/FRB/LLVM, engine archive και caches. Χρησιμοποίησε canonical
   υπάρχουσες απόλυτες TEMP/TMP διαδρομές μόνο στο τρέχον process και το ίδιο
   reviewed drive_alias. Χρησιμοποίησε το υπάρχον RDCL_TEST_CMAKE:
   C:\Program Files\CMake\bin\cmake.exe, αφού επιβεβαιώσεις την πραγματική διαδρομή.
   Καμία αλλαγή καθολικών ρυθμίσεων, tests ή guards.

4. Εντόπισε το υπάρχον S2 toolchain-codecs-local.json και compiled-cache receipt.
   Επαλήθευσε πραγματικό receipt hash, cl/link/lib/CMake/vcpkg.exe, sdk_identity,
   SDK-pinned triplet και codec ABI/libraries,
   overlays και installed-only plan με τον υπάρχοντα verifier. Αν είναι συμβατά,
   επαναχρησιμοποίησε τον verified codec root. Μην ξαναχτίσεις codecs απλώς επειδή
   άλλαξε το application SHA. Μην χρησιμοποιήσεις receipt S1 ή θεωρήσεις το codec
   PASS ως πλήρες application build/warm cache. Το γνωστό genuine receipt έχει
   SHA-256 3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97.
   Αυτό είναι ιστορικό receipt χωρίς SDK identity: επαλήθευσε ότι παραμένει
   αμετάβλητο, μην το επανεκδώσεις/συμπληρώσεις και μην το χρησιμοποιήσεις ως νέο
   compile proof. Αν δεν υπάρχει νεότερο genuine receipt συμβατό με το νέο guard,
   απαιτείται το ακόλουθο νέο isolated bootstrap. Κατέγραψε χωριστά το νέο hash.

5. Μόνο αν απαιτείται πραγματικά νέο codec bootstrap και υπάρχουν όλα τα pinned
   τοπικά inputs, εκτέλεσε τα δημοσιευμένα bootstrap tests με RDCL_TEST_CMAKE,
   Preflight και Compile. Χρησιμοποίησε νέο κατάλληλα owned root σύμφωνα με τους
   source/phase guards, διατηρώντας τους παλιούς. Η διαδικασία προετοιμάζει πρώτα
   vcpkg-cmake, μετά get-vars/Meson. Το ακριβές κενό detect_compiler package dir
   είναι αναμενόμενο probe state· δεν το διαγράφεις και δεν χαλαρώνεις guards.
   Receipt παράγεται μόνο από πραγματικό compilation/ABI/tool evidence. Συνέχισε
   με το παραγόμενο toolchain JSON, όχι με αντιγραμμένο ή χειροποίητο receipt.
   Όρισε από τα επαληθευμένα metadata $bootstrapOutput και $codecRoot σε νέα,
   unused owned paths κάτω από το πραγματικό artifact root (π.χ. με short SHA),
   και $existingTriplet στο υπάρχον original/legacy triplet που θα διατηρηθεί.
   Μην χρησιμοποιήσεις το παλιό codec-bootstrap-s2 output που έχει ήδη receipt.
   Με το ίδιο verified snapshot/source/toolchain/drive_alias εκτέλεσε:
   & (Join-Path $snapshot 'scripts\windows-codec-bootstrap.ps1') `
     -Mode Preflight -Toolchain $toolchain -SourceCommit $sourceCommit `
     -OutputRoot $bootstrapOutput -CodecRoot $codecRoot -ExistingTriplet $existingTriplet
   & (Join-Path $snapshot 'scripts\windows-codec-bootstrap.ps1') `
     -Mode Compile -Toolchain $toolchain -SourceCommit $sourceCommit `
     -OutputRoot $bootstrapOutput -CodecRoot $codecRoot -ExistingTriplet $existingTriplet
   Μετά πραγματικό PASS, όρισε $toolchain στο νέο παραγόμενο
   toolchain-codecs-local.json και κατέγραψε/επαλήθευσε το νέο receipt SHA256.
   Αν δεν περνά κάποιο στάδιο, σταμάτα τα εξαρτώμενα βήματα και κράτησε diagnostics.

Πριν από το ακριβό native compilation, εκτέλεσε τον pinned analyzer για τα
   αλλαγμένα αρχεία και tests, μόλις επαληθευτούν package/generated prerequisites
   του νέου owned snapshot. Κράτησε πλήρη command/exit code/diagnostics.
   Αν τα reviewed εργαλεία δεν επιτρέπουν αυτή τη σειρά, ανέφερε τον ακριβή
   περιορισμό· μην τροποποιήσεις tooling/source/guards στον S2. Μην αγνοήσεις
   WARNING/ERROR ή αλλάξεις severity/fatality flags. Τα INFO διατηρούνται στην
   αναφορά και αξιολογούνται με την υπάρχουσα πολιτική του analyzer.

6. Επίλεξε OutputRoot κάτω από το πραγματικό Desktop:
   Office-Workspace-Artifacts\Builds\rd-cl\<version>\delivery-s2-<short-source-sha>
   ή άλλο επαληθευμένο unused owned delivery path. Το delivery-s2 της έκδοσης
   1.4.13+71 περιέχει ήδη το verified EXE του baseline και πρέπει να διατηρηθεί.
   Εκτύπωσε την πλήρη απόλυτη διαδρομή πριν το build, ως planned destination.
   Μην αντικαταστήσεις προηγούμενο verified πακέτο. Με ακριβώς το ίδιο snapshot,
   SourceCommit, toolchain και drive_alias, κατέγραψε τον επιλεγμένο απόλυτο
   OutputRoot στην $delivery και το ακριβές full SHA στην $sourceCommit.
   Από το $snapshot με $ErrorActionPreference = 'Stop', εκτέλεσε:
   $env:PYTHONDONTWRITEBYTECODE = '1'
   & $python -m unittest discover -s scripts/tests -p 'test_windows*.py' -v
   if ($LASTEXITCODE -ne 0) { throw 'Guard tests failed' }
   & (Join-Path $snapshot 'scripts\windows-native-build.ps1') `
     -Mode Preflight -Toolchain $toolchain `
     -SourceCommit $sourceCommit -OutputRoot $delivery
   & (Join-Path $snapshot 'scripts\windows-native-release.ps1') `
     -Mode Build -WithExe -Toolchain $toolchain `
     -SourceCommit $sourceCommit -OutputRoot $delivery
   Συμπλήρωσε τις παραμέτρους από τα παραπάνω verified δεδομένα. Μη σταματήσεις
   στο codec PASS: ο στόχος περιλαμβάνει native application build και EXE packaging.
   Όλοι οι exit codes, tests, space guards και offline checks παραμένουν ενεργοί.
   Έλεγξε το native-vcpkg-root.json και τα native logs: μετά το VsDevCmd ο
   VCPKG_ROOT πρέπει να δείχνει στο ίδιο verified paths.vcpkg, μέσω του ίδιου alias.
   Μην διορθώσεις χειροκίνητα environment/source και μην καθαρίσεις Cargo targets.
   Χρησιμοποίησε μία release invocation Build -WithExe: το lock μένει ενεργό
   μέχρι να τελειώσει το packaging. Μην τρέξεις παράλληλα ξεχωριστό PackageExe
   και μην διαγράψεις lock που αναφέρει busy/stale/changed owner.

7. Επαλήθευσε version/source/target, runtime ZIP και πραγματικό Windows x64 EXE,
   EXE-INFO.json, BUILD-INFO.json και SHA256SUMS. Κάνε το υποχρεωτικό Office
   office-release-maintenance plan/apply/verify πριν από παράδοση. Διατήρησε
   προηγούμενο verified πακέτο, source, codecs, caches και dirty εργασία.
   Επαλήθευσε embedded runtime integrity και κράτησε SHA256SUMS, manifests,
   BUILD-STATUS.md και ελληνικό INSTALLATION-EL.md δίπλα στο νέο EXE.
   Cleanup μόνο με την προβλεπόμενη ελεγμένη/εξουσιοδοτημένη διαδικασία.
   Επαλήθευσε τα πέντε canonical icon hashes του docs/windows-branding.md και
   την επιλογή resources για tray/runner/installer. Αν διαφέρουν, ανέφερε τη
   διαφορά χωρίς τοπική διόρθωση source ή ισχυρισμό branding PASS.
   Επαλήθευσε και το native-core-identity.json: έκδοση και DLL hash πρέπει να
   συμφωνούν με το Cargo output και το runtime manifest.
   Packaging PASS δεν σημαίνει installation/runtime PASS. Αν η οθόνη δείχνει
   άλλη έκδοση (π.χ. 1.4.11), κράτησε installer SHA και loaded librustdesk.dll
   path/hash για σύγκριση με το payload manifest· ακολούθησε το diagnostic
   section του docs/windows-s2-build-integrity.md, χωρίς αυθαίρετο reinstall.

8. Πρόσθετο υποχρεωτικό στάδιο για αλλαγμένο rd-cl: ακολούθησε το δημοσιευμένο
   Office docs/rdcl-installer-hosting.md. Αφού περάσουν native acceptance και
   maintenance, χρησιμοποίησε την υπάρχουσα επαληθευμένη πρόσβαση στον server
   και τον συγκεκριμένο publisher για νέα λήψη HTTPS/αποτύπωμα, ατομικό current
   και αφαίρεση μόνο του προηγούμενου EXE. Στον server μένει μόνο η τελευταία
   έκδοση· τα rollback packages/caches διατηρούνται στον S2. Μην εγκαταστήσεις
   προϊόν στον S2 host ή πελάτη ως μέρος build. Native acceptance γίνεται μόνο
   σε εξουσιοδοτημένο αναλώσιμο Windows περιβάλλον με συνθετικές ταυτότητες.
   Έλλειψη αυτού ή πρόσβασης/mounts/rollout σημαίνει σαφές pending/BLOCKED για
   hosting, όχι ψευδές PASS ή αυθαίρετο deploy/restart/SQL.

9. Παράδωσε ενιαία αναφορά: στάδια tests/preflight/codecs/application/EXE/artifact
   gate χωριστά, πραγματικές εντολές/log paths, source SHA και έκδοση. Αν το EXE
   υπάρχει και επαληθεύτηκε, ανέφερε υποχρεωτικά τον ακριβή απόλυτο κατάλογό του
   στο Desktop του S2, το πλήρες filename/path, μέγεθος και SHA-256. Πάρε τα από
   το πραγματικό OutputRoot/EXE-INFO.json και επιβεβαίωσε το αρχείο. Αν δεν έχει
   παραχθεί, πες NOT_PRODUCED και δήλωσε μόνο την planned διαδρομή ως τέτοια.

Χωρίς upgrades, source/authentication αλλαγές,
commit/push στον S2, bypass guards, εγκατάσταση προϊόντος στον S2 host/πελάτες, signing,
GitHub Release, Actions, Dokploy deployment ή πραγματική συνεδρία πελάτη.
Εξαίρεση μόνο η εγκεκριμένη διάθεση installer στον συγκεκριμένο server/volume
και η απομονωμένη native acceptance του παραπάνω σταδίου· χωρίς SQL/restart.
Η άδεια λήψεων αφορά απαιτούμενα build inputs, όχι παράκαμψη offline guards,
αυτόματο upgrade ή κατασκευή receipt από downloaded/precompiled αποτελέσματα.
Runtime/installation acceptance παραμένει ξεχωριστό στάδιο με πραγματική απόδειξη
απομονωμένου Windows ελέγχου· χωρίς τέτοιο περιβάλλον δηλώνεται NOT_RUN. Σε πραγματική αποτυχία σταμάτα τα
εξαρτώμενα βήματα, διατήρησε diagnostics και επέστρεψε ένα συγκεντρωτικό BLOCKED.
```

The template's variables are filled from current source by the sender or resolved
from actual S2 metadata by the recipient, not guessed. The EXE's current naming
rule is `rd-cl-<profile.version>-windows-x64-install.exe` directly under OutputRoot;
verify it against the current packager and actual EXE-INFO.json each time. The
codec bootstrap output directory is not the application EXE delivery directory.
Keep build handoff, migration prompt and manual Dokploy rollout instructions separate.
