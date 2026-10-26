import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/exantas_lifecycle_queue.dart';

Map<String, dynamic> record(String id, {String owner = 'tech', String native = '123'}) => {
  'event_id': id, 'local_session': 'peer:flutter-session', 'owner': owner,
  'api': 'https://synthetic.invalid/api/v1', 'from_peer': '111', 'peer_id': '222',
  'rustdesk_session_id': native, 'started_at': '2026-10-23T09:00:00Z',
  'ended_at': '2026-10-23T09:10:00Z', 'acknowledged': false,
};
Map<String, dynamic> ack(Map<String, dynamic> r) => {
  'status': 'ok', 'recorded': true, 'event_id': r['event_id'], 'remote_session_id': 'remote-source',
};
void main() {
  const api = 'https://synthetic.invalid/api/v1';
  test('persist failure never advances memory or acknowledges close', () async {
    final queue = ExantasLifecycleQueue(save: (_) async => throw StateError('disk'), send: (r) async => ack(r));
    await expectLater(queue.capture(record('a')), throwsStateError);
    expect(queue.records, isEmpty);
  });
  test('lost receipt survives restart and retries exact event without new identity', () async {
    final disk = <String, Map<String, dynamic>>{};
    final sent = <Map<String, dynamic>>[];
    Future<void> save(Map<String, dynamic> row) async { disk[row['event_id']] = Map.from(row); }
    final first = ExantasLifecycleQueue(save: save, send: (r) async {
      sent.add(r); throw TimeoutException('ACK lost');
    });
    await first.capture(record('a')); await first.sync('tech', api, '111');
    expect(first.records['a']!['acknowledged'], false);
    final restarted = ExantasLifecycleQueue(save: save, send: (r) async { sent.add(r); return ack(r); });
    restarted.records.addAll(disk);
    await restarted.sync('tech', api, '111');
    expect(sent[0], sent[1]); expect(restarted.records['a']!['acknowledged'], true);
    await restarted.sync('tech', api, '111'); expect(sent.length, 2);
  });
  test('duplicate close preserves first end and cannot reopen acknowledged event', () async {
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async => ack(r));
    await queue.capture(record('a')); await queue.sync('tech', api, '111');
    await queue.capture({...record('a'), 'ended_at': '2026-10-23T09:20:00Z'});
    expect(queue.records['a']!['ended_at'], '2026-10-23T09:10:00Z');
    expect(queue.records['a']!['acknowledged'], true);
    await expectLater(queue.capture(record('a', owner: 'other')), throwsStateError);
    await expectLater(queue.capture(record('a', native: 'different')), throwsStateError);
  });
  test('wrong account/API/peer and zero native ID cannot dispatch', () async {
    var sent = 0;
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async { sent++; return ack(r); });
    await queue.capture(record('a'));
    await queue.sync('other', api, '111'); await queue.sync('tech', 'other', '111'); await queue.sync('tech', api, 'other');
    expect(sent, 0);
    await queue.capture(record('unknown', native: '0'));
    await queue.sync('tech', api, '111'); expect(sent, 1);
    expect(queue.records['unknown']!['acknowledged'], false);
  });
  test('mismatched receipt stays pending; distinct native connections in one tab stay separate', () async {
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async => {...ack(r), 'event_id': 'wrong'});
    await queue.capture(record('a')); await queue.capture(record('b', native: '456'));
    await queue.sync('tech', api, '111'); expect(queue.records.length, 2);
    expect(queue.records.values.every((r) => r['acknowledged'] == false), true);
    expect(queue.error, isNotNull);
  });
  test('receipt persistence failure repeats the same payload instead of losing it', () async {
    var writes = 0, sends = 0;
    final queue = ExantasLifecycleQueue(save: (_) async {
      if (++writes == 2) throw StateError('ACK disk failure');
    }, send: (r) async { sends++; return ack(r); });
    await queue.capture(record('a')); await queue.sync('tech', api, '111');
    expect(queue.records['a']!['acknowledged'], false);
    await queue.sync('tech', api, '111');
    expect(queue.records['a']!['acknowledged'], true); expect(sends, 2);
  });
  test('unresolved early records do not starve later native connections', () async {
    var sends = 0;
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async { sends++; return ack(r); });
    for (var i = 0; i < 31; i++) {
      await queue.capture(record('event-$i', native: i < 20 ? '0' : '$i'));
    }
    await queue.sync('tech', api, '111'); expect(sends, 0);
    await queue.sync('tech', api, '111'); expect(sends, 11);
  });
  test('in-flight duplicate and ACK cannot downgrade each other', () async {
    final pending = Completer<Map<String, dynamic>>();
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (_) => pending.future);
    await queue.capture(record('a')); final sync = queue.sync('tech', api, '111');
    await Future<void>.delayed(Duration.zero);
    await queue.capture({...record('a'), 'ended_at': '2026-10-23T09:20:00Z'});
    pending.complete(ack(record('a'))); await sync;
    expect(queue.records['a']!['acknowledged'], true);
    expect(queue.records['a']!['ended_at'], '2026-10-23T09:10:00Z');
  });
  test('launch binding persists before import, retries exact identity and never changes scope', () async {
    final sent = <Map<String,dynamic>>[];
    var imported = false;
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async => ack(r), bindLaunch: (r) async {
      sent.add(r);
      return {'status':'ok', 'launch_request_id':r['launch']['launch_request_id'],
        'rustdesk_session_id':r['rustdesk_session_id'], 'linked':imported,
        if (imported) 'remote_session_id':'exact-source'};
    });
    final start = {...record('launch'), 'ended_at':null, 'launch':{'launch_request_id':'request','capability':'synthetic-only'}};
    await queue.capture(start);
    await queue.sync('other',api,'111'); expect(sent,isEmpty);
    await queue.sync('tech',api,'111'); expect(queue.records['launch']!['launch_linked'],isNot(true));
    imported = true;
    await queue.sync('tech',api,'111'); expect(sent[0],sent[1]);
    expect(queue.records['launch']!['launch_linked'],true);
    await queue.capture(start); await queue.sync('tech',api,'111'); expect(sent.length,2);
  });
  test('foreign binding receipt and binding failure never acknowledge association or block close', () async {
    final queue = ExantasLifecycleQueue(save: (_) async {}, send: (r) async => ack(r), bindLaunch: (r) async =>
      {'status':'ok','launch_request_id':'different','rustdesk_session_id':r['rustdesk_session_id'],'linked':true,'remote_session_id':'foreign'});
    await queue.capture({...record('a'),'launch':{'launch_request_id':'request'}});
    await queue.sync('tech',api,'111');
    expect(queue.records['a']!['launch_linked'],isNot(true));
    expect(queue.records['a']!['acknowledged'],true);
    expect(queue.error,isNotNull);
  });

}
// The queue is intentionally transport/storage injected: no real HTTP/DPAPI here.
