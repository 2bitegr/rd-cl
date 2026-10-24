# Native Office session closure — source implementation

2026-10-23. Source publication prepared over rd-cl51fec73b9941a05a87a7861a1644bf34ccfede07
and Officeb7b6e2d363faedbcb15da53a941dee708025ba5d. Application remains2.0.0+72;
codec/toolchain/lock/icon pins unchanged; application integrity hashes refreshed. No Windows build here.

## Contract and source path

Closing the last actual remote view captures the UTC close event. Home-window
close, moving a tab and removing an additional shared view do not constitute that
connection's end. The existing native last-view predicate remains in force.
RemotePage caches a nonzero native connection ID while connected, retaining it
when the getter becomes0 after disconnect, and begins main IPC delivery before
tearing down the FFI view. Main records the event before acknowledgement.

The new lifecycle queue is separate from v1 report drafts and v2 suppression
markers. Main persists starts/IDs/ends atomically in office-lifecycle under the
existing application-support root; Windows data uses existing DPAPI protection.
Native connections in one Flutter tab have distinct immutable event IDs. Missing
or ambiguous identity is retained/reported, never matched by target/time alone.
Normal restarts recover pending events. Duplicate callbacks preserve the first
close and acknowledged state; bounded rotating batches avoid starvation.
Account/API/source-peer fences prevent dispatch under a different login or host.
HTTP targets the captured API base, not a later mutable configuration value.

POST `/api/v1/rustdesk-companion/sessions/close` requires the existing active
paired companion/role and existing workflow flag. Payload:
`event_id`, `peer_id`, `from_peer`, `rustdesk_session_id`, `ended_at` (UTC).
The new Office1.12.9 receiver selects exactly one already imported audit/provider
session by all identities plus paired actor. Exclusions/suppressions, unknown IDs,
source changes, future/negative clocks and conflicting replay fail closed.
No business session, work link, invoice or charge is created by this endpoint.

A matching ACK contains status=ok, recorded=true, the same event_id and a nonempty
remote_session_id. Only that ACK is persisted as acknowledged. Lost replies repeat
the identical event; the server serializes the source row and verifies a payload
hash. No secret/token is stored in the lifecycle payload. Errors remain visible in
the existing Reports screen. HTTP failures/older API404 keep events locally.

## Time authority

An end may fill a missing remote_sessions.ended_at; the existing generated
column computes duration from the audited start. raw_payload.office_native_close
retains event/hash/client end/server receipt and client_observed provenance.
Timing_quality stays **unverified**. A client clock is not verified automatic
billing evidence and does not finalize work. Existing independently audited end
and quality are never overwritten by the native close.

Audit refresh preserves the client close metadata. An incomplete import cannot
reopen the source or promote client time to verified. A subsequent authoritative
end replaces a client-derived end; normal authoritative time-change guards still
apply afterward. No new schema/DDL/dependency/flag/grant is introduced.

A force kill, power loss or disk failure before durable capture cannot truthfully
supply a window-close timestamp. Keep the error/state and reconcile with server
audit; never synthesize an end from next startup or turn a failed persist into ACK.

## Validation and delivery gates

Office API/core/history/companion/workflow/actual PostgreSQL fixture:80 PASS,
0 SKIP. The real close SQL is exercised against memory-only PostgreSQL with a
generated duration column; paired-authority/replay/conflict/time/exclusion/receipt
and audit precedence checks run. No production DB or service was started.
Seven modified/new Dart files pass tree-sitter syntax checks. Eight injected Dart
queue tests are provided for disk failure, ACK loss/restart, duplicates, owner/API/
peer fences, unknown ID, separate connections and concurrent ACK/callback.
**Dart/Flutter behavioral tests and analyzer NOT_RUN**: no local SDK; official
Dart3.5.4 archive and documented Flutter China mirror both returned HTTP403.
Syntax is not type checking or runtime acceptance. Evidence is outside Git at
Reports/rdcl-native-close-current under Office-Workspace-Artifacts.

Before runtime testing: review/publish BOTH repositories, then user manually deploys
Office API1.12.9 after target checks. Produce the standard single S2 prompt using
both exact published SHAs; S2 synchronizes first, runs all existing guards/Dart
regressions including `flutter test test/exantas_lifecycle_queue_test.dart`, then
builds the Windows installer with the genuine existing codec receipt and warm
application caches. No new codec compilation or dependency changes are justified
by these Dart-only client changes. Preserve the previous verified EXE.

Native acceptance must cover: normal last-window close with correct Office end;
disconnect then close with getter0; two clients simultaneously; reconnect in the
same tab; tab movement/additional shared view and simultaneous shared-view close;
main restart/lost ACK; offline-to-online replay; account switch; disk failure;
late authoritative audit vs incomplete refresh; zero charges/emails/work-finalize
on closure. Actual native GUI, DPAPI, server delivery and installation NOT_RUN.

The standard native build Dart regression list includes the new lifecycle queue
test, so Build -WithExe cannot skip it. This changes the test invocation only;
codec/ABI/toolchain inputs stay unchanged; reviewed application source hashes
are refreshed in windows-native-profile.json. Publication is not native PASS.


## S2 d029c35d result and local type correction — 2026-10-24

User-reported S2 source d029c35d3771be508376a1986251d66d8351fa82: guards89
PASS/1 Linux-only SKIP, Dart70 PASS including all lifecycle cases, verified codec
reuse, Rust/Flutter/EXE compilation PASS. Analyzer exit2 flags a null-returning
catchError handler on Future<MultiWindowCallResult> in remote_page.dart. The
local correction maps the successful IPC result to Future<void> before the void
error handler; durable-main capture still begins before FFI teardown and its
failure remains logged. No IPC success/ACK is invented and no guard is weakened.

The generated installer is BLOCKED, unsigned,24318464 bytes, SHA256
c0ac67646bb75d5e45eaa7a626aaee0b825b4d8af695652685ea9ec6576b7b46.
It lives under the reported S2 Desktop path
Office-Workspace-Artifacts/Builds/rd-cl/2.0.0+72/delivery-s2-d029c35d.
Do not install or advance the completed baseline from a23ec301. Final maintenance
was NOT_RUN; static artifact diagnostics do not override that failed gate.

New confirmed SDK-aware receipt SHA256:
784aba5498e0a84922367ff58e506940c60b445958bc8ceda1ccf0b0e4796572.
Its reported toolchain JSON is beside the blocked EXE:
toolchain-codecs-d029c35d-local.json. Verify these actual bytes/paths on S2 and
reuse matching codecs plus the successful application target. Do not rebuild
FFmpeg due to this source-only type correction. After publication, use a fresh
owned snapshot/delivery for the new SHA, run tests/analyzer/build/packaging and
all maintenance gates. Preserve d029 diagnostics and previous verified delivery.
The report's PE numeric/string version distinction is diagnostic, not permission
to alter product metadata or relax the canonical package verifier on S2.
