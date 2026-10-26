# RustDesk Guide

## Project Layout

### Directory Structure
* `src/` Rust app
* `src/server/` audio / clipboard / input / video / network
* `src/platform/` platform-specific code
* `src/ui/` legacy Sciter UI (deprecated)
* `flutter/` current UI
* `libs/hbb_common/` config / proto / shared utils
* `libs/scrap/` screen capture
* `libs/enigo/` input control
* `libs/clipboard/` clipboard
* `libs/hbb_common/src/config.rs` all options

### Key Components
- **Remote Desktop Protocol**: Custom protocol implemented in `src/rendezvous_mediator.rs` for communicating with rustdesk-server
- **Screen Capture**: Platform-specific screen capture in `libs/scrap/`
- **Input Handling**: Cross-platform input simulation in `libs/enigo/`
- **Audio/Video Services**: Real-time audio/video streaming in `src/server/`
- **File Transfer**: Secure file transfer implementation in `libs/hbb_common/`

### UI Architecture
- **Legacy UI**: Sciter-based (deprecated) - files in `src/ui/`
- **Modern UI**: Flutter-based - files in `flutter/`
  - Desktop: `flutter/lib/desktop/`
  - Mobile: `flutter/lib/mobile/`
  - Shared: `flutter/lib/common/` and `flutter/lib/models/`

## Rust Rules

* Avoid `unwrap()` / `expect()` in production code.
* Exceptions:

  * tests;
  * lock acquisition where failure means poisoning, not normal control flow.
* Otherwise prefer `Result` + `?` or explicit handling.
* Do not ignore errors silently.
* Avoid unnecessary `.clone()`.
* Prefer borrowing when practical.
* Do not add dependencies unless needed.
* Keep code simple and idiomatic.

## Tokio Rules

* Assume a Tokio runtime already exists.
* Never create nested runtimes.
* Never call `Runtime::block_on()` inside Tokio / async code.
* Do not hide runtime creation inside helpers or libraries.
* Do not hold locks across `.await`.
* Prefer `.await`, `tokio::spawn`, channels.
* Use `spawn_blocking` or dedicated threads for blocking work.
* Do not use `std::thread::sleep()` in async code.

## Editing Hygiene

* Change only what is required.
* Prefer the smallest valid diff.
* Do not refactor unrelated code.
* Do not make formatting-only changes.
* Keep naming/style consistent with nearby code.

## Localization (`src/lang/*.rs`)

Each file is a `HashMap<key, translation>`. Layout:

* `template.rs` is the master list of every key. **Never edit it** as part of translation work.
* `en.rs` holds only the keys whose English display text differs from the key itself.
* Every other file (`de.rs`, `fr.rs`, …) carries the full key set; an untranslated entry has an empty value: `("key", "")`.

### Finding the English source for a key

When filling an empty entry, determine the source English text with this rule:

* If `key` exists in `en.rs` **with a non-empty value**, that value is the source text (look it up in `en.rs`).
* Otherwise the **key string itself is the source text** (the key is already plain English).

Then translate that source into the file's target language (infer the language from the file's existing non-empty entries / filename).

### Translation hygiene

* Only fill empty values. Never change keys, and never touch existing non-empty translations.
* Preserve placeholders (`{}`) and escape sequences (`\n`, `\"`) exactly as in the source.
* Do not translate brand or technical tokens: `RustDesk`, `Socks5`, `TLS`, `UAC`, `Wayland`, `X11`, `TCP`, `UDP`, `2FA`, `RDP`, `D3D`, etc.
* Copy URL values (e.g. `doc_*` keys) verbatim from `en.rs`.

## Office workstation roles

Development, source/version/build-tooling corrections, commits and pushes belong
only to S1 (Windows DESKTOP-IQ8ORD5). S2 (Windows S2) pulls published source;
its delivery-build role covers changed rd-cl only, never this API or other apps.
S2 performs reviewed Office migrations only through a separate user-forwarded
handoff with target, ledger, backup, ownership and locking safeguards. Verify the
actual host before work. S2 must not author source, bump versions, commit or push;
return corrections to S1. Prepare missing pinned rd-cl inputs under the download policy below. Explicit
offline tasks or unavailable/unverifiable inputs mean BLOCKED; no fallback
builds on S1. The user performs final deployment manually
from S1 through Dokploy; report when/what to deploy and prerequisite gaps. Read
the published Office AGENTS.md for the full shared handoff/deployment procedure.
These roles grant no standing Git, installation, deployment or SQL permission.

## One complete S2 build handoff

On a user request for Office commit/push, the source/coordinator agent inspects
both Office and rd-cl for related task-owned uncommitted/unpublished changes and
published rd-cl changes since the last completed S2 application/EXE build. The
coordinated publication includes those related reviewed rd-cl changes unless the
user explicitly limits scope; apply this repository's live-ref, review and cleanup
Git gates and preserve unrelated work. An Office push alone does not publish
rd-cl. After successful publication (including user-reported Office publication),
verify live refs and, when rd-cl is pending, return one complete S2 prompt in the
same response without another request. Begin the prompt with safe fast-forward
pull/synchronization of published Office instructions and rd-cl source, verify
the exact full SHAs and pinned submodule, then build from a matching owned
snapshot. S2 must not create a commit or push, reset/clean/rebase or auto-stash;
dirty/diverged work must be preserved and reported. A blocked publication means
BLOCKED, never a prompt for unpublished source.
Use [the maintained handoff procedure](docs/windows-s2-build-handoff.md) and the
actual current scripts/profile. Include local preparation, codec receipt reuse
or conditional codec bootstrap, verified dependency preparation, native application
build, EXE packaging and
artifact verification in that one prompt. Missing local inputs are investigated
and prepared before a consolidated BLOCKED report. Required pinned downloads
are permitted; no guard/source edits on S2.
Report the absolute Desktop output directory and full verified EXE path/name,
version, source commit and SHA-256. Planned paths are not proof a package exists.
Keep codec-only results separate from application/EXE success. Record source
baseline/handoff/completion evidence to avoid duplicate prompts/builds. If rd-cl
is unchanged, report NO_RDCL_BUILD_NEEDED. No automatic builds, Actions, product
installation or deployment is implied. The former cloud build plan is superseded.

The latest completed S2 application/EXE baseline, reported by the user on
2026-10-24, is `1c7cff1289438b84788b3b2b78ab30c05ce25202`, version `2.0.0+72`.
Read the maintained handoff guide's completed baseline for the EXE hash, size,
codec receipt and acceptance limits; do not use earlier blocked/codec-only states.
Reported EXE directory:
`C:\Users\Support-2\Desktop\Office-Workspace-Artifacts\Builds\rd-cl\2.0.0+72\delivery-s2-1c7cff12`.
Keep that verified delivery unchanged and use an unused owned output directory
for the next build. An unchanged published SHA needs no repeat build.

The prompt must preserve actual pinned Git-object checks (shallow alone is not
failure), reuse a matching genuine codec receipt, and verify after VsDevCmd that
`VCPKG_ROOT` comes from the same configured/drive-aliased `paths.vcpkg` used by the
receipt/ABI verifier and installed-only plan. Inspect `native-vcpkg-root.json`;
never use Visual Studio's bundled vcpkg or edit hwcodec on S2. Include guard tests,
Dart regressions, Rust/Flutter build, EXE/runtime integrity, SHA256SUMS/manifests,
BUILD-STATUS.md, Greek INSTALLATION-EL.md and release-maintenance verification.
Packaging PASS does not authorize or prove signing, installation, upgrade or real
runtime acceptance; those remain NOT_RUN until separately performed and reported.

## Preserve verified application build caches

Future S2 handoffs must assess the last successful CARGO_TARGET_DIR and compatible
Flutter build state before allocating a cold application target. A new source SHA
or delivery directory alone is not a reason to discard compiled dependencies.
Keep immutable source snapshots and separate delivery roots; reuse compatible
owned caches under the existing session locks and pinned tool/SDK/codec checks.
Ambiguous or incompatible native-cache provenance still requires isolation, with
an exact recorded reason. Never copy a stale DLL as proof of a new build, skip
Cargo/Flutter/tests or weaken guards. Let the build tools determine recompilation.
Current scripts pin Cargo to -j1; changing CARGO_BUILD_JOBS cannot override that.
Parallelism changes need reviewed source tooling and S2 CPU/RAM/peak-memory
measurements, not an unreviewed local command edit. Record per-stage wall times
and distinguish cold compilation from repeat builds; do not promise an unmeasured
build-time target. See rd-cl/docs/windows-native-build.md for measured S2 timings.

## Required rd-cl Windows branding

User-selected canonical icons are the five assets from immutable rd-cl commit
`cf634df336de55daf3d67273a91194e427369e31` (branding refresh in
`custom-windows-client`): res/tray-icon.ico, res/icon.ico,
flutter/windows/runner/resources/app_icon.ico, flutter/assets/icon.ico and
flutter/assets/icon.png. Use those exact bytes; no new design, full-word EXANTAS
substitute, resizing or recompression without an explicit user change.
Read rd-cl/docs/windows-branding.md for verified hashes and consumers. Before the
next publication/build handoff the source coordinator restores/verifies only these
assets in reviewed source; never import the old commit's unrelated source/auth
changes. S2 builds the published assets and reports mismatch, without local source
edits. Verify tray/EXE/installer/Flutter/Desktop icon selection; distinguish static
resource checks from installed runtime/icon-cache acceptance. Reuse compatible
verified codecs for icon-only changes; do not interrupt an active historical build
or rewrite its provenance. A policy edit alone is not restored branding.

## Native build integrity gates

Windows Office sign-in has one entry point: Settings → Account. The Home Office
card shows status and navigates there; do not reintroduce a second login form.
Use Office credentials and the existing native lease bridge, never replace this
with a shared RustDesk user/password or remove foreign-owner/role guards. Existing
legacy native sessions require explicit authenticated logout before Office login;
preserve local credentials on an unconfirmed migration logout. No device/user/ID
deletion or automatic ownership transfer is implied. Non-Windows native Account
behavior remains unchanged until its secure-store integration is reviewed.

The 2026-10-22 audit fixes require the owned hbb_common tree to equal its pinned
commit plus only the reviewed patch (CRLF allowed, extra tracked/staged/untracked
source rejected), and exact native receipt/runtime/ZIP inventories. Compiler reuse
checks cl/link/lib/CMake/vcpkg, selected SDK identity and the SDK-pinned triplet.
Use Windows SDK10.0.22621.0 from the profile; verify actual Flutter project SDK
selection as well. Read rd-cl/docs/windows-s2-build-integrity.md and current scripts.

The historical genuine codec receipt3b02998a60c5439c3031ba84536791837ed9cce6290bccad6a36f256fb229e97
has no SDK identity and cannot pass the hardened reuse guard. Preserve it, the
old codecs/configs and the completed ad46 EXE. Do not amend old proof with current
SDK hashes. For this migration, use new unused owned codec/output roots and real
updated bootstrap compilation to produce a new SDK/tool/ABI receipt and derived
JSON; do not copy an S1 receipt or fabricate schema upgrades. Later compatible
application-only changes can reuse the new receipt. No dependency/version bump
is needed; the triplet now explicitly selects the already required SDK22621.

Use one windows-native-release.ps1 -Mode Build -WithExe invocation. Resource
locks cover the snapshot/output/Cargo target/Flutter/vcpkg/alias through packaging;
do not launch a parallel PackageExe or delete busy/stale/changed locks. Investigate
ownership/process state instead. Keep the current complete prompt, required
verified preparation downloads, artifact gate and exact EXE path/hash reporting.
Local guard/PowerShell/CMake PASS is not native S2 build/runtime acceptance.
User-authorized current source release is2.0.0 (Flutter2.0.0+72). See
rd-cl/docs/windows-installer-2.0.0.md for the installer correction and required
native clean-install/upgrade acceptance. The old1.4.13+71 packaging PASS remains
historical; user-reported installation/upgrade failed (old core, broken shortcut,
stopped service). Do not call it a verified installation or overwrite its evidence.
For CRLF synthetic fixtures, normalize existing CRLF before generating CRLF;
Git apply may already emit CRLF under core.autocrlf=true. Test true/false/input
in fixture-local configuration, retain negative CRCRLF/extra-source checks and
never relax production source guards or change global Git settings to fix tests.
When installation screenshots show a different version, record actual installer
SHA256 and running core DLL path/hash against the delivery manifest before
concluding which build is installed. Sidebar version comes from the Rust core;
the older-installation warning compares BuildDate registry metadata. Packaging
PASS cannot establish installation/service acceptance. Use the diagnostic steps
in rd-cl/docs/windows-s2-build-integrity.md; do not silently reinstall/start services.



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
This is task-scoped build approval, not permission for product installation,
deployment, production DB changes, real customer sessions, source/guard changes,
credential disclosure, Git publication on S2 or unrelated destructive operations.
It does not override sandbox/tool/UAC approval mechanisms: use required approvals
normally, never disable/bypass them or claim a prompt removes them. When mandatory
platform approval is still needed, explain the concrete action and platform rule;
when automatic review rejects it, report its reason and preserve dependent work.

## Mandatory cleanup before commit, push and release

Before creating any commit and before every `git push`, run a dedicated cleanup
agent using the shared skill below. This includes documentation-only changes and
pushes without a new build. Wait for its completed PASS report on the current
affected work and artifacts. Run a fresh check before push even after a pre-commit
PASS; intervening file/artifact changes invalidate the result. A dispatched agent,
historical PASS or skipped check is insufficient. If the agent/check is
unavailable or BLOCKED, stop the Git operation and report why; do not bypass it.

Limit cleanup to inspected, authorized task-owned disposable files. Preserve
staged/unstaged source, index selections, active runtime data, Windows/Linux
resources and reusable caches. The cleanup agent must not stage, commit or push.
If nothing is disposable, record an actual completed PASS with zero removals;
do not create a build or download dependencies just to perform this check.
Reuse one compact current cleanup record; do not accumulate per-command reports.
Existing approval requirements and release hooks still apply.

Before preparing or handing off a release/build package, use the Office repository's
`office-release-maintenance` skill at `.agents/skills/office-release-maintenance/SKILL.md`.
Locate the actual Office checkout by Git remote `2bitegr/Office`; read the exact
skill when it is not in the current registry. It covers affected applications and
requires an explicit plan, authorized task-owned cleanup and a PASS artifact
`verify` before delivery, alongside this repository's existing release checks.
Preserve active source/runtime data, Windows/Linux resources and reusable caches.
User policy (2026-10-22): required dependency/build-tool downloads are permitted,
including on S2; disk space is no longer a blanket reason to prohibit them.
Reuse existing caches, then prepare missing exact prerequisites from trusted
sources without asking for another exception. Preserve TLS, signatures/checksums,
lockfiles, Git pins, existing working tools and application/dependency versions.
Use side-by-side or owned tool roots. Stage verified inputs before the existing
offline/frozen builds; do not disable guards, enable lazy fetch during those
builds or copy/fabricate codec receipts. An explicitly offline task still blocks
on absent local inputs, as do unavailable/unverifiable requirements or real errors.
If the skill or required verification is unavailable, report the gate BLOCKED;
do not silently skip the gate or install unrelated tools. This does not authorize publication,
product installation, production changes or cleanup outside the reviewed task scope.

## Local artifact storage and workspace cleanliness

Use the machine's verified local Windows Desktop as the persistent home for generated reports, evidence, graph indexes, logs, screenshots, temporary deliverables and application build packages. Default organized folder: `Office-Workspace-Artifacts`. Discover its actual absolute Windows path and WSL mount; do not hardcode another machine's username or assume Desktop is outside OneDrive.

Keep project source and portable source-adjacent documentation in their repositories: AGENTS.md, tracked skills/metadata, README, maintained architecture/interface/regression maps, tests, manifests, migrations and compact state files. A file is not disposable merely because it is Markdown or generated. Required runtime resources and installed tool environments are not reports and must not be moved blindly.

Store persistent generated output under the Desktop hierarchy by purpose and run/application/version. Keep executable paths and graph locations in local setup metadata; avoid machine-specific paths and secrets in tracked portable skills. Never commit generated graphs, private logs, installers, dependency caches, credentials or customer data unless specifically reviewed and authorized for that repository.

For artifact relocation: inspect ownership, symlinks, current consumers and destination first. Copy to a unique Desktop destination preserving required structure; verify all bytes/hashes and a manifest; update local graph/report references; validate consumers; only then remove the exact verified owned source files. No broad recursive cleanup, reset/clean, retained-enrollment/database deletion or deletion of unrelated files. If live consumers cannot be validated, retain source and mark relocation pending.

Control disk growth as part of completing each authorized task. Before generating artifacts, inspect existing outputs and reuse installed tools, dependency caches and the current owned build workspace. Keep the latest verified delivery for each requested application/version/target with its provenance and checksums; retain older full packages only for an identified rollback, comparison or review need. Do not accumulate timestamped full payload copies, repeated source exports, preflight/negative-test directories, extracted installer payloads or redundant logs.

After validating delivery bytes/hashes and current consumers, remove the exact task-owned disposable staging outputs within the authorized scope. This includes redundant `MsiPayload`/`Portable` copies and superseded test/build outputs; it does not include active source snapshots, compiler targets or reusable dependency caches. After a failure, retain a compact root-cause record and only the diagnostics/resumable state still needed. Keep one concise task summary/manifest, compress useful historical text logs when appropriate, and do not archive obsolete binaries merely to avoid deleting them. Update current artifact links when paths change.

Cleanup must use an explicit inspected file/path list, reject symlinks/reparse points or unknown ownership, check active consumers, and recheck size/hash immediately before removal. Existing user cleanup authorization covers that verified scope; uncertain or unrelated files stay in place. Report retained outputs and logical bytes removed separately from measured disk-space changes. Do not create a scheduled/global purge or delete other projects' resources as routine cleanup.

For rd-cl, reuse existing libraries/toolchains and Cargo/Pub/vcpkg/NuGet caches; prepare missing exact prerequisites under the download policy above. Preserve working tools and caches; no dependency upgrades or unnecessary reinstalls. Unavailable or unverifiable prerequisites still block dependent work. Preserve both Windows and Linux support/resources unless the user explicitly authorizes a platform-specific removal. Neither a cache name nor an old timestamp alone establishes that an item is disposable.

Prefer explicit output/log/build paths on the Windows data volume. If a tool requires Linux scratch for correctness or performance, use a bounded owned temporary directory and remove it after verified export. Do not relocate installed SDKs/venvs, application data or runtime databases merely to reduce disk usage. Reassess unusually large reproducible caches separately with evidence and authorization.

Desktop build packages for rd-cl, CallerPopup and GrandStreamAgent must include source repository/commit, dirty-source caveat if applicable, version, target architecture, toolchain, build result and SHA-256 manifest. Build output is not permission to install, run, restart a service, connect to production or publish a GitHub Release.

Report bytes exported and source bytes actually removed separately. Freeing Linux files does not by itself prove the host's WSL virtual disk file shrank. Do not perform VHD compaction or WSL shutdown as routine cleanup.

The Desktop is an artifact destination, not a secret backup store. Keep secrets/business data in their established protected locations; do not copy them into reports/builds. Unrelated generated work also belongs outside Office repositories, under a separate Desktop category.

## Durable native Office session closure

Normal close of the last active remote connection view records the close event;
tab moves, extra shared views and closing the home page do not close a session.
Keep DPAPI-protected lifecycle delivery separate from v1/v2 report suppression,
persist before acknowledging main-window IPC, retry immutable event IDs after
lost ACK/restart and fence owner/API/from-peer. Reconnects in one Flutter tab are
distinct native connections. Use Office companion sessions/close with an exact
audited native session ID; no peer/time guessing, fake receipt or automatic bill.
Client timing stays unverified until authoritative audit evidence confirms it.
This requires the new Office1.12.9 receiver before S2 runtime acceptance. Pure
Dart lifecycle tests plus native close/retry/multi-window tests are required;
syntax checks alone are not behavioral/native acceptance. Preserve codec receipt
and warm application caches: these Dart/API changes do not alter codec inputs.
