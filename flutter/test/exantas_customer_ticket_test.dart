import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_customer_ticket.dart';
import 'package:flutter_hbb/models/exantas_customer_ticket_store.dart';
import 'package:flutter_hbb/models/exantas_customer_ticket_proxy.dart';

const device = '11111111-1111-4111-8111-111111111111';
const customer = '22222222-2222-4222-8222-222222222222';
const ticketId = '33333333-3333-4333-8333-333333333333';
const fileId = '44444444-4444-4444-8444-444444444444';
const input = {
  'category': 'problem',
  'priority': 'normal',
  'subject': 'Synthetic problem',
  'details': 'Synthetic customer description'
};

class MemoryStore extends ExantasTicketStore {
  Map<String, dynamic>? value;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async =>
      value == null ? null : ticketMap(jsonDecode(jsonEncode(value)));
  @override
  Future<void> write(Map<String, dynamic> next) async {
    if (fail) throw FileSystemException('synthetic disk failure');
    value = ticketMap(jsonDecode(jsonEncode(next)));
  }
}

class FakeTransport extends ExantasTicketTransport {
  String company = customer;
  bool lostCreate = false,
      lostReply = false,
      lostUpload = false,
      uploaded = false;
  bool failReadySave = false;
  int uploads = 0, requests = 0;
  final creates = <Map<String, dynamic>>[], replies = <Map<String, dynamic>>[];
  Map<String, dynamic>? created;
  MemoryStore? store;
  @override
  Future<Map<String, dynamic>> request(
      ExantasTicketIdentity identity, String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    requests++;
    if (path == '/capabilities') {
      return {
        'status': 'ok',
        'enabled': true,
        'contract_version': 1,
        'viewer_id': device,
        'context': {
          'customer_id': company,
          'branch_id': null,
          'customer_name': 'Synthetic company'
        },
        'limits': {
          'files': 5,
          'imageBytes': 10000000,
          'videoBytes': 50000000,
          'totalBytes': 200000000
        }
      };
    }
    if (path.startsWith('/operations/')) {
      return {
        'status': 'ok',
        'found': created != null,
        if (created != null) 'ticket': created
      };
    }
    if (path == '') {
      creates.add(Map.from(body!));
      created = {'id': ticketId, 'reference': 'T-SYNTHETIC', 'status': 'open'};
      if (lostCreate) {
        lostCreate = false;
        throw TimeoutException('synthetic lost ACK');
      }
      return {'status': 'ok', 'ticket': created};
    }
    if (path.endsWith('/messages')) {
      replies.add(Map.from(body!));
      if (lostReply) {
        lostReply = false;
        throw TimeoutException('synthetic reply ACK lost');
      }
      return {'status': 'ok'};
    }
    if (path.endsWith('/complete')) {
      if (!uploaded) {
        throw const ExantasTicketFailure('ticket_file_unavailable',
            status: 409);
      }
      if (failReadySave) {
        failReadySave = false;
        store!.fail = true;
      }
      return {
        'status': 'ok',
        'file': {'id': fileId, 'state': 'ready'}
      };
    }
    if (path.endsWith('/files')) {
      return {
        'status': 'ok',
        'file': {'id': fileId, 'state': 'prepared'},
        'signed_upload': {'url': 'https://storage.invalid/signed-upload'}
      };
    }
    return {'status': 'ok'};
  }

  @override
  Future<void> upload(Uri url, File file, int length, String mediaType,
      {required bool Function() cancelled,
      void Function(int, int)? progress}) async {
    uploads++;
    uploaded = true;
    progress?.call(length, length);
    if (lostUpload) {
      lostUpload = false;
      throw TimeoutException('synthetic lost PUT response');
    }
  }

  @override
  void close() {}
}

ExantasTicketIdentity identity([String token = 'synthetic-device-secret']) =>
    ExantasTicketIdentity('https://office.invalid/api/v1', device, token);
ExantasCustomerTicketClient client(MemoryStore store, FakeTransport transport,
        {Future<ExantasTicketIdentity> Function()? current}) =>
    ExantasCustomerTicketClient(
        identity: identity(),
        current: current ?? (() => Future.value(identity())),
        store: store,
        transport: transport);

void main() {
  test(
      'proxy settings match native defaults and refuse unknown schemes or malformed authentication',
      () {
    expect(ExantasTicketProxy.fromSettings([]), isNull);
    final bare = ExantasTicketProxy.fromSettings(['127.0.0.1:1080', '', ''])!;
    expect(bare.uri.scheme, 'socks5');
    expect(bare.uri.port, 1080);
    expect(
        ExantasTicketProxy.fromSettings(['https://proxy.invalid', '', ''])!
            .uri
            .port,
        443);
    final overridden = ExantasTicketProxy.fromSettings(
        ['http://old:secret@proxy.invalid', 'new', 'replacement'])!;
    expect(overridden.username, 'new');
    expect(overridden.password, 'replacement');
    for (final values in [
      ['file:///tmp/a', '', ''],
      ['socks5://user:@proxy.invalid', '', ''],
      ['http://proxy.invalid/path', '', ''],
      ['http://proxy.invalid?x=1', '', ''],
      ['http://proxy.invalid', 'u', 'x' * 256]
    ]) {
      expect(() => ExantasTicketProxy.fromSettings(values),
          throwsA(isA<ExantasTicketFailure>()));
    }
  });
  test(
      'draft persistence failure starts no request and does not advance memory',
      () async {
    final store = MemoryStore()..fail = true,
        transport = FakeTransport(),
        c = client(store, transport);
    await expectLater(
        c.saveDraft(input, []), throwsA(isA<ExantasTicketFailure>()));
    expect(transport.requests, 0);
    expect(c.draft, isNull);
  });
  test(
      'lost create ACK and restart read back the same ticket without a second create',
      () async {
    final store = MemoryStore(),
        transport = FakeTransport()..lostCreate = true,
        c = client(store, transport);
    await c.refreshCapabilities();
    await c.saveDraft(input, []);
    await expectLater(c.submit(), throwsA(isA<TimeoutException>()));
    expect(store.value!['draft']['attempted'], true);
    final resumed = client(store, transport);
    await resumed.load();
    expect((await resumed.recoverCreate())!['id'], ticketId);
    expect(transport.creates.length, 1);
    expect(resumed.draft!['request_id'], ticketId);
    expect(jsonEncode(store.value).contains(identity().token), false);
  });
  test(
      'retry keeps immutable original payload/nonce and blocks editing unknown outcome',
      () async {
    final store = MemoryStore(),
        transport = FakeTransport()..lostCreate = true,
        c = client(store, transport);
    await c.saveDraft(input, []);
    await expectLater(c.submit(), throwsA(isA<TimeoutException>()));
    await expectLater(c.saveDraft({...input, 'subject': 'Changed'}, []),
        throwsA(isA<ExantasTicketFailure>()));
    await expectLater(c.discardDraft(), throwsA(isA<ExantasTicketFailure>()));
    await c.submit();
    expect(transport.creates[0], transport.creates[1]);
  });
  test(
      'new credentials cannot load another protected draft or accept a late response',
      () async {
    final store = MemoryStore(),
        transport = FakeTransport(),
        c = client(store, transport);
    await c.saveDraft(input, []);
    final changed = ExantasCustomerTicketClient(
        identity: identity('new'),
        current: () => Future.value(identity('new')),
        store: store,
        transport: transport);
    await expectLater(changed.load(), throwsA(isA<ExantasTicketFailure>()));
    var current = identity();
    final fenced =
        client(MemoryStore(), transport, current: () => Future.value(current));
    await fenced.saveDraft(input, []);
    current = identity('changed');
    await expectLater(fenced.submit(), throwsA(isA<ExantasTicketFailure>()));
    expect(transport.creates, isEmpty);
  });
  test('offline draft cannot silently move to another legal customer',
      () async {
    final transport = FakeTransport(), c = client(MemoryStore(), transport);
    await c.refreshCapabilities();
    await c.saveDraft(input, []);
    transport.company = '55555555-5555-4555-8555-555555555555';
    await expectLater(
        c.submit(),
        throwsA(predicate((e) =>
            e is ExantasTicketFailure &&
            e.code == 'ticket_device_scope_changed')));
    expect(transport.creates, isEmpty);
    expect(c.draft!['input'], input);
  });
  test('file limits are enforced before upload, without modifying originals',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-native-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
    final info = await inspectTicketFile(file.path);
    expect(info['byte_size'], 3);
    expect(info['sha256'], hasLength(64));
    expect(await file.readAsBytes(), [1, 2, 3]);
    await expectLater(
        inspectTicketFile(
            (await File('${dir.path}/bad.exe').writeAsBytes([1])).path),
        throwsA(isA<ExantasTicketFailure>()));
    expect(() => checkTicketFileQuota(List.generate(6, (_) => info)),
        throwsA(isA<ExantasTicketFailure>()));
    expect(
        () => checkTicketFileQuota(
            List.generate(3, (_) => {...info, 'byte_size': 100000000})),
        throwsA(isA<ExantasTicketFailure>()));
  });
  test(
      '50 MB video boundary is accepted and overflow rejected before transport',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-video-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/boundary.mp4');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(50000000);
    await handle.close();
    final info = await inspectTicketFile(file.path);
    expect(info['byte_size'], 50000000);
    expect(info['sha256'], hasLength(64));
    final growing = await file.open(mode: FileMode.append);
    await growing.writeByte(0);
    await growing.close();
    await expectLater(
        inspectTicketFile(file.path),
        throwsA(predicate((e) =>
            e is ExantasTicketFailure && e.code == 'invalid_ticket_upload')));
    expect(await file.length(), 50000001);
    checkTicketFileQuota(List.generate(4, (_) => info));
    expect(() => checkTicketFileQuota(List.generate(5, (_) => info)),
        throwsA(isA<ExantasTicketFailure>()));
  });
  test(
      'lost PUT response confirms existing bytes; local ACK save failure resumes without upload',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-upload-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]),
        store = MemoryStore();
    final transport = FakeTransport()
      ..lostUpload = true
      ..store = store
      ..failReadySave = true;
    final c = client(store, transport);
    await c.saveDraft(input, [await inspectTicketFile(file.path)]);
    await c.submit();
    await expectLater(c.uploadPending(), throwsA(isA<ExantasTicketFailure>()));
    expect(transport.uploads, 1);
    store.fail = false;
    final resumed = client(store, transport);
    await resumed.load();
    await resumed.uploadPending();
    expect(transport.uploads, 1);
    expect(resumed.draft!['files'][0]['ready'], true);
    await resumed.finishDraft();
    expect(resumed.draft, isNull);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
  test(
      'changed or missing original bytes cannot be submitted under an old file proof',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-change-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/a.png').writeAsBytes([1, 2, 3]);
    final transport = FakeTransport(), c = client(MemoryStore(), transport);
    await c.saveDraft(input, [await inspectTicketFile(file.path)]);
    await c.submit();
    await file.writeAsBytes([3, 2, 1]);
    await expectLater(c.uploadPending(), throwsA(isA<ExantasTicketFailure>()));
    expect(transport.uploads, 0);
    await expectLater(
        c.reselectFile(0, file.path), throwsA(isA<ExantasTicketFailure>()));
  });
  test(
      'pending reply persists exact text/key and cannot become a different reply after restart',
      () async {
    final store = MemoryStore(),
        transport = FakeTransport()..lostReply = true,
        c = client(store, transport);
    await expectLater(
        c.reply(ticketId, 'Customer reply'), throwsA(isA<TimeoutException>()));
    final resumed = client(store, transport);
    await resumed.load();
    await expectLater(resumed.reply(ticketId, 'Another reply'),
        throwsA(isA<ExantasTicketFailure>()));
    await resumed.reply(ticketId, 'Customer reply');
    expect(transport.replies[0], transport.replies[1]);
    expect(resumed.pendingReply, isNull);
  });
  test(
      'media capabilities reject clear-text, local files, credentials and unknown schemes',
      () {
    for (final value in [
      'http://storage.invalid/a',
      'file:///secret',
      'javascript:alert(1)',
      'https://user:pass@storage.invalid/a'
    ]) {
      expect(() => checkedTicketMediaUrl(value),
          throwsA(isA<ExantasTicketFailure>()));
    }
    expect(
        checkedTicketMediaUrl('https://storage.invalid/private?token=synthetic')
            .scheme,
        'https');
  });
  test(
      'encrypted file store keeps two generations, no plaintext and an exclusive owner',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-store-');
    addTearDown(() => dir.delete(recursive: true));
    ExantasTicketFileStore store() => ExantasTicketFileStore(
        directory: dir,
        scope: identity().scope,
        protectedPrefix: 'synthetic-protected:',
        protect: (value) async =>
            'synthetic-protected:${base64Encode(utf8.encode(value))}',
        unprotect: (value) async => utf8.decode(
            base64Decode(value.substring('synthetic-protected:'.length))));
    final first = store();
    expect(await first.read(), isNull);
    await first.write({
      'scope': identity().scope,
      'subject': 'Private synthetic description'
    });
    await first.write(
        {'scope': identity().scope, 'subject': 'Retained next generation'});
    expect((await first.read())!['subject'], 'Retained next generation');
    final protected =
        await File('${dir.path}/draft.0.protected').readAsString();
    expect(protected.contains('Retained next generation'), false);
    final competing = store();
    await expectLater(competing.read(), throwsA(isA<ExantasTicketFailure>()));
    await first.close();
    final resumed = store();
    expect((await resumed.read())!['subject'], 'Retained next generation');
    await resumed.close();
  });
  test(
      'corrupt encrypted generation fails closed rather than falling back to an old mutable nonce',
      () async {
    final dir = await Directory.systemTemp.createTemp('office-ticket-corrupt-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ExantasTicketFileStore(
        directory: dir,
        scope: identity().scope,
        protectedPrefix: 'protected:',
        protect: (v) async => 'protected:${base64Encode(utf8.encode(v))}',
        unprotect: (v) async => utf8.decode(base64Decode(v.substring(10))));
    await store.read();
    await store.write({'scope': identity().scope, 'attempted': false});
    await store.write({'scope': identity().scope, 'attempted': true});
    await store.close();
    await File('${dir.path}/draft.0.protected').writeAsString('damaged');
    await expectLater(store.read(), throwsA(isA<ExantasTicketFailure>()));
    await store.close();
  });
}
