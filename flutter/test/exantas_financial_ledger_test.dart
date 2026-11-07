import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_financial_ledger.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';

/// In-memory Office + journal: a request store keyed by idempotency key.
class Fixture {
  DateTime clock = DateTime.utc(2026, 11, 7, 12);
  final records = <String, Map<String, dynamic>>{'e1': {'event_id': 'e1', 'work_item_id': 'work', 'peer_id': 'p', 'from_peer': 'me'}};
  final applied = <String, Map<String, dynamic>>{}; // key -> stored result
  final posts = <Map<String, dynamic>>[];
  final gets = <String>[];
  bool loseResponse = false, applyOnPost = true;
  Object? rejectWith;
  Future<void>? hold;
  late final ledger = ExantasFinancialLedger(
      record: (id) => records[id],
      save: (row, values) async => records[row['event_id']] = {...records[row['event_id']]!, ...values},
      get: (path, row) async {
        gets.add(path);
        final key = path.split('/').last;
        return {'request': applied.containsKey(key) ? {'state': 'applied', 'result': applied[key]} : {'state': 'not_found'}};
      },
      post: (path, body, row) async {
        posts.add({...body});
        if (hold != null) await hold;
        if (rejectWith != null) throw rejectWith!;
        final result = {'status': 'ok', 'item': {'id': 'work', 'support_state': 'finalized'}};
        if (applyOnPost) applied[body['idempotency_key'] as String] = result;
        if (loseResponse) throw StateError('lost response');
        return result;
      },
      requireOwner: (_) async {},
      now: () => clock);
  Map<String, dynamic> get row => records['e1']!;
  Future<void> finalize({String hash = 'h1', DateTime? previewedAt}) => ledger.submit(
      row, {'key': 'android_k${posts.length}${DateTime.now().microsecondsSinceEpoch}', 'work_item_id': 'work'},
      '/support-workflow/items/work/finalize',
      {'preview_hash': hash, 'previewed_at': (previewedAt ?? clock).toIso8601String()},
      spendToken: 'e1:$hash:${previewedAt ?? clock}');
}

void main() {
  test('lost response after success: recovery returns the stored result, no second POST', () async {
    final f = Fixture()..loseResponse = true;
    await expectLater(f.finalize(), throwsStateError);
    expect(f.posts.length, 1);
    final op = f.row['financial_operation'] as Map;
    expect(op['key'], f.posts.single['idempotency_key']);
    expect(op.containsKey('previewed_at'), false);
    expect(f.posts.single.containsKey('previewed_at'), false);
    // A second finalize cannot POST while the operation is unresolved.
    await expectLater(f.finalize(hash: 'h2'), throwsStateError);
    expect(f.posts.length, 1);
    expect(await f.ledger.recover(f.row), true);
    expect(f.posts.length, 1);
    expect(f.row['decision'], 'completed');
    expect(f.row['financial_operation'], isNull);
  });
  test('not_found with a young reservation: no abandon', () async {
    final f = Fixture()..loseResponse = true..applyOnPost = false;
    await expectLater(f.finalize(), throwsStateError);
    f.clock = f.clock.add(const Duration(seconds: 90));
    expect(await f.ledger.recover(f.row), false);
    expect(f.ledger.canAbandon(f.row), false);
    await expectLater(f.ledger.abandon(f.row), throwsStateError);
    expect(f.row['financial_operation'], isNotNull);
    expect(f.posts.length, 1);
  });
  test('not_found with an old reservation: abandon allowed; next finalize uses a fresh key and fresh preview', () async {
    final f = Fixture()..loseResponse = true..applyOnPost = false;
    final oldPreview = f.clock;
    await expectLater(f.finalize(previewedAt: oldPreview), throwsStateError);
    final oldKey = (f.row['financial_operation'] as Map)['key'];
    f.clock = f.clock.add(const Duration(minutes: 3));
    expect(f.ledger.canAbandon(f.row), false); // no not_found proof yet
    expect(await f.ledger.recover(f.row), false);
    expect(f.ledger.canAbandon(f.row), true);
    expect(await f.ledger.abandon(f.row), true);
    expect(f.row['financial_operation'], isNull);
    expect(f.posts.length, 1); // abandon never POSTs
    // The old reviewed preview is stale: it cannot be reused.
    await expectLater(f.finalize(hash: 'h-old', previewedAt: oldPreview), throwsStateError);
    expect(f.posts.length, 1);
    // A fresh preview (taken after abandon) is accepted with a different key.
    f.loseResponse = false; f.applyOnPost = true;
    f.clock = f.clock.add(const Duration(seconds: 5));
    await f.finalize(hash: 'h-new', previewedAt: f.clock);
    expect(f.posts.length, 2);
    expect(f.posts.last['idempotency_key'], isNot(oldKey));
    expect(f.row['decision'], 'completed');
  });
  test('abandon re-checks the server: an applied result is accepted, not abandoned', () async {
    final f = Fixture()..loseResponse = true;
    await expectLater(f.finalize(), throwsStateError);
    // Make the operation look abandonable, as if not_found had been seen earlier.
    final op = f.row['financial_operation'] as Map;
    f.records['e1']!['financial_operation'] = {...op, 'not_found_at': f.clock.toIso8601String()};
    f.clock = f.clock.add(const Duration(minutes: 5));
    expect(await f.ledger.abandon(f.row), false);
    expect(f.row['decision'], 'completed');
    expect(f.posts.length, 1);
  });
  test('definitive rejection (409 stale_preview) is recorded; abandon needs 2 min and a fresh not_found', () async {
    final f = Fixture()..rejectWith = ExantasOfficeRejection(409, 'stale_preview', 'changed');
    await expectLater(f.finalize(), throwsA(isA<ExantasOfficeRejection>()));
    final op = f.row['financial_operation'] as Map;
    expect((op['rejected'] as Map)['code'], 'stale_preview');
    expect(f.ledger.canAbandon(f.row), false);
    f.clock = f.clock.add(const Duration(minutes: 2));
    expect(f.ledger.canAbandon(f.row), true);
    expect(await f.ledger.abandon(f.row), true);
    expect(f.posts.length, 1);
  });
  test('5xx / idempotency_conflict are not definitive', () async {
    expect(ExantasOfficeRejection(502, null, 'x').definitive, false);
    expect(ExantasOfficeRejection(409, 'idempotency_conflict', 'x').definitive, false);
    expect(ExantasOfficeRejection(409, 'stale_preview', 'x').definitive, true);
    final f = Fixture()..rejectWith = ExantasOfficeRejection(502, null, 'bad gateway');
    await expectLater(f.finalize(), throwsA(isA<ExantasOfficeRejection>()));
    expect((f.row['financial_operation'] as Map).containsKey('rejected'), false);
    f.clock = f.clock.add(const Duration(minutes: 10));
    expect(f.ledger.canAbandon(f.row), false);
  });
  test('double tap issues a single POST', () async {
    final f = Fixture();
    final gate = Future<void>.delayed(const Duration(milliseconds: 20));
    f.hold = gate;
    final first = f.finalize();
    final second = f.finalize();
    await expectLater(second, throwsStateError);
    await first;
    expect(f.posts.length, 1);
  });
  test('the same reviewed preview cannot be spent twice', () async {
    final f = Fixture()..loseResponse = false;
    await f.finalize();
    f.records['e1'] = {...f.row, 'financial_operation': null, 'decision': 'later'};
    await expectLater(f.finalize(), throwsStateError);
    expect(f.posts.length, 1);
  });
  test('abandon rule helper', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(exantasAbandonEligible({}, now), false);
    expect(exantasAbandonEligible({'not_found_at': now.toIso8601String()}, now), false);
    expect(exantasAbandonEligible({'reserved_at': now.subtract(const Duration(minutes: 2)).toIso8601String(), 'rejected': {}}, now), true);
  });
}
