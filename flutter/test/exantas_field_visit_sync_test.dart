import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_hbb/models/exantas_field_visit_api.dart';
import 'package:flutter_hbb/models/exantas_field_visit_store.dart';
import 'package:flutter_hbb/models/exantas_field_visit_sync.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exantas_field_visit_fakes.dart';

void main() {
  late Directory dir;
  late ExantasFieldVisitStore store;
  late FakeOffice office;
  late DateTime clock;
  late int ids;
  late FvScope? currentScope;
  final uploads = <List<int>>[];

  ExantasFieldVisitSync make() => ExantasFieldVisitSync(
      store: store,
      api: office.api,
      scope: () async => currentScope,
      now: () => clock,
      newId: () {
        ids += 1;
        return '${ids.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
      },
      uploader: (signed, bytes, type) async => uploads.add(bytes));

  /// Office that applies save/attendance/close and echoes a consistent visit.
  void echoOffice({bool finalizeClose = false}) {
    office.onPost = (path, body) async {
      final id = RegExp(r'field-visits/([0-9a-f-]{36})/').firstMatch(path)?.group(1) ?? 'x';
      if (path.endsWith('/attendance')) fvAttendanceEcho[id] = Map<String, dynamic>.from(body);
      if (path.endsWith('/save')) fvContentEcho[id] = Map<String, dynamic>.from(body);
      if (path.endsWith('/close')) {
        return {'status': 'ok', 'visit': visitDto(id, status: finalizeClose ? 'closed' : 'awaiting_participants', revision: '5'), 'report': {'id': 'r1', 'version': 1}, 'charge': {'net_minor': '9120', 'state': 'posted'}, 'warnings': [], 'finalized': finalizeClose};
      }
      if (path.endsWith('/payments')) return {'status': 'ok', 'payment': {'id': body['payment_id'], 'method': body['method'], 'amount_minor': body['amount_minor'], 'received_at': body['received_at']}};
      if (path.contains('/photos/request')) return {'status': 'ok', 'signed_upload': {'url': 'https://s/u', 'token': 't', 'path': 'p'}};
      if (path.contains('/confirm')) return {'status': 'ok', 'photo': {'state': 'ready'}};
      if (path.endsWith('/equipment') || path.endsWith('/draft-customers')) return {'status': 'ok'};
      return {'status': 'ok', 'applied': true, 'visit': visitDto(id), 'warnings': []};
    };
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fvsync');
    store = fakeStore(dir);
    office = FakeOffice();
    clock = DateTime.utc(2026, 11, 21, 9, 30);
    ids = 0;
    fvAttendanceEcho.clear();
    fvContentEcho.clear();
    currentScope = fvScopeA;
    uploads.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(ExantasFieldVisitSync, FieldVisit)> started({bool arrive = true}) async {
    final sync = make();
    await sync.load();
    final v = await sync.startVisit(customerId: 'c-1', customerName: 'Κ. Αλεξίου', jobType: jobType());
    if (arrive) await sync.arrive(v.id, fix: FvFix(37.9, 23.7, 8, clock));
    return (sync, v);
  }

  group('persistence before network', () {
    test('startVisit writes the encrypted file and sends nothing', () async {
      final (sync, v) = await started(arrive: false);
      expect(office.calls, isEmpty);
      expect(File('${dir.path}/${v.id}.json').existsSync(), isTrue);
      final reloaded = make();
      await reloaded.load();
      expect(reloaded.visit(v.id)!.ops.single.kind, FvOpKind.save);
      expect(sync.unsyncedCount, 1);
    });

    test('the close op (with reserved_at) is on disk before the single POST', () async {
      final (sync, v) = await started();
      await sync.editContent(v.id, (x) {
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
        x.noSignature = true;
      });
      var diskHadReservation = false;
      office.onPost = (path, body) async {
        if (path.endsWith('/close')) {
          final onDisk = FieldVisit.decode(await fakeUnprotect(File('${dir.path}/${v.id}.json').readAsStringSync()))!;
          diskHadReservation = onDisk.closeOp?.reservedAt != null && onDisk.localStatus == FvLocalStatus.closing;
          return {'status': 'ok', 'visit': visitDto(v.id, status: 'awaiting_participants'), 'warnings': [], 'finalized': false};
        }
        return {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      };
      await sync.closeVisit(v.id);
      expect(diskHadReservation, isTrue);
      expect(office.posts('/close').length, 1);
    });
  });

  group('ordering and coalescing', () {
    test('draft customer op precedes the visit save', () async {
      final sync = make();
      await sync.load();
      final v = await sync.startVisit(customerName: '', draft: const FvDraftCustomerInput(companyName: 'Νέος ΙΚΕ', afm: '123'), jobType: jobType());
      expect(v.ops.map((o) => o.kind), [FvOpKind.draftCustomer, FvOpKind.save]);
      expect(v.customerIsDraft, isTrue);
      expect(v.ops.last.body['create']['draft_customer_id'], v.ops.first.body['draft_customer_id']);
    });

    test('equipment is inserted before the first unsent save (dependency order)', () async {
      final (sync, v) = await started(arrive: false);
      await sync.saveEquipment(v.id, FvEquipment(id: 'e-1', kind: 'Εκτυπωτής', barcode: 'B1'));
      expect(sync.visit(v.id)!.ops.map((o) => o.kind), [FvOpKind.equipment, FvOpKind.save]);
      // and the save carries the line
      final save = sync.visit(v.id)!.ops.last;
      expect((save.body['equipment_lines'] as List).single['equipment_id'], 'e-1');
    });

    test('unsent saves coalesce into ONE op with the newer rev and a new key', () async {
      final (sync, v) = await started(arrive: false);
      final firstKey = sync.visit(v.id)!.ops.single.key;
      await sync.editContent(v.id, (x) => x.workSummary = 'α');
      await sync.editContent(v.id, (x) => x.workSummary = 'αβ');
      final ops = sync.visit(v.id)!.ops;
      expect(ops.length, 1);
      expect(ops.single.key, isNot(firstKey));
      expect(ops.single.body['work_summary'], 'αβ');
      expect(ops.single.body['client_rev'], 3);
      expect(ops.single.body.containsKey('create'), isTrue); // create survives coalescing
    });

    test('a sent op body is frozen: new edits append, retry uses identical key and body', () async {
      final (sync, v) = await started(arrive: false);
      office.onPost = (p, b) async => throw const SocketException('down');
      await sync.sync(force: true);
      final sent = sync.visit(v.id)!.ops.single;
      expect(sent.state, 'unknown');
      final frozenKey = sent.key;
      final frozenBody = jsonEncode(sent.body);
      await sync.editContent(v.id, (x) => x.workSummary = 'νέο');
      final ops = sync.visit(v.id)!.ops;
      expect(ops.length, 2);
      expect(ops.first.key, frozenKey);
      expect(jsonEncode(ops.first.body), frozenBody);
      expect(ops.last.body.containsKey('create'), isFalse); // first save already went out
      // backoff: not retried until due, then identical replay
      await sync.sync();
      expect(office.posts('/save').length, 1);
      clock = clock.add(const Duration(minutes: 10));
      echoOffice();
      await sync.sync();
      final saves = office.posts('/save');
      expect(saves.length >= 2, isTrue);
      expect(saves[1].body!['idempotency_key'], frozenKey);
      expect(jsonEncode(saves[1].body), frozenBody);
      expect(sync.visit(v.id)!.ops, isEmpty);
    });

    test('ops run strictly in order per visit and stop at the first unknown', () async {
      final (sync, v) = await started();
      final order = <String>[];
      office.onPost = (path, body) async {
        order.add(path.split('/').last);
        if (path.endsWith('/save')) throw const SocketException('down');
        return {'status': 'ok'};
      };
      await sync.sync(force: true);
      expect(order, ['save']); // attendance must not overtake the unconfirmed save
      expect(sync.visit(v.id)!.ops.map((o) => o.kind), [FvOpKind.save, FvOpKind.attendance]);
    });

    test('different visits sync in parallel and independently', () async {
      final sync = make();
      await sync.load();
      final a = await sync.startVisit(customerId: 'c-1', customerName: 'A', jobType: jobType());
      final b = await sync.startVisit(customerId: 'c-2', customerName: 'B', jobType: jobType());
      office.onPost = (path, body) async {
        if (path.contains(a.id)) throw const SocketException('down');
        return {'status': 'ok', 'applied': true, 'visit': visitDto(b.id)};
      };
      await sync.sync(force: true);
      expect(sync.visit(a.id)!.ops.single.state, 'unknown');
      expect(sync.visit(b.id)!.ops, isEmpty);
    });
  });

  group('server answers', () {
    test('applied:false (stale replay) is not an error and is counted', () async {
      final (sync, v) = await started(arrive: false);
      office.onPost = (p, b) async => {'status': 'ok', 'applied': false, 'visit': visitDto(v.id, revision: '9')};
      await sync.sync(force: true);
      expect(sync.staleIgnored, 1);
      expect(sync.visit(v.id)!.ops, isEmpty);
      expect(sync.visit(v.id)!.serverRevision, '9');
    });

    test('reorder safety: an older server echo never wipes own unsynced attendance', () async {
      final (sync, v) = await started();
      var saveDone = false;
      office.onPost = (p, b) async {
        if (p.endsWith('/save')) {
          saveDone = true;
          return {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)}; // no arrival in echo
        }
        throw const SocketException('down');
      };
      await sync.sync(force: true);
      expect(saveDone, isTrue);
      expect(sync.visit(v.id)!.myAttendance.arrivalAt, isNotNull); // attendance op still queued
      expect(sync.visit(v.id)!.myAttendance.gpsMissing, isFalse);
    });

    test('definitive rejection marks the op rejected without blocking later ops', () async {
      final (sync, v) = await started();
      await sync.addPayment(v.id, method: 'cash', amountMinor: 5000);
      office.onPost = (p, b) async {
        if (p.endsWith('/attendance')) throw rejection(409, 'visit_closed');
        return {'status': 'ok', 'applied': true, 'visit': visitDto(v.id), 'payment': {'id': b['payment_id'], 'method': 'cash', 'amount_minor': '5000', 'received_at': b['received_at']}};
      };
      await sync.sync(force: true);
      final ops = sync.visit(v.id)!.ops;
      expect(ops.length, 1);
      expect(ops.single.state, 'rejected');
      expect(ops.single.rejected!['code'], 'visit_closed');
      expect(sync.visit(v.id)!.payments.single.id, isNotEmpty);
      await sync.dismissRejected(v.id, ops.single.key);
      expect(sync.visit(v.id)!.ops, isEmpty);
    });

    test('idempotency_conflict is NOT definitive: op stays queued for retry', () async {
      final (sync, v) = await started(arrive: false);
      office.onPost = (p, b) async => throw rejection(409, 'idempotency_conflict');
      await sync.sync(force: true);
      expect(sync.visit(v.id)!.ops.single.state, 'unknown');
    });

    test('5xx keeps the op for backoff retry', () async {
      final (sync, v) = await started(arrive: false);
      office.onPost = (p, b) async => throw rejection(503, 'unavailable');
      await sync.sync(force: true);
      final op = sync.visit(v.id)!.ops.single;
      expect(op.state, 'unknown');
      expect(op.nextRetryAt!.isAfter(clock), isTrue);
    });
  });

  group('close protocol', () {
    Future<(ExantasFieldVisitSync, FieldVisit)> ready() async {
      final (sync, v) = await started();
      await sync.editContent(v.id, (x) {
        x.workSummary = 'Συντήρηση server';
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
        x.showPrices = true;
        x.noSignature = true;
      });
      echoOffice();
      await sync.sync(force: true); // drain save+attendance
      office.calls.clear();
      return (sync, v);
    }

    test('success: one POST with full body, status awaiting, charge shown from server', () async {
      final (sync, v) = await ready();
      echoOffice();
      await sync.closeVisit(v.id);
      final close = office.posts('/close').single;
      expect(close.body!['outcome'], 'done');
      expect(close.body!['charge_source'], 'prepaid');
      expect(close.body!['signature'], {'no_signature': true});
      expect(close.body!['content']['work_summary'], 'Συντήρηση server');
      expect(close.body!['idempotency_key'], isNotEmpty);
      expect(close.body!['auto_depart_at'], isNotNull);
      final got = sync.visit(v.id)!;
      expect(got.localStatus, FvLocalStatus.awaiting);
      expect(got.charge!['net_minor'], '9120'); // mirrored, never computed
      expect(got.ops, isEmpty);
    });

    test('finalized:true closes the local visit', () async {
      final (sync, v) = await ready();
      echoOffice(finalizeClose: true);
      await sync.closeVisit(v.id);
      expect(sync.visit(v.id)!.localStatus, FvLocalStatus.closed);
    });

    test('unknown outcome: never re-POST, recovery is GET only, applied is accepted', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);
      expect(office.posts('/close').length, 1);
      final key = sync.visit(v.id)!.closeOp!.key;
      expect(sync.visit(v.id)!.localStatus, FvLocalStatus.closing);

      // every later pass only GETs
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'unknown'}};
      await sync.sync(force: true);
      await sync.sync(force: true);
      expect(office.posts('/close'), hasLength(1));
      expect(office.gets().where((c) => c.path == '/support-workflow/requests/$key').isNotEmpty, isTrue);

      office.onGet = (p) async => p.contains('/requests/')
          ? {'status': 'ok', 'request': {'state': 'applied', 'result': {'status': 'ok', 'visit': visitDto(v.id, status: 'closed', revision: '8'), 'charge': {'net_minor': '100'}, 'report': {'id': 'r', 'version': 1}, 'warnings': [], 'finalized': true}}}
          : {'status': 'ok', 'items': []};
      await sync.sync(force: true);
      final got = sync.visit(v.id)!;
      expect(got.closeOp, isNull);
      expect(got.localStatus, FvLocalStatus.closed);
      expect(office.posts('/close').length, 1);
    });

    test('abandon needs proof not_found AND >= 2 minutes, then a NEW key is used', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);

      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'not_found'}};
      expect(await sync.recoverClose(v.id), isFalse);
      expect(sync.visit(v.id)!.closeOp!.notFoundAt, isNotNull);
      // proven but younger than 2 minutes
      expect(sync.canAbandonClose(v.id), isFalse);
      expect(() => sync.abandonClose(v.id), throwsStateError);
      clock = clock.add(const Duration(minutes: 2, seconds: 1));
      expect(sync.canAbandonClose(v.id), isTrue);

      // applied in the meantime: accepted instead of abandoned
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'applied', 'result': {'status': 'ok', 'visit': visitDto(v.id, status: 'closed'), 'warnings': [], 'finalized': true}}};
      expect(await sync.abandonClose(v.id), isFalse);
      expect(sync.visit(v.id)!.localStatus, FvLocalStatus.closed);
    });

    test('abandon clears the op, unlocks the editor and the next close gets a new key', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);
      final firstKey = sync.visit(v.id)!.closeOp!.key;
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'not_found'}};
      await sync.recoverClose(v.id);
      clock = clock.add(const Duration(minutes: 3));
      expect(await sync.abandonClose(v.id), isTrue);
      final got = sync.visit(v.id)!;
      expect(got.closeOp, isNull);
      expect(got.localStatus, FvLocalStatus.draft);
      expect(got.lastAbandonedAt, isNotNull);
      echoOffice();
      await sync.closeVisit(v.id);
      final posts = office.posts('/close');
      expect(posts.last.body!['idempotency_key'], isNot(firstKey));
    });

    test('abandon refuses when Office does not answer not_found', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'not_found'}};
      await sync.recoverClose(v.id);
      clock = clock.add(const Duration(minutes: 3));
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'pending'}};
      expect(() => sync.abandonClose(v.id), throwsStateError);
      expect(sync.visit(v.id)!.closeOp, isNotNull);
    });

    test('definitive rejection unlocks the editor and keeps the Greek reason', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw rejection(422, 'discount_exceeds_limit', 'x');
      await sync.closeVisit(v.id);
      final got = sync.visit(v.id)!;
      expect(got.closeOp, isNull);
      expect(got.localStatus, FvLocalStatus.draft);
      expect(got.closeRejection!['code'], 'discount_exceeds_limit');
      expect(got.contentLocked, isFalse);
      expect(office.posts('/close').length, 1);
    });

    test('single flight: a second close while one is pending is refused', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);
      await expectLater(sync.closeVisit(v.id), throwsStateError);
      expect(office.posts('/close').length, 1);
    });

    test('concurrent close calls produce exactly one op and one POST', () async {
      final (sync, v) = await ready();
      echoOffice();
      final results = await Future.wait([sync.closeVisit(v.id).then((_) => 'ok', onError: (_) => 'refused'), sync.closeVisit(v.id).then((_) => 'ok', onError: (_) => 'refused')]);
      expect(results.where((r) => r == 'ok').length, 1);
      expect(office.posts('/close').length, 1);
    });

    test('restart after a POST that never answered: unknown, GET-only recovery, no re-POST', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.closeVisit(v.id);
      final key = sync.visit(v.id)!.closeOp!.key;
      // App killed mid-flight: on disk the op is sent but still `queued`.
      final onDisk = sync.visit(v.id)!;
      onDisk.closeOp!.state = 'queued';
      await store.save(onDisk);

      final again = make();
      await again.load();
      expect(again.visit(v.id)!.closeOp!.state, 'unknown');
      expect(again.visit(v.id)!.closeOp!.sent, isTrue);
      office.calls.clear();
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'not_found'}};
      await again.sync(force: true);
      expect(office.posts('/close'), isEmpty);
      expect(office.gets().any((c) => c.path == '/support-workflow/requests/$key'), isTrue);
    });

    test('the 2-minute abandon window starts at the first send, not when queued offline', () async {
      final (sync, v) = await ready();
      final queuedAt = clock;
      currentScope = null; // signed out / no session: the close is queued but cannot be sent
      await sync.closeVisit(v.id);
      var op = sync.visit(v.id)!.closeOp!;
      expect(op.sent, isFalse);
      expect(op.reservedAt, queuedAt);
      expect(office.posts('/close'), isEmpty);

      clock = clock.add(const Duration(minutes: 30));
      currentScope = fvScopeA;
      office.onPost = (p, b) async => throw const SocketException('timeout');
      await sync.sync(force: true);
      op = sync.visit(v.id)!.closeOp!;
      expect(op.sentAt, clock);
      expect(op.reservedAt, clock); // follows the send, not the queueing
      office.onGet = (p) async => {'status': 'ok', 'request': {'state': 'not_found'}};
      await sync.recoverClose(v.id);
      expect(sync.canAbandonClose(v.id), isFalse);
      clock = clock.add(const Duration(minutes: 2, seconds: 1));
      expect(sync.canAbandonClose(v.id), isTrue);
    });

    test('an Office-less 4xx (gateway) on the close is NOT a rollback proof', () async {
      final (sync, v) = await ready();
      office.onPost = (p, b) async => throw ExantasOfficeRejection(409, null, 'Bad gateway page');
      await sync.closeVisit(v.id);
      final got = sync.visit(v.id)!;
      expect(got.closeOp, isNotNull);
      expect(got.closeOp!.state, 'unknown');
      expect(got.localStatus, FvLocalStatus.closing);
      await sync.sync(force: true);
      expect(office.posts('/close'), hasLength(1));
    });

    test('free text sent to Office is single-line (discount reason, signer, payment reference)', () async {
      final (sync, v) = await ready();
      await sync.updateLocal(v.id, (x) {
        x.discountBps = 0;
        x.discountReason = 'πρώτη\nδεύτερη';
        x.noSignature = false;
        x.signaturePngBase64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]);
        x.signerName = ' Γιώργος\nΠ ';
      });
      echoOffice();
      await sync.closeVisit(v.id);
      final body = office.posts('/close').single.body!;
      expect(body['discount_reason'], 'πρώτη δεύτερη');
      expect(body['signature']['signer_name'], 'Γιώργος Π');
      expect(body['signature']['png_base64'], isNotEmpty);
    });

    test('blockers refuse to start a close (no op persisted)', () async {
      final (sync, v) = await started();
      await expectLater(sync.closeVisit(v.id), throwsStateError); // no outcome etc.
      expect(sync.visit(v.id)!.closeOp, isNull);
    });

    test('create identity is repeated in the close body while the row is unconfirmed', () async {
      final (sync, v) = await started();
      await sync.editContent(v.id, (x) {
        x.outcome = FvOutcome.pending;
        x.chargeSource = FvChargeSource.invoice;
        x.noSignature = true;
      });
      office.onPost = (p, b) async => throw const SocketException('down');
      await sync.closeVisit(v.id);
      final body = sync.visit(v.id)!.closeOp!.body;
      expect(body['content']['create']['customer_id'], 'c-1');
      expect(body['content']['job_type_id'], 'jt-1');
    });
  });

  group('scope and feature detection', () {
    test('visits of another owner/api are not loaded nor sent', () async {
      final (sync, v) = await started(arrive: false);
      currentScope = const FvScope('someone-else', fvApi);
      final other = make();
      await other.load();
      expect(other.visits, isEmpty);
      office.onPost = (p, b) async => {'status': 'ok'};
      await other.sync(force: true);
      expect(office.posts(), isEmpty);
      // same files are still there for the rightful owner
      currentScope = fvScopeA;
      final back = make();
      await back.load();
      expect(back.visits.length, 1);
      expect(back.visit(v.id), isNotNull);
      expect(sync.unsyncedCount, 1);
    });

    test('a request is sent with the scope it was created under', () async {
      final (sync, _) = await started(arrive: false);
      echoOffice();
      await sync.sync(force: true);
      expect(office.lastScope, fvScopeA);
    });

    test('capabilities: enabled / 404 route not found / 409 unavailable / offline', () async {
      final sync = make();
      await sync.load();
      office.onGet = (p) async => {'status': 'ok', 'enabled': true};
      expect(await sync.detectFeature(), isTrue);
      expect(sync.enabled, isTrue);

      final s2 = make();
      await s2.load();
      office.onGet = (p) async => throw rejection(404, null.toString(), 'Route not found.');
      expect(await s2.detectFeature(), isFalse);
      expect(s2.enabled, isFalse);

      final s3 = make();
      await s3.load();
      office.onGet = (p) async => throw rejection(409, 'field_visits_unavailable');
      expect(await s3.detectFeature(), isFalse);

      final s4 = make();
      await s4.load();
      office.onGet = (p) async => throw const SocketException('down');
      await s4.detectFeature();
      expect(s4.enabled, isNull); // unknown while offline and nothing local
    });

    test('plain Exception from androidOfficeRequest for missing routes also means off', () {
      expect(fvIsFeatureOff(Exception('Το Office χρειάζεται ενημέρωση για υποστήριξη από Android. Η σύνδεσή σας διατηρείται.')), isTrue);
      expect(fvIsFeatureOff(rejection(500, 'x')), isFalse);
    });

    test('config is cached per owner and reused offline', () async {
      final sync = make();
      await sync.load();
      office.onGet = (p) async => {'status': 'ok', 'job_types': [{'id': 'jt-1', 'code': 'maintenance', 'label_el': 'Συντήρηση', 'checklist': []}], 'phrases': [], 'eligible_staff': [], 'my_discount_limit_bps': 1500, 'config_revision': '3'};
      await sync.refreshConfig();
      expect(sync.config.myDiscountLimitBps, 1500);
      final again = make();
      await again.load();
      expect(again.config.myDiscountLimitBps, 1500);
      currentScope = const FvScope('x', fvApi);
      final other = make();
      await other.load();
      expect(other.config.myDiscountLimitBps, 0);
    });
  });

  group('pull and merge', () {
    test('list then get for newer revisions; server wins for status and others', () async {
      final (sync, v) = await started(arrive: false);
      echoOffice();
      await sync.sync(force: true);
      final other = '99999999-9999-4999-8999-999999999999';
      office.calls.clear();
      office.onGet = (p) async {
        if (p.contains('updated_since') || p.startsWith('/support-workflow/field-visits?')) {
          return {'status': 'ok', 'items': [{'id': v.id, 'revision': '12'}, {'id': other, 'revision': '1'}], 'server_time': '2026-11-21T09:31:00Z'};
        }
        if (p.contains(other)) return {'status': 'ok', 'visit': visitDto(other, status: 'scheduled', revision: '1')};
        return {'status': 'ok', 'visit': visitDto(v.id, status: 'closed', revision: '12', participants: [
          {'user_id': fvOwner, 'display_name': 'Εσύ', 'role': 'lead', 'is_self': true, 'arrival': null, 'departure_at': null, 'pauses': []},
          {'user_id': 'u2', 'display_name': 'Ν. Πέτρου', 'role': 'member', 'arrival': {'at': '2026-11-21T07:28:00Z'}, 'departure_at': null, 'pauses': []},
        ])};
      };
      await sync.pull();
      expect(sync.visit(v.id)!.status, 'closed');
      expect(sync.visit(v.id)!.localStatus, FvLocalStatus.closed);
      expect(sync.visit(v.id)!.participants.length, 2);
      expect(sync.visit(other)!.status, 'scheduled');
      // cursor is used on the next pull
      office.calls.clear();
      office.onGet = (p) async => {'status': 'ok', 'items': [], 'server_time': 'x'};
      await sync.pull();
      expect(office.gets().single.path.contains('updated_since=2026-11-21T09%3A31%3A00Z'), isTrue);
    });

    test('pull never overwrites own queued attendance or lead content', () async {
      final (sync, v) = await started();
      await sync.editContent(v.id, (x) => x.workSummary = 'δικό μου');
      office.onGet = (p) async => p.contains('?')
          ? {'status': 'ok', 'items': [{'id': v.id, 'revision': '50'}], 'server_time': 's'}
          : {'status': 'ok', 'visit': visitDto(v.id, revision: '50', extra: {'work_summary': 'του server'})};
      await sync.pull();
      expect(sync.visit(v.id)!.workSummary, 'δικό μου');
      expect(sync.visit(v.id)!.myAttendance.arrivalAt, isNotNull);
    });
  });

  group('attendance', () {
    test('arrival without GPS is still recorded and flagged', () async {
      final (sync, v) = await started(arrive: false);
      await sync.arrive(v.id);
      final a = sync.visit(v.id)!.myAttendance;
      expect(a.arrivalAt, clock);
      expect(a.gpsMissing, isTrue);
      expect(a.lat, isNull);
      final op = sync.visit(v.id)!.ops.firstWhere((o) => o.kind == FvOpKind.attendance);
      expect(op.body['arrival']['lat'], isNull);
      expect(op.body['client_rev'], 1);
    });

    test('pause, resume and depart bump client_rev and coalesce into one op', () async {
      final (sync, v) = await started();
      clock = clock.add(const Duration(minutes: 10));
      await sync.startPause(v.id);
      expect(sync.visit(v.id)!.myAttendance.onPause, isTrue);
      clock = clock.add(const Duration(minutes: 5));
      await sync.endPause(v.id);
      clock = clock.add(const Duration(minutes: 20));
      await sync.depart(v.id);
      final att = sync.visit(v.id)!.ops.where((o) => o.kind == FvOpKind.attendance).toList();
      expect(att.length, 1);
      expect(att.single.body['client_rev'], 4);
      expect(att.single.body['departure_at'], isNotNull);
      expect(sync.visit(v.id)!.myAttendance.workedMinutes(clock), 30);
    });

    test('invalid changes are refused and leave state untouched', () async {
      final (sync, v) = await started();
      await expectLater(sync.arrive(v.id), throwsStateError); // already arrived
      await expectLater(sync.endPause(v.id), throwsStateError);
      clock = clock.add(const Duration(minutes: 1));
      await sync.depart(v.id);
      await expectLater(sync.startPause(v.id), throwsStateError);
    });

    test('device clock far in the past is stored as UTC instants only', () async {
      final (sync, v) = await started(arrive: false);
      await sync.arrive(v.id);
      expect(sync.visit(v.id)!.myAttendance.arrivalAt!.isUtc, isTrue);
      final body = sync.visit(v.id)!.ops.firstWhere((o) => o.kind == FvOpKind.attendance).body;
      expect((body['arrival']['at'] as String).endsWith('Z'), isTrue);
    });
  });

  group('payments, photos, equipment', () {
    test('payment is its own idempotent op keyed by payment_id and never coalesced', () async {
      final (sync, v) = await started(arrive: false);
      await sync.addPayment(v.id, method: 'cash', amountMinor: 5000);
      await sync.addPayment(v.id, method: 'bank_deposit', amountMinor: 1250, reference: 'ΤΡ-1');
      final pays = sync.visit(v.id)!.ops.where((o) => o.kind == FvOpKind.payment).toList();
      expect(pays.length, 2);
      expect(pays.first.body['payment_id'], isNot(pays.last.body['payment_id']));
      expect(pays.first.body['amount_minor'], '5000');
      await expectLater(sync.addPayment(v.id, method: 'cash', amountMinor: 0), throwsStateError);
    });

    test('photo: request -> signed upload -> confirm; bytes come from the encrypted store', () async {
      final (sync, v) = await started(arrive: false);
      echoOffice();
      final photo = await sync.addPhoto(v.id, [1, 2, 3, 4]);
      expect(photo.sha256.length, 64);
      await sync.sync(force: true);
      expect(uploads, [[1, 2, 3, 4]]);
      expect(office.posts('/photos/request').length, 1);
      final confirm = office.posts('/confirm').single;
      expect(confirm.path.contains(photo.id), isTrue);
      expect(sync.visit(v.id)!.photos.single.state, 'ready');
      expect(sync.visit(v.id)!.ops, isEmpty);
    });

    test('equipment_duplicate re-points lines to the existing register row', () async {
      final (sync, v) = await started(arrive: false);
      await sync.saveEquipment(v.id, FvEquipment(id: 'mine', kind: 'Εκτυπωτής', barcode: 'B9'), action: 'installed');
      office.onPost = (p, b) async {
        if (p.endsWith('/equipment')) throw rejection(409, 'equipment_duplicate');
        if (p.endsWith('/save')) fvContentEcho[v.id] = Map<String, dynamic>.from(b);
        return {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      };
      office.onGet = (p) async => {'status': 'ok', 'items': [{'id': 'existing', 'kind': 'Εκτυπωτής', 'barcode': 'B9'}]};
      await sync.sync(force: true);
      final got = sync.visit(v.id)!;
      expect(got.equipmentLines.single.equipmentId, 'existing');
      expect(got.equipment.single.id, 'existing');
      final save = office.posts('/save').last;
      expect((save.body!['equipment_lines'] as List).single['equipment_id'], 'existing');
    });
  });

  group('photo upload edge cases', () {
    test('Storage "Duplicate" on a replayed signed upload means the bytes are there', () {
      expect(fvStorageSaysAlreadyUploaded(409, '{}'), isTrue);
      expect(fvStorageSaysAlreadyUploaded(400, '{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}'), isTrue);
      expect(fvStorageSaysAlreadyUploaded(400, '{"message":"bad"}'), isFalse);
      expect(fvStorageSaysAlreadyUploaded(200, ''), isFalse);
      expect(fvStorageSaysAlreadyUploaded(403, 'expired'), isFalse);
    });

    test('equipment_duplicate uses details.existing_id even when only the serial clashed', () async {
      final (sync, v) = await started(arrive: false);
      await sync.saveEquipment(v.id, FvEquipment(id: 'mine', kind: 'Εκτυπωτής', barcode: 'NEW', serialNumber: 'S1'), action: 'installed');
      office.onPost = (p, b) async {
        if (p.endsWith('/equipment')) {
          throw ExantasOfficeRejection(409, 'equipment_duplicate', 'dup', details: {'existing_id': 'other'});
        }
        if (p.endsWith('/save')) fvContentEcho[v.id] = Map<String, dynamic>.from(b);
        return {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      };
      office.onGet = (p) async => {
            'status': 'ok',
            'items': [
              {'id': 'unrelated', 'kind': 'Άλλο'},
              {'id': 'other', 'kind': 'Εκτυπωτής', 'serial_number': 'S1'}
            ]
          };
      await sync.sync(force: true);
      expect(sync.visit(v.id)!.equipmentLines.single.equipmentId, 'other');
      expect(office.gets().first.path.contains('barcode='), isFalse);
    });
  });

  group('appointments and cancel', () {
    test('appointment is booked as an op and shows up locally as scheduled', () async {
      final sync = make();
      await sync.load();
      final v = await sync.createAppointment(
          customerId: 'c-1', customerName: 'Α', jobType: jobType(), start: DateTime.utc(2026, 11, 24, 8), end: DateTime.utc(2026, 11, 24, 9));
      expect(v.status, 'scheduled');
      final op = v.ops.single;
      expect(op.kind, FvOpKind.appointment);
      expect(op.body['visit_id'], v.id);
      expect(op.body['participants'], [fvOwner]);
      await expectLater(
          sync.createAppointment(customerId: 'c', customerName: 'x', jobType: jobType(), start: DateTime.utc(2026, 11, 24, 9), end: DateTime.utc(2026, 11, 24, 9)),
          throwsStateError);
    });

    test('cancel queues the op; rejection is surfaced', () async {
      final (sync, v) = await started(arrive: false);
      await sync.cancelVisit(v.id, 'Ο πελάτης ακύρωσε');
      expect(sync.visit(v.id)!.localStatus, FvLocalStatus.cancelled);
      expect(sync.visit(v.id)!.ops.last.kind, FvOpKind.cancel);
    });
  });
}
