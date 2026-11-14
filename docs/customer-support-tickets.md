# Customer support tickets — rd-cl3.1.1


## 50 MB correction —3.1.1 source preparation2026-11-14

User approved reducing videos to50,000,000bytes while leaving the shared Storage
global limit at52,428,800bytes, with a new installer. Source/PE/Flutter/profile
metadata targets clean3.1.1. Selection rejects50,000,001bytes before hashing or
transport; help/error copy agrees. Images remain10MB; five files/200MB total and
retention/original-file behavior are unchanged. No dependency/tool/codec change.

Office1.12.53 prepares the matching API/bucket contract and new forward migration
20261114000100 after unchanged20261112 SQL. Portal help reads capability limits.
Old3.1.0 can still select/display100MB before server rejection; use the new
installer for consistent50MB guidance, preserving customer identity/enrollment.

Source is prepared for coordinated publication. No3.1.1 EXE or hosting receipt exists.
The completed3.1.0 below remains the last delivered version. After publication,
use one S2 build/package/maintenance/hosting prompt with exact new SHAs, an unused
owned snapshot/output and verified reuse of compatible caches/codecs. Preserve
3.1.0, prior failure evidence and unrelated hbb_common. New source is not permission
to repeat cleanup/compression/UAC changes, bootstrap codecs or install the product.

Migration/storage remain blocked independently by the forwarded backup-fingerprint
evidence gap. Never solve it by guessing the writer or changing the global limit.

## Delivery completion2026-11-13

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

Earlier preparation/blocked notes below retain their dated historical meaning;
the completed delivery above supersedes their build/package/hosting status only.

## Historical source preparation2026-11-12

2026-11-12. Local source on S1, based on main
602d462d3309cd5d045f48e01df2dbd924d79af4 (3.0.0). Release metadata now targets3.1.0 with Office1.12.52;
publication/build/hosting receipts remain separate. Preserve the unrelated existing hbb_common overlay.

## Customer flow

The Windows Home Office card exposes **Αίτημα υποστήριξης** for a fully enrolled
customer device without an active staff login. An unbound generic installation
cannot select an arbitrary company. The enrolled API/device/credential determines
authority; server-derived company/site is asserted when submitting an offline
draft. No technician login, phone call or automatic remote session is involved.

The customer can create, list, read and reply to the same scoped ticket shown in
Office and the customer portal. Category/priority, subject/details and optional
reporter name/phone are distinct from verified CRM identity. Public history and
published reports are visible; internal staff notes, other devices/companies/sites,
financial fields and linked-work CRM contact data require their own authority.
Device proof never grants finance/CRM-contact access to a work report.

Existing PNG/JPEG/MP4/WebM files are selected explicitly and inspected before
upload. Screenshots use the existing Windows GDI API only after a privacy notice
and Save dialog, with a three-second countdown while the app is minimized. Image
preview is local. Video preview opens the selected file in the user's default
local player; no background capture or built-in recorder is introduced.

Local originals remain where the customer chose them. The program neither deletes
nor modifies selected originals; capture creates a new PNG exclusively and cannot
overwrite an existing file. Office stores a separate private copy so authorized
technicians/portal readers do not depend on the customer computer being online.
Limits: image10,000,000 bytes, video50,000,000 bytes, five active files and
200,000,000 bytes total per ticket. No silent conversion/compression.

## State and transport

`ExantasCustomerSupportPage` uses the new exantas_customer_ticket,
exantas_customer_ticket_runtime, exantas_customer_ticket_store and
exantas_customer_ticket_proxy models. Existing staff Account and native support
session behavior remain separate. Existing cached crypto3.0.6 was promoted from
transitive to direct in pubspec/lock, without a version or transitive change.

The actual platform application-support directory contains
`office-customer-tickets/<SHA256(API/device/credential)>/draft.0.protected`,
`draft.1.protected` and a lock. Windows runtime requires the existing DPAPI codec;
two encrypted generations store bounded draft/reply/file metadata. Raw credentials
are not stored there, and text/paths are not persisted in clear text. A corrupt
generation fails closed; it cannot silently restore an old editable operation key.

Every mutation persists its stable nonce/body before network I/O. A lost create
ACK uses GET/operations readback or the identical create; a reply survives restart
with the same key/text. An attempted create cannot be edited/discarded until its
outcome is known. Uploaded files preserve prepare/complete IDs and streamed SHA256;
lost PUT ACKs confirm the original bytes instead of upserting/resubmitting a ticket.
The user may reselect only a matching original or explicitly stop the local
pending transfers, retaining the submitted ticket and confirmed server files.

Each API operation rechecks current enrollment/credential/proxy settings before
and after I/O. Account events immediately hide old history; reassigned scope does
not rebind a retained draft. JSON and signed PUTs use the existing HTTP/HTTPS/SOCKS5
settings. Proxy credentials stay in memory, no direct fallback follows a failed
tunnel, and target/proxy TLS is validated. Signed storage PUTs carry no Office
bearer. SOCKS5 negotiation/auth follows RFC1928/RFC1929; partial/malformed supported
credentials, unknown schemes and redirects are rejected.

## Office dependency and lifecycle

The reviewed Office local candidate is based on
8d8e5a4815c41910a0b65fd4609a1486f8498e71 (1.12.51), with the new
`/api/v1/rustdesk-devices/support/tickets` capability/list/create/recovery/detail/
message and prepare/complete/download routes. Contract version1; device caps
include viewer ID and the current company/site IDs/names. This client cannot use
an older API that lacks that reviewed contract.

Office/portal share public replies/status/media and explicitly linked support
work. Only the existing preview/finalize flow creates a financial posting.
Creation/completion notifications reuse immutable Office templates, configured
recipient lists and the controlled outbox. A selected final report email suppresses
a second closing notification to the same recipient. Queueing/provider acceptance
is not proof of delivery/read; unknown acceptance never auto-retries.

Office001/002/003 migrations, a dedicated private support-tickets bucket and
reviewed customer-reachable HTTPS storage/CORS/timeout configuration are delivery
prerequisites. Feature/mail/retention flags default OFF. The source change does not
enable them or create production storage. Screenshots expire12calendar months and
video90days after closure. Reopen cancels only unclaimed expiry; a committed purge
tombstone/removed object is irreversible. Exact-object deletion keeps metadata and
append-only history; it never acts on the original customer files or proves backup
erasure. Abandoned upload cleanup fences issued capabilities plus24hour grace.

## Local verification and remaining acceptance

Flutter3.24.5 / Dart3.5.4, installed caches only:13core/store/proxy and11widget
tests PASS. Scoped analyzer0errors/0warnings with4unchanged Home INFO. Actual
Dart HTTPS integration passes against real managed-device auth/current Office
handlers and the retained isolated PostgreSQL fixture, using private fake storage.
It checks authenticated/anonymous HTTP/HTTPS/SOCKS5, bad proxy auth, untrusted TLS,
lost acknowledgements, four exact file transfers, one reply and zero bearer leaks.

Office's final48PASS batch covers35real PG scenarios,9core and3retention units
plus one harness: actual paid finalize/rollback/replay, report/contact/finance
scope, deduplicated email and physical fake-object purge/concurrency/reopen.
Web evidence:6helpers,10browser flows and1layout follow-up PASS; one Web build.
Evidence: Office docs/rdcl-customer-support-tickets.md and
/tmp/office-customer-tickets-20261112/final-checkpoint.json on S1.

Actual Windows DPAPI/GDI/save-picker/player behavior is NOT_RUN. No EXE/package,
installation, real storage/provider action, production migration, activation,
commit/push, NAS change or deploy occurred. Publish reviewed source only when
authorized; then issue one exact-SHA S2 Windows build/hosting handoff and a separate
pending-only migration handoff. Do not rebuild the unchanged old3.0.0 baseline or
claim its installer contains this unpublished feature.

## Source publication preparation2026-11-12

Product version3.1.0 is clean MAJOR.MINOR.PATCH without a build suffix. Rust,
Flutter, packer, PE metadata, locks and native profile agree. The reviewed native
profile binds all new customer-ticket inputs, and the existing build invocation
now runs both new Dart suites. Codec/SDK/engine pins and hbb_common remain unchanged.
Reuse compatible verified codecs and warm application caches on S2; do not rebuild
the previous3.0.0 delivery or treat this source preparation as a completed EXE.
Fresh Office recheck proves the complete browser cycle with exactly one
finalization/debit/report after double click and fake notification delivery only.
Private storage, the three published Office migrations and separate manual API/Web
rollout are required before activation/native customer acceptance. All new flags
remain OFF. No S1 delivery build or product installation is authorized here.


## Windows widget teardown correction2026-11-13

The S2 attempt at0cd3c64810ee85959d0206442211cea6e635f600 is **not** a
completed3.1.0 delivery:120test bodies passed, but the widget-suite tearDownAll
failed with Windows sharing violation32 while deleting its media fixture.
Application compilation/packaging did not run. Preserve its snapshot, output and
logs, the compressed warm Cargo target and genuine codec receipt, and the last
completed3.0.0 delivery at602d462d3309cd5d045f48e01df2dbd924d79af4.

S1 reproduced the same deletion failure using native Flutter3.24.5 on NTFS.
The fixture previously assumed80ms plus fake-clock frame pumping was enough for
real file I/O; it also checked only that an Image widget existed, not that the
file preview had decoded. The test now yields the real event loop between frames,
waits for the visible operation to finish with a10second failure deadline, and
asserts a decoded RawImage in both screenshot/pending-upload paths. A finally
block unmounts the preview and evicts its actual provider before fixture deletion.
The existing recursive tearDownAll remains mandatory, with no catch/retry/skip.
Original-file preservation and no-upload assertions remain in place.

Impact is limited to the widget fixture and its pinned profile hash. No runtime
UI, Office/API/portal contracts, dependency/codec/tool/SDK pins, identity, media
retention or product-version changes. Version remains3.1.0 because no3.1.0 EXE has
been produced or hosted. Native S1 widget verification is11/11PASS including
teardown; delivery application/EXE/installation/hosting acceptance remains separate.

The latest forwarded S2 free space is4778434560bytes, below the5368709120byte
cold guard by590274560bytes. Measure fresh space before the corrected attempt;
never weaken the guard or repeat the completed compression/UAC/reboot stages.
A corrected published SHA requires a new owned snapshot/output while preserving
the failed attempt. Reuse compatible existing codecs and application caches;
a test-only correction does not justify another codec bootstrap.
