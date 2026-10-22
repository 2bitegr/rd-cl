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

## Current completed application/EXE baseline

Latest S2 completion, reported by the user on 2026-10-21; Windows artifact bytes
were not independently accessed from this coordinator. Use this completed build
as the comparison baseline, not the earlier codec-only result or blocked attempts.

- Source/tooling: `ad46faef58b5773fc662f021c00ed2f92a9c675a`, published branch
  `codex/s2-codec-bootstrap-1.4.13`.
- Version/target: `1.4.13+71`, Windows x64, unsigned EXE installer; no MSI.
- EXE directory:
  `C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\1.4.13+71\delivery-s2`.
- Filename: `rd-cl-1.4.13+71-windows-x64-install.exe`; size: `23875584` bytes.
- SHA-256: `0586a21a7c3df107475722b07bcb6536be80fbcff19f9659672a7ddae6a8b66b`.
- Reported PASS: 53 guard tests, 50 Dart tests, Preflight, Git object/ABI/exact
  installed-only checks, Rust/Flutter build, EXE packaging, integrity of 91 embedded
  runtime files and release-maintenance gate. Genuine codec receipt unchanged.
- Sibling evidence: `SHA256SUMS`, manifests, `BUILD-STATUS.md`, `INSTALLATION-EL.md`.
- User-reported installation/upgrade acceptance on 2026-10-22: **FAIL** — the
  screen still showed core1.4.11, service stopped, no error dialog and a broken
  Desktop shortcut. Actual loaded DLL path/hash and installer bytes on that PC
  remain unverified. Retain historical packaging PASS separately from this failure.
- Current unpublished source targets2.0.0+72 with installer corrections; see
  [Windows installer correction](windows-installer-2.0.0.md). Do not issue its
  build prompt until the exact source/tooling commit is published and verified.

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
Προετοίμασε τα απαιτούμενα pinned inputs και εκτέλεσε το πλήρες build/package
του rd-cl στον native Windows S2. Επιτρέπονται οι αναγκαίες λήψεις κατά την
προετοιμασία, με TLS, signatures/checksums και ακριβή lockfile/Git/version pins.
Τα υπάρχοντα guarded build/codec scripts παραμένουν offline/frozen.

Office publication: <verified Office repository/ref/full SHA>
rd-cl repository/ref: <verified repository and published ref>
Ακριβές rd-cl SourceCommit: <full published SHA>
Version: <manifest/profile version including Flutter build number>
Target: Windows x64, EXE installer και το υπάρχον verified runtime ZIP.
Προηγούμενο completed application/EXE baseline: ad46faef58b5773fc662f021c00ed2f92a9c675a
Baseline version: 1.4.13+71
Baseline EXE SHA-256: 0586a21a7c3df107475722b07bcb6536be80fbcff19f9659672a7ddae6a8b66b
(Ο αποστολέας ενημερώνει αυτά τα baseline πεδία από την τελευταία completed αναφορά.)
Αλλαγές rd-cl: <verified comparison and changed source/build-input paths>
Προγραμματισμένος κατάλογος EXE: <verified S2 Desktop OutputRoot, or discover as below>

Διάβασε τα AGENTS.md και docs/windows-native-build.md,
docs/windows-s2-codec-bootstrap.md και docs/windows-s2-build-integrity.md.
Το παλιό receipt χωρίς sdk_identity δεν μπορεί να χρησιμοποιηθεί με το νέο
tooling. Διατήρησέ το και ακολούθησε το βήμα5 για πραγματικό νέο compilation.
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
   C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\1.4.13+71\codec-bootstrap-s2\toolchain-codecs-local.json
   Επαλήθευσε αυτά τα δεδομένα στο μηχάνημα· μην μαντέψεις άλλον root.

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
   Επαλήθευσε και το native-core-identity.json: έκδοση και DLL hash πρέπει να
   συμφωνούν με το Cargo output και το runtime manifest.
   Packaging PASS δεν σημαίνει installation/runtime PASS. Αν η οθόνη δείχνει
   άλλη έκδοση (π.χ. 1.4.11), κράτησε installer SHA και loaded librustdesk.dll
   path/hash για σύγκριση με το payload manifest· ακολούθησε το diagnostic
   section του docs/windows-s2-build-integrity.md, χωρίς αυθαίρετο reinstall.

8. Παράδωσε ενιαία αναφορά: στάδια tests/preflight/codecs/application/EXE/artifact
   gate χωριστά, πραγματικές εντολές/log paths, source SHA και έκδοση. Αν το EXE
   υπάρχει και επαληθεύτηκε, ανέφερε υποχρεωτικά τον ακριβή απόλυτο κατάλογό του
   στο Desktop του S2, το πλήρες filename/path, μέγεθος και SHA-256. Πάρε τα από
   το πραγματικό OutputRoot/EXE-INFO.json και επιβεβαίωσε το αρχείο. Αν δεν έχει
   παραχθεί, πες NOT_PRODUCED και δήλωσε μόνο την planned διαδρομή ως τέτοια.

Χωρίς upgrades, source/authentication αλλαγές,
commit/push στον S2, bypass guards, εγκατάσταση/εκτέλεση προϊόντος, signing,
GitHub Release, Actions, Dokploy deployment ή σύνδεση στην παραγωγή.
Η άδεια λήψεων αφορά απαιτούμενα build inputs, όχι παράκαμψη offline guards,
αυτόματο upgrade ή κατασκευή receipt από downloaded/precompiled αποτελέσματα.
Runtime/installation acceptance είναι ξεχωριστό στάδιο και παραμένει NOT_RUN
μέχρι να εκτελεστεί με δική του εξουσιοδότηση. Σε πραγματική αποτυχία σταμάτα τα
εξαρτώμενα βήματα, διατήρησε diagnostics και επέστρεψε ένα συγκεντρωτικό BLOCKED.
```

The template's variables are filled from current source by the sender or resolved
from actual S2 metadata by the recipient, not guessed. The EXE's current naming
rule is `rd-cl-<profile.version>-windows-x64-install.exe` directly under OutputRoot;
verify it against the current packager and actual EXE-INFO.json each time. The
codec bootstrap output directory is not the application EXE delivery directory.
Keep build handoff, migration prompt and manual Dokploy rollout instructions separate.
