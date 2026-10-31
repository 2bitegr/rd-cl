import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';
import 'package:flutter_hbb/models/exantas_native_source.dart';

const who = ExantasNativeIdentity('https://office.invalid/api/v1',
    'synthetic-actor', 'never-forward-this', '123456789');
void main() {
  test(
      'outgoing Android registers exact native source via existing sysinfo before native sign-in',
      () async {
    var calls = 0;
    await prepareAndroidOfficeSource(
        before: who,
        current: () async => who,
        nativeApi: 'https://native.invalid/',
        deviceUuid: 'native_uuid=',
        version: '2.0.3',
        send: (uri, headers, body) async {
          calls++;
          expect(uri.toString(), 'https://native.invalid/api/sysinfo');
          expect(headers, {'content-type': 'application/json'});
          expect(body.contains(who.companion), false);
          expect(jsonDecode(body), {
            'id': '123456789',
            'uuid': 'native_uuid=',
            'version': '2.0.3',
            'os': 'Android',
            'hostname': 'Exantas Support Android'
          });
          return Response('SYSINFO_UPDATED', 200);
        });
    expect(calls, 1);
  });
  test(
      'registration rejects incomplete identity and insecure API without any request',
      () async {
    var calls = 0;
    for (final value in [
      who,
      const ExantasNativeIdentity(
          'https://office.invalid', '', '', '123456789'),
      const ExantasNativeIdentity(
          'https://office.invalid', 'actor', 'pair', '192.168.1.1')
    ]) {
      await expectLater(
          prepareAndroidOfficeSource(
              before: value,
              current: () async => value,
              nativeApi: value == who
                  ? 'http://native.invalid'
                  : 'https://native.invalid',
              deviceUuid: 'uuid',
              version: '2',
              send: (_, __, ___) async {
                calls++;
                return Response('SYSINFO_UPDATED', 200);
              }),
          throwsA(anything));
    }
    expect(calls, 0);
  });
  test(
      'HTTP failure or non-authoritative acknowledgement cannot permit native issuance',
      () async {
    for (final r in [
      Response('SYSINFO_UPDATED', 502),
      Response('<html>proxy</html>', 200),
      Response('ID_NOT_FOUND', 200)
    ]) {
      await expectLater(
          prepareAndroidOfficeSource(
              before: who,
              current: () async => who,
              nativeApi: 'https://native.invalid',
              deviceUuid: 'uuid',
              version: '2',
              send: (_, __, ___) async => r),
          throwsStateError);
    }
  });
  test('account/source switch during registration rejects late acknowledgement',
      () async {
    var current = who;
    await expectLater(
        prepareAndroidOfficeSource(
            before: who,
            current: () async => current,
            nativeApi: 'https://native.invalid',
            deviceUuid: 'uuid',
            version: '2',
            send: (_, __, ___) async {
              current = const ExantasNativeIdentity(
                  'https://office.invalid/api/v1',
                  'other',
                  'other-pair',
                  '987654321');
              return Response('SYSINFO_UPDATED', 200);
            }),
        throwsStateError);
  });
  test(
      'lost registration response remains an error, without a fabricated lease',
      () async {
    await expectLater(
        prepareAndroidOfficeSource(
            before: who,
            current: () async => who,
            nativeApi: 'https://native.invalid',
            deviceUuid: 'uuid',
            version: '2',
            send: (_, __, ___) async => throw TimeoutException('synthetic')),
        throwsA(isA<TimeoutException>()));
  });
}
