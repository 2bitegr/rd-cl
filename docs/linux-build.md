# Exantas Support for Ubuntu (amd64 .deb)

The Linux client is the same rd-cl source as Windows. Branding and servers are
applied in code on every platform (`apply_exantas_custom_client` in
`src/common.rs`, plus `patches/hbb_common-exantas-config.patch`): app name
"Exantas Support", `desk.exantas.eu:21116/21117`, `https://desk-api.exantas.eu`
and the server public key. No `custom.txt` is needed.

## Package

`python3 build.py --flutter --hwcodec --unix-file-copy-paste` produces
`exantas-support_<version>_amd64.deb`:

- Package name `exantas-support` (Provides/Conflicts/Replaces `rustdesk`, since
  the files keep RustDesk's Linux layout: `/usr/share/rustdesk`,
  `/usr/bin/rustdesk`, the `rustdesk` systemd service, PAM and xorg files).
- `/usr/bin/exantas-support` → `/usr/share/rustdesk/rustdesk`: the stable path
  Office Call Popup on Ubuntu uses to recognize and start the client.
- Menu entry "Exantas Support" with the approved "EX" icon
  (`flutter/assets/icon.png`, see [windows-branding.md](windows-branding.md)).
- `rustdesk://` links are registered (`rustdesk-link.desktop`) and accepted by
  the client on Linux, because the spaced product name gives no valid scheme.

Toolchain used: Flutter 3.24.5, Rust 1.75.0, flutter_rust_bridge_codegen 1.80.1,
vcpkg at the baseline in `vcpkg.json` with the `res/vcpkg` overlays, on Ubuntu
24.04 with the usual RustDesk Linux build packages plus `libsecret-1-dev`.

## Office technician sign-in on Linux

Settings → Account offers the same Office sign-in as Windows, including
installation approval (contract 2) and the five-minute native lease. Windows
protects these values with DPAPI; Linux uses the desktop keyring:

- `src/office_secret_linux.rs` keeps one random per-user key in the Freedesktop
  Secret Service (libsecret, schema `eu.exantas.Support`) and seals local values
  as `secret:v1:<base64>` (XSalsa20-Poly1305). No plaintext fallback: without an
  unlocked keyring, sign-in fails with a visible error.
- Values written as plain text by earlier Linux builds are still readable and
  are re-sealed on the next write.
- The Rust native-auth reader (`office_native_auth.rs`) opens the lease the same
  way, so remote windows observe refresh and logout as on Windows.

## Office Call Popup handoff

Office Call Popup 1.4.21 for Ubuntu writes the one-time native ticket to the
keyring entry `Exantas.OfficeCallPopup.Handoff.v1.native-<ticket>` (schema
`eu.exantas.OfficeCallPopup`, the popup's own) and starts
`/usr/bin/exantas-support rustdesk://connection/new/<id>?office_ticket=<ticket>`.
The client reads the entry, checks the API and peer scope, and deletes it, as
it does with Windows Credential Manager.

## Windows-only on purpose

Customer device enrollment, customer support tickets (screen capture) and
silent updates stay Windows-only. The Linux Account page shows only the
technician card.
