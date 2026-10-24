# Required rd-cl Windows icons

User decision, 2026-10-22: reuse the existing icons from the published branding
refresh. Do not design replacement icons or use the current full-word EXANTAS
artwork as a substitute without an explicit new user decision.

Authoritative repository: https://github.com/2bitegr/rd-cl.git
Authoritative immutable commit: `cf634df336de55daf3d67273a91194e427369e31`
Commit subject: `Fix companion enrollment and refresh branding`.
Verified as an ancestor of published `custom-windows-client`; that moving branch
is a discovery reference, not the immutable asset pin. Import only the five assets,
not the historical commit's application, dependency or authentication changes.

## Exact required assets

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `res/tray-icon.ico` | 372526 | `0ddb6370f8d1d80da794372cecb4191ae28d4e4c1042a6cecc0ab3caab622a90` |
| `res/icon.ico` | 372526 | `0ddb6370f8d1d80da794372cecb4191ae28d4e4c1042a6cecc0ab3caab622a90` |
| `flutter/windows/runner/resources/app_icon.ico` | 372526 | `0ddb6370f8d1d80da794372cecb4191ae28d4e4c1042a6cecc0ab3caab622a90` |
| `flutter/assets/icon.ico` | 372526 | `0ddb6370f8d1d80da794372cecb4191ae28d4e4c1042a6cecc0ab3caab622a90` |
| `flutter/assets/icon.png` | 24422 | `6dc3d3daf8cce082fc7ba4f14752ee08aab3fda0d675244f94a2e57910325382` |

The four ICO files are identical, with seven ICO image entries. The PNG has its
own separate hash. Retain original bytes, formats and resolutions; do not redraw,
resize, recompress or replace them with an approximation.

## Source and build responsibilities

Before the next source publication/build handoff, the source coordinator must
restore these exact five assets in reviewed source and verify every path/hash.
The2.0.0 source at6c9828b2 differs at all five paths. The current reviewed
publication restores all five exact assets and pins their build-profile hashes;
this establishes source equality, not a built/installed branded EXE. Missing/different assets mean the
required branding has not been applied; do not silently approve a new handoff.
Keep relevant build profile input hashes consistent when asset pins are added.

Verify actual consumers: `src/tray.rs` embeds `res/tray-icon.ico` for Windows;
`build.rs` and `libs/portable/build.rs` use `res/icon.ico` for applicable native
EXE/installer resources; Flutter runner's `Runner.rc` uses
`flutter/windows/runner/resources/app_icon.ico`. Keep both Flutter asset files
present for their assets consumers and verify packaging declarations as needed.
A Desktop shortcut must resolve to the installed branded executable and its icon;
source file equality alone does not prove installed shortcut/icon-cache behavior.

S2 consumes the published assets in its exact owned source snapshot. It must not
cherry-pick the old branding commit, edit/copy icons into its snapshot, change
source to satisfy this policy, weaken guards or rebuild codecs solely for icons.
Corrections belong in reviewed/published source. Preserve any running build,
existing receipts/codecs/caches and old delivery evidence; never retrofit its
provenance to claim it used icons absent from its immutable source commit.

At delivery, verify source icon hashes and native EXE/installer/Flutter resource
selection with available tooling. Actual tray/Desktop appearance and Windows icon
cache behavior are native runtime acceptance, separate from packaging evidence.
