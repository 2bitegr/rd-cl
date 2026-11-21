import 'dart:io';

import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_hbb/models/exantas_field_visit_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exantas_field_visit_fakes.dart';

FieldVisit sample(String id, {String owner = fvOwner, String api = fvApi}) => FieldVisit(
    id: id, owner: owner, api: api, selfUserId: owner, customerName: 'Μυστικός Πελάτης', workSummary: 'εμπιστευτικό κείμενο');

const idA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const idB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  late Directory dir;
  late ExantasFieldVisitStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fvstore');
    store = fakeStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('one encrypted file per visit; plaintext never on disk', () async {
    await store.save(sample(idA));
    await store.save(sample(idB));
    final names = [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();
    expect(names, ['$idA.json', '$idB.json']);
    final raw = File('${dir.path}/$idA.json').readAsStringSync();
    expect(raw.startsWith('enc:'), isTrue);
    expect(raw.contains('Μυστικός'), isFalse);
    expect(raw.contains('εμπιστευτικό'), isFalse);
    final all = await store.loadAll();
    expect(all.map((v) => v.id).toSet(), {idA, idB});
    expect(all.firstWhere((v) => v.id == idA).workSummary, 'εμπιστευτικό κείμενο');
  });

  test('write goes through a temp file renamed into place; no temp left behind', () async {
    await store.save(sample(idA));
    await store.save(sample(idA)..workSummary = 'v2');
    expect(dir.listSync().any((f) => f.path.endsWith('.tmp')), isFalse);
    expect((await store.loadAll()).single.workSummary, 'v2');
  });

  test('a crash leftover .tmp never replaces or breaks the real file', () async {
    await store.save(sample(idA)..workSummary = 'good');
    File('${dir.path}/$idA.json.tmp').writeAsStringSync('half written');
    final all = await store.loadAll();
    expect(all.single.workSummary, 'good');
    expect(store.corrupt, isEmpty);
  });

  test('corrupt, plaintext and foreign files are tolerated and reported, never deleted', () async {
    await store.save(sample(idA));
    File('${dir.path}/$idB.json').writeAsStringSync('{"visit_id":"$idB"}'); // not encrypted
    File('${dir.path}/cccccccc-cccc-4ccc-8ccc-cccccccccccc.json').writeAsStringSync(await fakeProtect('garbage'));
    File('${dir.path}/readme.json').writeAsStringSync('x');
    final all = await store.loadAll();
    expect(all.map((v) => v.id), [idA]);
    expect(store.corrupt.length, 3);
    expect(File('${dir.path}/$idB.json').existsSync(), isTrue);
    // a later save of the same visit repairs it
    await store.save(sample(idB));
    expect((await store.loadAll()).length, 2);
  });

  test('a file whose name does not match its visit id is rejected', () async {
    final text = await fakeProtect(sample(idB).encode());
    File('${dir.path}/$idA.json').writeAsStringSync(text);
    expect(await store.loadAll(), isEmpty);
    expect(store.corrupt, ['$idA.json']);
  });

  test('ids are validated against path traversal', () async {
    expect(() => store.save(sample('../evil')), throwsStateError);
    expect(() => store.delete('..'), throwsStateError);
    expect(() => store.writeBinary(idA, '../x', [1]), throwsStateError);
  });

  test('binary files (photos) are encrypted and round trip; delete removes everything', () async {
    await store.save(sample(idA));
    await store.writeBinary(idA, 'photo-1', [1, 2, 3, 250]);
    final raw = File('${dir.path}/$idA/photo-1.photo').readAsStringSync();
    expect(raw.startsWith('enc:'), isTrue);
    expect(await store.readBinary(idA, 'photo-1'), [1, 2, 3, 250]);
    expect(await store.readBinary(idA, 'missing'), isNull);
    await store.delete(idA);
    expect(Directory('${dir.path}/$idA').existsSync(), isFalse);
    expect(File('${dir.path}/$idA.json').existsSync(), isFalse);
  });

  test('meta documents are separate from visits', () async {
    await store.writeMeta('pull', {'server_time': 'x'});
    await store.save(sample(idA));
    expect((await store.readMeta('pull'))!['server_time'], 'x');
    expect(await store.readMeta('nope'), isNull);
    expect((await store.loadAll()).length, 1);
  });

  test('scope: only visits of the same owner and API belong', () {
    final v = sample(idA);
    expect(fvBelongsToScope(v, fvOwner, fvApi), isTrue);
    expect(fvBelongsToScope(v, 'other', fvApi), isFalse);
    expect(fvBelongsToScope(v, fvOwner, 'https://other/api'), isFalse);
    expect(fvBelongsToScope(v, '', fvApi), isFalse);
  });
}
