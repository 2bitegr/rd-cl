# One complete rd-cl build prompt for S2

## Current source candidate — 3.1.5

S1 is preparing a correction for a pilot NAS running 3.1.4. Its inherited
TrustedInstaller FullControl rule on the installation directory was rejected
before the first updater poll. The corrected installation guard accepts the
exact Windows TrustedInstaller service SID, with synthetic tests retaining
rejection of Everyone, Users and unrelated service writers. Private updater-root
ownership and permissions remain strict.

Startup failures after verifying the private updater root now produce bounded,
sanitized update.jsonl codes, including failures before the normal poll loop.
Recovery setup preserves a sanitized underlying cause before its summary failure.
The new native fixture covers 41 recovery/security scenarios. Full publication
checks and the final published source SHA belong in the completed handoff.

Last completed package and hosting are rd-cl 3.1.4,
f66ed92801f5bea6f2de956c8e605b8c6217e422, EXE 24551424 bytes,
SHA-256 1430fa8c57d95a410769c819e8f842c37980bce006700d4fb414ac3e6bd95dfa.
User-forwarded S2 transfer/maintenance/hosting PASS was independently checked
through public Web/API by S1 on 2026-11-21. Native clean-install/upgrade/enrollment
remain NOT_RUN. Existing guest codec receipts and warm application caches need
fresh compatibility verification before reuse for 3.1.5.
No 3.1.5 EXE has been produced. S2's work ends at verified EXE transfer.

## S2 build station

S2 coordinates from Ubuntu **Exantas-S2** and builds inside **Windows11-Development**
(UUID 8c15378e-e71b-4c78-bf41-e77ba3915205, Windows hostname **DESKTOP-5OTBBT7**).
Verify both identities at the start of each handoff. Inspect the actual
UbuntuTransfer mapping with `VBoxManage showvminfo <uuid> --machinereadable`.
Start the VM manually from the Ubuntu user's normal session if the automation
executor cannot start VirtualBox. Run the native commands in the guest console
or with already authorized Guest Control. Keep credentials out of transfer
files and command logs. If using SSH to reach Ubuntu, use the verified host
identity and already authorized access to build work and the transfer directory.

Resolve the guest Desktop using the Windows Known Folder API. Store the owned
source snapshot, toolchain, short TEMP/TMP, Cargo/Flutter/vcpkg caches, and
OutputRoot on guest-local NTFS. Use a new owned snapshot and delivery root per
published commit. Reuse compatible verified tools and warm build caches. Budget
guest NTFS and Ubuntu storage separately, including temporary build and transfer
space. Reserve UbuntuTransfer for input handoff, verified packages and reports.

Provision the pinned C++ tools and Windows SDK10.0.22621.0 before codec
bootstrap. Record the selected installation from vswhere, x64 tool paths from
VsDevCmd, and tool versions and hashes. Keep provisioning and offline builds
separate. When a tool or an ABI changes, reverify existing receipts before reuse.
If the guest lacks a verified codec cache, run the separate offline codec
bootstrap in a new guest-local root. Run native guards, Dart tests and analyzer
before the one application build and packaging invocation. Report host identity,
toolchain, codecs, application, EXE verification, maintenance and transfer
as separate gates.

After package and maintenance PASS, transfer the EXE, runtime ZIP, manifests and
reports through UbuntuTransfer. Verify Windows-generated SHA-256 inventories
independently in Ubuntu. This transfer completes the S2 handoff. Keep the last
verified package and reusable caches for the next delivery. Production hosting,
Office migrations, Dokploy and install/upgrade acceptance belong to separately
authorized work outside S2. This scope supersedes historical S2 assignments below.

## Latest S2 attempt BLOCKED — 3.1.3/2e8babad, 2026-11-18

User-forwarded native S2 receipt: source recovery and the 79 profile pins passed;
guards 91 PASS/2 SKIP (Linux-only and synthetic symlink privilege), updater
7 envelope cases/38 recovery checks, analyzer zero diagnostics, Dart137 PASS,
and virtual-display compilation PASS. One Build-WithExe invocation stopped at
Cargo101/E0382 in update_me: exe was moved into the restore callback before
formatting the updater-enable command. Flutter release/ZIP/EXE were NOT_RUN;
maintenance and hosting did not execute. Completed delivery remains3.1.2.

S1 moves the pure command formatting before the move capture without cloning or
changing the command, target path, checked execution or restore guard. The new
metadata-only native regression compiles the actual command/callback region and
actual guard with inert helper signatures: the original fails E0382, the fix
passes with Rust1.75. No product, installer, callback or service is executed.
The final handoff must supply the NEW published rd-cl SHA; do not replay2e8babad.

S2 genuinely rebuilt codecs and produced compiled-cache-receipt.json under
Builds/rd-cl/3.1.3/codec-bootstrap-s2-2e8babad, SHA256
32cdda39d3b73e8c16988c4eb46e1df9571ea260171dfb2fb82ce7ba25e077a6.
Its sibling toolchain-codecs-local.json selects the new receipt. Reverify its
actual SDK10.0.22621/tool/triplet/424ABI-file/16-port evidence for reuse; this
application-only correction does not require another codec bootstrap. Preserve
all failed outputs, that receipt/root and C:\Build\rd-cl\a23ec301\target.
An old hwcodec build-script output still references the old codec root; final
link provenance was NOT established before failure. Inspect selected native
search/link inputs; use a new isolated application target only if their provenance
cannot be verified, without purging or modifying the existing cache/receipt.

S2 retained the recovered3.1.2 installer with its known hash; original ZIP and
BUILD-INFO remain historical MISSING. Use a new truthful maintenance config with
the real recovered installer/new package/receipt and cleanup:[], not absent old
required paths. Migration20261116000100 already has user-forwarded APPLIED /
MIGRATION_GATE_PASS; no replay or new SQL audit. All S2 facts here are reported
evidence, not independent S1 inspection of its filesystem or database.


## Previous S2 attempt BLOCKED —3.1.3/da4256e5,2026-11-17

Cargo exit101: incorrect WinAPI sddl import and4unsupported crypto error
conversions. No EXE/ZIP/package, maintenance or hosting. Guards90PASS, updater38,
Dart137PASS and analyzer0/0/0 are retained, not application acceptance. Preserve
this failed snapshot/output/receipts and existing C:\Build\rd-cl\a23ec301\target.
Last completed build/hosting remains3.1.2/babdbfc0; not a new3.1.3 delivery.

S1 local fixes and real native regression probe are prepared. Wait for NEW full
published Office/rd-cl SHAs; never replay da4256e5 as a corrected target. Use a
new owned snapshot/output for the corrected SHA, compatible verified codec/cache
reuse and one normal Build-to-EXE invocation. No new codec/dependency/SDK change.
The optional native contract probe accepts RDCL_TEST_RUSTC and
RDCL_TEST_NATIVE_DEPS pointing at real pinned Rust1.75/compiled release deps;
it compiles actual production function bodies and executes disposable envelope
cases only, never the product barrier. Full native application compile is still
mandatory. Original S2 migration was0attempts/BLOCKED by sequence default UPDATE;
its separate corrected published SQL/hash handoff must enforce fresh ledger checks.


## Current source candidate —3.1.3 / Office1.12.60,2026-11-17

The reviewed sequential silent-update implementation is ready for coordinated S1
publication; the final user-forwarded prompt supplies both full published SHAs.
This heading is not a completed build receipt. No new EXE exists yet. Preserve the
completed3.1.2/babdbfc0 delivery below and its source/cache/rollback provenance.

Build the changed3.1.3 source through one normal `Build -WithExe` invocation,
including the new update-registration Dart case and Windows synthetic updater
fixtures. Compatible verified codecs and warm application targets should be
reused; application-only changes do not justify codec bootstrap. Full native
compilation/package checks remain mandatory. Publish the common interactive EXE
through the same reviewed Office publisher and volume/retention guard, with native
acceptance honestly NOT_RUN. No signed silent-release envelope is supplied by
this build job; never fabricate clean-install/upgrade PASS, request a private key
or unlock a production key on S2. Native installation and pilot acceptance, live
SQL/configuration, feature activation and Dokploy deployment stay separate.


## Current completed delivery —3.1.2,2026-11-16

Current completed S2 application/EXE and hosting baseline (user-forwarded
receipt2026-11-16; native Windows logs/package not independently inspected by S1):
`babdbfc0dad64f6725ba938222c7b70503ed2b31`, rd-cl `3.1.2`, Windows x64, NotSigned.
Office handoff: `bc7f82801fd962200e86bc66aebcb77dd1bedd97` (1.12.59).
Directory: `C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\3.1.2\delivery-s2-babdbfc0`.
EXE: `rd-cl-3.1.2-windows-x64-install.exe`, 24497152 bytes.
SHA256: `7251af67957c5c064ce9c095ddd079aa6f74ec7a37972eeea6a38050645d02d5`.
Runtime ZIP SHA256: `f32ca8b028bcf17ed58647c3b2d55107b289b2b2a9bebf99a4204e097de491c8`.
Public URL: `https://office.exantas.eu/downloads/rd-cl/rd-cl-3.1.2-7251af67957c-windows-x64-install.exe`.
S2 reports exact-source sync/snapshot, verified codec/toolchain/cache reuse without
bootstrap, 89 executed guard PASS + 1 REUSED_VERIFIED + 1 Linux-only NOT_RUN,
analyzer0errors/0warnings/4INFO,130 Dart PASS and one Build-to-EXE1060.234s PASS.
EXE/ZIP/PE/icons/inventories, maintenance plan/apply/verify (zero removals) and
hosting/HTTPS/retirement/staging cleanup PASS. Only the previous manifest-owned
3.1.1 server EXE was retired; one current server EXE, rollback packages/caches
retained on S2. These native/server details are user-reported, not S1 re-execution.
S1 independently streamed both immutable Web and common API downloads: HTTP200,
normal TLS, exact size/SHA256 and MZ header PASS; no binary saved or executed.
Native installation/upgrade/customer acceptance remains NOT_RUN; no SQL, flags,
activation or service deployment/restart in this delivery. The live customer
mapping/ticket403 is not proven fixed by build/hosting. Detailed S2 commands,
exits/timings/inputs are in BUILD-STATUS.md and stage-summary.json beside the EXE.
Do not rebuild unchanged babdbfc0 source or reissue its completed S2 handoff.
Previous3.1.0/earlier receipts stay historical. This receipt supplies no newer
individual toolchain/codec hash or free-space measurement; discover actual state
on S2 when required, without inventing it. Tracking-doc updates alone do not
request another build. See docs/rdcl-3.1.2-delivery.md in Office.

The requested3.1.2 section below is now historical: the user returned DELIVERY_PASS.
Do not replay it or the old3.1.1 handoff. For unchanged runtime/build inputs,
NO_RDCL_BUILD_NEEDED; installation/acceptance remains a separate manual step.

## Historical requested target —3.1.2 publication2026-11-16

Company/computer presentation and its tests are coordinated with Office1.12.59
customer directory/group search. Source/runtime test bindings are retained;
normal core/packer/Flutter/profile versions and exact input hashes are updated.
No codec/dependency/SDK/ABI/icon change. Use the coordinator's newly published
full Office/rd-cl SHAs, a separate owned3.1.2 snapshot/output, and compatible
verified receipts/warm Cargo/Flutter caches. Preserve the outstanding3.1.1
receipts/active resources; do not assume completion from an installed screenshot.
Read actual S2 state before proceeding and do not run parallel release sessions.
The known completed3.1.0 baseline below remains historical evidence. New build,
maintenance and latest-only hosting must pass before delivery; installation and
deploy are not authorized. The later dated3.1.1 source-preparation section is
historical and is not an instruction to build that superseded source.


2026-11-14 source preparation: clean3.1.1 reduces ticket video selection/help to
50,000,000bytes, matching local Office1.12.53 and a forward DB constraint. The
global Storage limit stays52,428,800bytes. Do not execute a replacement build
from the previous SHAs. Use the coordinator's verified full published Office/rd-cl
SHAs and one complete S2 prompt for this correction. Preserve
the completed3.1.0 baseline below; use a new owned snapshot/output and compatible
verified caches/codec receipt. Application-only limit/version changes do not
require codec bootstrap. Hosting, migrations/storage, activation and real native
installation/acceptance remain separate stages.

## Previous completed delivery —3.1.0, build/EXE/maintenance/hosting PASS (2026-11-13)

Current completed S2 application/EXE and hosting baseline (user-forwarded
receipt2026-11-13; native Windows package/report not independently inspected by S1):
`1d76e7d176637bf74962a7061d77395def3082bc`, rd-cl `3.1.0`, Windows x64, NotSigned.
Office handoff source: `d7330fc05cd197573cc522e4f50a822b0e2886d0` (1.12.52).
Directory: `C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\3.1.0\delivery-s2-1d76e7d1`.
EXE: `rd-cl-3.1.0-windows-x64-install.exe`, 24499200 bytes.
SHA256: `7be3409f23788d5422b02add17fbe966e738c1b451955a52591b9f9b1336d541`.
Public installer: `https://office.exantas.eu/downloads/rd-cl/rd-cl-3.1.0-7be3409f2378-windows-x64-install.exe`.
Build/EXE, maintenance and hosting PASS are user-reported; no repeated build for
hosting. S1 independently streamed the public HTTPS bytes with normal TLS
verification: exact size/SHA256 and MZ header PASS, without saving/executing EXE.
Native installation/customer acceptance remains NOT_RUN. S2 retains previous
3.0.0 and reusable caches. Detailed S2 checks/timings/commands/hosting receipts:
`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Reports\2026-11-13\rd-cl-1d76e7d1\BUILD-STATUS.md`.
No new exact test counts, free-space/compression results or server retirement
receipts were supplied in this summary; do not invent those details. This
supersedes the blocked 0cd3c648 teardown and 1d76e7d1 space-only attempts as the
current delivery state. Preserve their historical evidence. Do not rebuild this
unchanged completed source; installation, migrations/storage/flags, manual
deployment and real customer acceptance remain separate, unproven by this receipt.

The dated preparation and older baseline sections below are historical. They do
not request a new build of the already completed current source.

## Historical Caller Popup native readiness fix —candidate2.0.3+75 (2026-10-28)

User reports:Office was already signed in and showing native readiness. The SAME
peer connects from the main rd-cl screen,but Caller Popup launch receives server
"Connection failed, please login!". Verified source gap:handleUriLink launched the
remote window directly,while manual connectMainDesktop first runs the existing
ensureNativeReady flow. Route network desktop URIs through that SAME gateway;
preserve officeTicket,switchUuid,password and relay. Protected Office tickets also
require actual current companion/native readiness;legacy manual login behavior
and local recording playback remain separate. No copying Office tokens into the
legacy access_token,no server MUST_LOGIN/JWT change or new issuer/permission.

Candidate source requires coordinator publication before the S2 build. New Windows
rd-cl2.0.3+75 is required;installed2.0.2+74 cannot acquire a Dart change from an Office
deploy. Reuse verified codecs/SDK/warm app caches;no bootstrap/dependency/FFI change.
Do not rebuild completed680628f2 or issue an executable S2 prompt with an invented
new SHA. After publication include the full build+latest-only hosting phase with
Office's exact-volume/single-old-EXE deletion guard. Keep current2.0.2 hosted until
new bytes pass. Compilation/source guards are not proof this live issue is solved.

Acceptance after new build:Caller Popup cold/warm launch and idle/expired lease
must complete native preflight before a remote window opens;explicit confirmation
or API/lease failure opens no connection and does not replay issuance. Verify the
opaque ticket still scopes the actual call/work/session and flags are preserved.
Also test ordinary manual connection,legacy native account and local recording
playback. Main/remote DLL paths/hashes must match the delivery;do not install on
S2 host/customer PCs as an automatic build step. Actual Windows/DPAPI/runtime
acceptance remains NOT_RUN until real evidence. Manual main-window connection is
the current working workaround;no customer re-enrollment or logout is required.


## Historical completed build —2.0.2+74 (2026-10-28)

Historical completed S2 application/EXE baseline (user-forwarded receipt2026-10-28;
not independently inspected on Windows here):
`680628f2b9e798ef63e6d29c73954807d9012e12`,rd-cl `2.0.2+74`,Windows x64,UNSIGNED.
Directory:`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.2+74\delivery-s2-680628f2`.
EXE:`rd-cl-2.0.2+74-windows-x64-install.exe`,24343040bytes.
SHA256:`d4843ebf32759b78f2663247d6fd72cb4ba7a2ce2229c9f59131186a4fa292a1`.
Codec/cache reuse without bootstrap,guards90PASS/1SKIP,analyzer0ERROR/0WARNING/30INFO,
Dart86PASS,native/EXE/ZIP/integrity125checksums/maintenance PASS;release23m04s.
Native installation/enrollment acceptance remains NOT_RUN. User-forwarded S2
PUBLISH-COMPLETED receipt confirms hosting PUBLISHED:exact24343040bytes/hash verified
via HTTPS from DEV/S2,one server EXE,transfer staging cleaned/verified. No repeated
build or deploy/restart in that publication. Exact public URL was not included in
the forwarded report;do not invent a verified URL. Do NOT rebuild unchanged source.
The additional volume/deletion guard is delivered by the coordinated Office1.12.19
source change;it is not claimed as executed proof for the prior publication.
Preserve prior4c678792 package/caches and useful failed evidence. No runtime,
signing or hosting success is inferred from build PASS.

The following implementation/build description applies to future changed source;
for unchanged680628f2 reuse its completed package and continue publication only.

### Automatic installation implementation

New source spans Office1.12.18 and rd-cl2.0.2+74. The card COPIES a device-scoped
installation link for the customer browser;successful interactive Windows install
passes the capability to native automatic enrollment and same-grant completion
ACK. Common latest download is also available. One PC can have multiple contacts
and callers;changes of caller do not change the managed identity. See published
Office docs/rdcl-automatic-enrollment.md and current rdcl-installer-hosting.md.
New pure Rust filename/parser and automatic Flutter cases are mandatory existing
runner tests. No dependencies/codecs/SDK/icons or session protocol pins change.
Future reviewed source requires exact publication before S2;no invented future SHA.
The previous4c6787922.0.1+73 package is retained for rollback,not rebuilt or copied
as proof of this new feature. Reuse its genuine codec receipt and warm caches.

The user has no disposable Windows environment. Successful build/package/integrity/
maintenance may be uploaded through verified SSH with explicit native NOT_RUN;
this supersedes the older mandatory acceptance-PASS/VM hosting block below.
Do not manufacture PASS or hide FAIL. Source/bytes/PE/HTTPS/atomic latest-only and
maintenance gates remain. S2 reports native runtime separately and never installs
on host/customer PCs or deploys/restarts Office as part of building. The user
manually rolls out Office1.12.18 with existing shared installer volume/config.
No migration/replay. Always include the scoped hosting phase in the one prompt.


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
hashes/reports, reviewed task-owned cleanup and verified UbuntuTransfer under
these gates. Proceed
through those authorized phases without asking the user to approve them again.
For an already running job, continue from its actual stage with the same approved
SHAs/config/outputs; do not restart, change source or repeat completed phases
merely to apply this approval. Preserve active processes, source and caches.
Build approval ends after verified transfer. Other builds, source changes/Git
publication, production SSH, hosting, migrations, deployment, installation,
acceptance and real customer use are outside this handoff.
It does not override sandbox/tool/UAC approval mechanisms: use required approvals
normally, never disable/bypass them or claim a prompt removes them. When mandatory
platform approval is still needed, explain the concrete action and platform rule;
when automatic review rejects it, report its reason and preserve dependent work.

## Delivery boundary

The S2 build-only handoff stops after package, maintenance and UbuntuTransfer
verification. Keep older delivery, production and migration receipts below as
historical evidence. A separately authorized release operator may use the
received EXE and the reviewed Office publisher without rebuilding it.

## Earlier attempt87e01f40 — notifier analyzer BLOCKED,2026-10-27

User S2 receipt:source/pins/codec reuse/SDK/ABI/plan/Preflight PASS;guards89PASS/
1Linux-onlySKIP. Analyzer exit2,0ERROR/4WARNING/30INFO. External notifyListeners
calls at desktop_setting_page.dart2088 and exantas_companion_model.dart282 each
trigger INVALID_USE_OF_VISIBLE_FOR_TESTING_MEMBER + INVALID_USE_OF_PROTECTED_MEMBER.
Dart regressions/native/EXE/maintenance NOT_RUN;new EXE NOT_PRODUCED.
Reviewed correction owns notification in a private ChangeNotifier subclass and
exposes only Listenable for subscriptions plus a public service notification
method. Both callers and profile input hashes change, nothing in codec/SDK/tool/
dependency/version/icon inputs. New published SHA is required before S2 retry;
do not re-run87e01f40, suppress warnings or treat cloud parsing as analyzer PASS.
Keep its failed evidence, genuine codec receipt784aba54 and compatible caches.
Completed baseline remains1c7cff12,2.0.0+72; candidate remains2.0.1+73.

Independent S2 read-only findings:owned Windows VM unavailable, Sandbox disabled;
running Office API1.12.16 has no common installer mount/config/download route.
Historical attempt:acceptance/hosting were BLOCKED by unavailable Windows proof
and manual rollout. Current2.0.2 policy allows honest NOT_RUN hosting after verified
package/maintenance and user manual Office1.12.18 rollout. No upload/deploy/restart. Build stages may proceed
independently after source correction; retain the hosting phase with its actual
blocker instead of inventing acceptance. No migration replay or sandbox enabling
is implied by this report. Office source staysde040725852f49761d602a81b6420e80f028f9e8.

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

## Earlier attempt: b94834c7 — analyzer BLOCKED, 2026-10-26

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

## Previous completed application/EXE baseline —4c678792 (historical)

User-forwarded S2 receipt received2026-10-28;Windows bytes/logs were not
independently accessed here. Source`4c6787926a46a2a981f1b251b0223c8853fce54b`,branch
codex/s2-codec-bootstrap-1.4.13,version2.0.1+73,Windows x64 EXE UNSIGNED.
Directory:`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.1+73\delivery-s2-4c678792`.
Filename:`rd-cl-2.0.1+73-windows-x64-install.exe`;size24332288bytes.
SHA256:`7a46b86664abacc9ec46adea51d35df664f6c3852886be19a87c9c8ff12641ec`.
Pull/pins/snapshot,codec reuse/SDK/ABI (no bootstrap),guards89PASS/1Linux-onlySKIP,
analyzer0ERROR/0WARNING/30INFO,Dart80PASS,native/EXE/ZIP/integrity122checksum entries
and maintenance plan/apply/verify PASS. ZIP/manifests/SHA256SUMS/INSTALLATION-EL.md,
BUILD-STATUS.md and real acceptance.json with NOT_RUN are beside EXE per report.
Windows acceptance NOT_RUN;hosting BLOCKED/NOT_PUBLISHED. No owned disposable
Windows environment is available. Last hosting check found API1.12.16 without
shared installer volume/config/route;user manual Office1.12.17 rollout remains
pending. No upload/publication/deploy/restart occurred. Do not invent signing or
runtime proof. No repeat build/handoff for this unchanged source:
NO_RDCL_BUILD_NEEDED. Any hosting-only continuation uses this actual package and
preserves pending acceptance;current publisher records honest PASS or NOT_RUN and requires maintenance PASS.

Retain prior packages/caches and failed87e01f40 evidence. Automatic managed-device
activation from contact association/download is proposed,not implemented in this
EXE. It supports the existing explicit installation-link activation path.

## Previous completed baseline —1c7cff12 (historical)


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
analyzer, compilation, packaging, hashes/reports, ελεγμένο task-owned cleanup
και επαληθευμένη μεταφορά μέσω UbuntuTransfer με τα υποχρεωτικά gates. Συνέχισε χωρίς να ζητάς ξανά την ίδια έγκριση.
Αν το build ήδη εκτελείται, συνέχισε από το πραγματικό τρέχον στάδιο με τα ίδια
εγκεκριμένα SHAs/config/outputs. Μην το επανεκκινήσεις, αλλάξεις source ή
επαναλάβεις ολοκληρωμένα στάδια μόνο εξαιτίας αυτής της έγκρισης.
Η έγκριση αφορά αποκλειστικά την παραγωγή του rd-cl EXE. Hosting, Dokploy,
production SSH, migrations, εγκατάσταση, αποδοχή, customer sessions και Git
publication είναι εκτός του ρόλου του S2.
Οι υποχρεωτικές εγκρίσεις sandbox/tools/UAC εξακολουθούν να ισχύουν· μην τις
παρακάμψεις ή απενεργοποιήσεις. Αν απαιτηθούν, εξήγησε τη συγκεκριμένη ενέργεια
και τον κανόνα της πλατφόρμας. Πραγματική αποτυχία σταματά τα εξαρτώμενα στάδια.

Προετοίμασε τα απαιτούμενα pinned inputs και εκτέλεσε το πλήρες build/package
του rd-cl στη VirtualBox VM Windows11-Development (UUID
8c15378e-e71b-4c78-bf41-e77ba3915205, Windows hostname DESKTOP-5OTBBT7).
Ο Exantas-S2 συντονίζει από Ubuntu, οι εντολές build εκτελούνται στο guest και τα
πακέτα μεταφέρονται μέσω UbuntuTransfer με επαλήθευση SHA-256 και στις δύο πλευρές.
Επιτρέπονται οι αναγκαίες λήψεις κατά την
προετοιμασία, με TLS, signatures/checksums και ακριβή lockfile/Git/version pins.
Τα υπάρχοντα guarded build/codec scripts παραμένουν offline/frozen.

Office publication: <verified Office repository/ref/full SHA>
rd-cl repository/ref: <verified repository and published ref>
Ακριβές rd-cl SourceCommit: <full published SHA>
Version: <manifest/profile version including Flutter build number>
Target: Windows x64, EXE installer και το υπάρχον verified runtime ZIP.
Τρόπος: <initial build ή continuation από συγκεκριμένο failed gate>
Τελευταία ολοκληρωμένη προσπάθεια: 680628f2b9e798ef63e6d29c73954807d9012e12, PASS build/package;hosting pending.
Ιστορικό d029c35d: BLOCKED analyzer, δεν χρησιμοποιείται ως διορθωμένο EXE.
Νεότερο reported SDK-aware receipt:
784aba5498e0a84922367ff58e506940c60b445958bc8ceda1ccf0b0e4796572
Current toolchain SHA256:
0b07fdfce291343d7a5f51b26275858c70faaed277da39347f61c18dcdbe0b70
Εντόπισε το πραγματικό config από τα manifests της delivery-s2-680628f2.
Επαλήθευσε πραγματικό path/hash/tool/SDK/ABI στον S2 και κράτησέ τα αμετάβλητα.
Αυτό είναι ανεξάρτητο codec proof, όχι επιτυχής εφαρμογή ή νέο completed baseline.
Προηγούμενο completed application/EXE baseline: 680628f2b9e798ef63e6d29c73954807d9012e12
Baseline version: 2.0.2+74
Baseline EXE SHA-256: d4843ebf32759b78f2663247d6fd72cb4ba7a2ce2229c9f59131186a4fa292a1
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
   Επιβεβαίωσε τον Ubuntu Exantas-S2, το UUID της VM, το Windows hostname
   DESKTOP-5OTBBT7, το UbuntuTransfer, τα Git roots/remotes και την τοπική κατάσταση.
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
   Χρησιμοποίησε το πραγματικό Known Folder Desktop και τα επαληθευμένα
   paths/config/receipts του guest. Τα παλιά paths του Windows S2 είναι ιστορικά.

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
   Office-Workspace-Artifacts\Builds\rd-cl\<version>\delivery-vm-<short-source-sha>
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

8. Μετά από package και maintenance PASS, μετέφερε το EXE, το συνοδευτικό runtime
   ZIP και τα απαραίτητα manifests/logs σε ξεχωριστό φάκελο του UbuntuTransfer.
   Παρήγαγε τον πίνακα SHA-256 από τα τοπικά αρχεία της VM και την καταγεγραμμένη
   τιμή SHA-256 του πίνακα. Στο Ubuntu επαλήθευσε ανεξάρτητα τον πίνακα και όλα
   τα αρχεία με sha256sum --check --strict. Δώσε τις απόλυτες διαδρομές και στις
   δύο πλευρές. Μια αστοχία μεταφοράς απαιτεί επαλήθευση ή νέα μεταφορά του ίδιου
   πακέτου. Η εργασία ολοκληρώνεται με επαληθευμένη παράδοση στο Ubuntu.

9. Παράδωσε ενιαία αναφορά: στάδια tests/preflight/codecs/application/EXE/artifact
   gate χωριστά, πραγματικές εντολές/log paths, source SHA και έκδοση. Αν το EXE
   υπάρχει και επαληθεύτηκε, ανέφερε υποχρεωτικά τον ακριβή απόλυτο κατάλογό του
   στο Desktop του S2, το πλήρες filename/path, μέγεθος και SHA-256. Πάρε τα από
   το πραγματικό OutputRoot/EXE-INFO.json και επιβεβαίωσε το αρχείο. Αν δεν έχει
   παραχθεί, πες NOT_PRODUCED και δήλωσε μόνο την planned διαδρομή ως τέτοια.

Ο S2 παραδίδει το build του rd-cl Windows x64 EXE και την τεκμηρίωσή του.
Εγκατάσταση και native acceptance παραμένουν NOT_RUN. Σε πραγματική αποτυχία
σταμάτα τα εξαρτώμενα βήματα, διατήρησε diagnostics και επέστρεψε συγκεντρωτικό
BLOCKED. Η προετοιμασία χρησιμοποιεί τα ακριβή pins και η μεταγλώττιση τους
υπάρχοντες offline guards.
```

The template's variables are filled from current source by the sender or resolved
from actual S2 metadata by the recipient, not guessed. The EXE's current naming
rule is `rd-cl-<profile.version>-windows-x64-install.exe` directly under OutputRoot;
verify it against the current packager and actual EXE-INFO.json each time. The
codec bootstrap output directory is not the application EXE delivery directory.
Include only the rd-cl EXE build and verified transfer in the S2 handoff.
