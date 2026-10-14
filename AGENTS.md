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

## Local artifact storage and workspace cleanliness

Use the machine's verified local Windows Desktop as the persistent home for generated reports, evidence, graph indexes, logs, screenshots, temporary deliverables and application build packages. Default organized folder: `Office-Workspace-Artifacts`. Discover its actual absolute Windows path and WSL mount; do not hardcode another machine's username or assume Desktop is outside OneDrive.

Keep project source and portable source-adjacent documentation in their repositories: AGENTS.md, tracked skills/metadata, README, maintained architecture/interface/regression maps, tests, manifests, migrations and compact state files. A file is not disposable merely because it is Markdown or generated. Required runtime resources and installed tool environments are not reports and must not be moved blindly.

Store persistent generated output under the Desktop hierarchy by purpose and run/application/version. Keep executable paths and graph locations in local setup metadata; avoid machine-specific paths and secrets in tracked portable skills. Never commit generated graphs, private logs, installers, dependency caches, credentials or customer data unless specifically reviewed and authorized for that repository.

For existing disposable artifacts: inspect ownership, symlinks, current consumers and destination first. Copy to a unique Desktop destination preserving required structure; verify all bytes/hashes and a manifest; update local graph/report references; validate consumers; only then remove the exact verified owned source files. No broad recursive cleanup, reset/clean, retained-enrollment/database deletion or deletion of unrelated files. If live consumers cannot be validated, retain source and mark relocation pending.

Prefer explicit output/log/build paths on the Windows data volume. If a tool requires Linux scratch for correctness or performance, use a bounded owned temporary directory and remove it after verified export. Do not relocate installed SDKs/venvs, application data or runtime databases merely to reduce disk usage. Reassess unusually large reproducible caches separately with evidence and authorization.

Desktop build packages for rd-cl, CallerPopup and GrandStreamAgent must include source repository/commit, dirty-source caveat if applicable, version, target architecture, toolchain, build result and SHA-256 manifest. Build output is not permission to install, run, restart a service, connect to production or publish a GitHub Release.

Report bytes exported and source bytes actually removed separately. Freeing Linux files does not by itself prove the host's WSL virtual disk file shrank. Do not perform VHD compaction or WSL shutdown as routine cleanup.

The Desktop is an artifact destination, not a secret backup store. Keep secrets/business data in their established protected locations; do not copy them into reports/builds. Unrelated generated work also belongs outside Office repositories, under a separate Desktop category.
