import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_device_display.dart';

const scope = ExantasDeviceDisplayScope(
    apiBase: 'https://office.invalid/api/v1',
    deviceId: 'device-a',
    deviceToken: 'synthetic-token',
    peerId: '123456789',
    enabled: true);
Map<String, dynamic> reply() => {
      'status': 'ok',
      'device': <String, dynamic>{
        'id': scope.deviceId,
        'peer_id': scope.peerId,
        'customer_id': 'company-a',
        'customer_name': ' Synthetic Company AE ',
        'label': ' Front desk PC ',
        'device_name': 'Generic device',
        'hostname': 'PC-01',
        'status': 'active',
        'activation_status': 'active',
        'policy': <String, dynamic>{}
      }
    };
ExantasDeviceDisplayScope changed(
        {String? api,
        String? id,
        String? token,
        String? peer,
        bool enabled = true}) =>
    ExantasDeviceDisplayScope(
        apiBase: api ?? scope.apiBase,
        deviceId: id ?? scope.deviceId,
        deviceToken: token ?? scope.deviceToken,
        peerId: peer ?? scope.peerId,
        enabled: enabled);

void main() {
  test('uses the current registered company and user-assigned computer label',
      () {
    final display = parseExantasDeviceDisplay(reply(), scope)!;
    expect(display.companyName, 'Synthetic Company AE');
    expect(display.computerName, 'Front desk PC');
    expect(display.peerId, scope.peerId);
  });
  test(
      'legacy missing labels fall back to the reported host, never a contact or staff name',
      () {
    final value = reply();
    value['device'].addAll({
      'label': null,
      'contact_name': 'Contact only',
      'technician_name': 'Staff only'
    });
    expect(parseExantasDeviceDisplay(value, scope)!.computerName, 'PC-01');
    value['device']['hostname'] = null;
    expect(parseExantasDeviceDisplay(value, scope)!.computerName,
        'Generic device');
    value['device']['device_name'] = null;
    expect(parseExantasDeviceDisplay(value, scope)!.computerName, '');
    value['device']['customer_name'] = null;
    expect(parseExantasDeviceDisplay(value, scope), isNull);
  });
  test(
      'wrong device or peer, revoked/pending and incomplete replies cannot show company data',
      () {
    for (final patch in [
      {'id': 'other-device'},
      {'peer_id': '987654321'},
      {'revoked_at': '2026-11-16'},
      {'status': 'revoked'},
      {'activation_status': 'pending'},
      {
        'policy': {'office_activation_pending': true}
      },
      {'customer_id': null},
      {'customer_name': <String, dynamic>{}},
    ]) {
      final value = reply();
      value['device'].addAll(patch);
      expect(parseExantasDeviceDisplay(value, scope), isNull, reason: '$patch');
    }
    expect(
        parseExantasDeviceDisplay(
            {'status': 'error', 'device': reply()['device']}, scope),
        isNull);
  });
  test('unenrolled, pending or staff scope makes no policy request', () async {
    var calls = 0;
    for (final value in [
      changed(enabled: false),
      changed(token: ''),
      changed(id: ''),
      changed(peer: '')
    ]) {
      expect(
          await readExantasDeviceDisplay(
              readScope: () async => value,
              readPolicy: (_) async {
                calls++;
                return reply();
              }),
          isNull);
    }
    expect(calls, 0);
  });
  test(
      'account, API, credential and peer changes during a lookup discard the response',
      () async {
    for (final after in [
      changed(api: 'https://other.invalid/api/v1'),
      changed(id: 'other'),
      changed(token: 'rotated'),
      changed(peer: '987654321'),
      changed(enabled: false)
    ]) {
      var calls = 0;
      final response = Completer<Map<String, dynamic>>();
      final pending = readExantasDeviceDisplay(
          readScope: () async => calls++ == 0 ? scope : after,
          readPolicy: (before) {
            expect(before, same(scope));
            return response.future;
          });
      response.complete(reply());
      expect(await pending, isNull);
    }
  });
  test(
      'each successful refresh reads current company/device names rather than enrollment metadata',
      () async {
    var value = reply();
    Future<ExantasDeviceDisplay?> load() => readExantasDeviceDisplay(
        readScope: () async => scope, readPolicy: (_) async => value);
    expect((await load())!.companyName, 'Synthetic Company AE');
    value = reply();
    value['device'].addAll(
        {'customer_name': 'Updated Company AE', 'label': 'Updated POS'});
    final current = (await load())!;
    expect(current.companyName, 'Updated Company AE');
    expect(current.computerName, 'Updated POS');
  });
  test(
      'permission denial is preserved rather than retrying enrollment or using old metadata',
      () async {
    var calls = 0;
    await expectLater(
        readExantasDeviceDisplay(
            readScope: () async => scope,
            readPolicy: (_) async {
              calls++;
              throw StateError('synthetic HTTP 403');
            }),
        throwsStateError);
    expect(calls, 1);
  });
}
