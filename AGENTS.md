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
return corrections to S1. Missing rd-cl offline inputs mean BLOCKED, without
downloads or fallback builds on S1. The user performs final deployment manually
from S1 through Dokploy; report when/what to deploy and prerequisite gaps. Read
the published Office AGENTS.md for the full shared handoff/deployment procedure.
These roles grant no standing Git, installation, deployment or SQL permission.

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
Use installed tools and local dependencies only; missing/incompatible requirements
stop the release with an exact explanation, without downloads or reinstalls.
If the skill or required verification is unavailable, report the gate BLOCKED;
do not silently skip it or install tools. This does not authorize publication,
installation, production changes or cleanup outside the reviewed task scope.

## Local artifact storage and workspace cleanliness

Use the machine's verified local Windows Desktop as the persistent home for generated reports, evidence, graph indexes, logs, screenshots, temporary deliverables and application build packages. Default organized folder: `Office-Workspace-Artifacts`. Discover its actual absolute Windows path and WSL mount; do not hardcode another machine's username or assume Desktop is outside OneDrive.

Keep project source and portable source-adjacent documentation in their repositories: AGENTS.md, tracked skills/metadata, README, maintained architecture/interface/regression maps, tests, manifests, migrations and compact state files. A file is not disposable merely because it is Markdown or generated. Required runtime resources and installed tool environments are not reports and must not be moved blindly.

Store persistent generated output under the Desktop hierarchy by purpose and run/application/version. Keep executable paths and graph locations in local setup metadata; avoid machine-specific paths and secrets in tracked portable skills. Never commit generated graphs, private logs, installers, dependency caches, credentials or customer data unless specifically reviewed and authorized for that repository.

For artifact relocation: inspect ownership, symlinks, current consumers and destination first. Copy to a unique Desktop destination preserving required structure; verify all bytes/hashes and a manifest; update local graph/report references; validate consumers; only then remove the exact verified owned source files. No broad recursive cleanup, reset/clean, retained-enrollment/database deletion or deletion of unrelated files. If live consumers cannot be validated, retain source and mark relocation pending.

Control disk growth as part of completing each authorized task. Before generating artifacts, inspect existing outputs and reuse installed tools, dependency caches and the current owned build workspace. Keep the latest verified delivery for each requested application/version/target with its provenance and checksums; retain older full packages only for an identified rollback, comparison or review need. Do not accumulate timestamped full payload copies, repeated source exports, preflight/negative-test directories, extracted installer payloads or redundant logs.

After validating delivery bytes/hashes and current consumers, remove the exact task-owned disposable staging outputs within the authorized scope. This includes redundant `MsiPayload`/`Portable` copies and superseded test/build outputs; it does not include active source snapshots, compiler targets or reusable dependency caches. After a failure, retain a compact root-cause record and only the diagnostics/resumable state still needed. Keep one concise task summary/manifest, compress useful historical text logs when appropriate, and do not archive obsolete binaries merely to avoid deleting them. Update current artifact links when paths change.

Cleanup must use an explicit inspected file/path list, reject symlinks/reparse points or unknown ownership, check active consumers, and recheck size/hash immediately before removal. Existing user cleanup authorization covers that verified scope; uncertain or unrelated files stay in place. Report retained outputs and logical bytes removed separately from measured disk-space changes. Do not create a scheduled/global purge or delete other projects' resources as routine cleanup.

For rd-cl, use the existing libraries/toolchains and Cargo/Pub/vcpkg/NuGet caches without new downloads, reinstalls or upgrades. If an existing dependency is missing or incompatible, stop and notify the user. Preserve both Windows and Linux support/resources unless the user explicitly authorizes a platform-specific removal. Neither a cache name nor an old timestamp alone establishes that an item is disposable.

Prefer explicit output/log/build paths on the Windows data volume. If a tool requires Linux scratch for correctness or performance, use a bounded owned temporary directory and remove it after verified export. Do not relocate installed SDKs/venvs, application data or runtime databases merely to reduce disk usage. Reassess unusually large reproducible caches separately with evidence and authorization.

Desktop build packages for rd-cl, CallerPopup and GrandStreamAgent must include source repository/commit, dirty-source caveat if applicable, version, target architecture, toolchain, build result and SHA-256 manifest. Build output is not permission to install, run, restart a service, connect to production or publish a GitHub Release.

Report bytes exported and source bytes actually removed separately. Freeing Linux files does not by itself prove the host's WSL virtual disk file shrank. Do not perform VHD compaction or WSL shutdown as routine cleanup.

The Desktop is an artifact destination, not a secret backup store. Keep secrets/business data in their established protected locations; do not copy them into reports/builds. Unrelated generated work also belongs outside Office repositories, under a separate Desktop category.
