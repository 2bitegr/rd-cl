import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';

const identity = ExantasNativeIdentity(
    'https://office.invalid', 'actor', 'synthetic-companion', '1234567890');
Map<String, dynamic> valid() => {
      'status': 'ok',
      'contract_version': 1,
      'office_user_id': 'actor',
      'pairing_id': 'pair',
      'peer_id': '1234567890',
      'access_token': 'synthetic-native',
      'expires_at': 1240,
      'native_api_base': 'https://native.invalid'
    };
void main() {
  test('lease is bound to Office source rather than provider-supplied metadata',
      () {
    expect(
        validateNativeLease(
            {...valid(), 'office_api_base': 'https://foreign.invalid'},
            identity,
            'https://native.invalid',
            1000)['office_api_base'],
        identity.apiBase);
  });
  test(
      'native credential requires exact owner, peer, provider and bounded lifetime',
      () {
    expect(
        validateNativeLease(
            valid(), identity, 'https://native.invalid/', 1000)['expires_at'],
        1240);
    for (final change in <Map<String, dynamic>>[
      {'office_user_id': 'other'},
      {'peer_id': 'other'},
      {'pairing_id': ''},
      {'expires_at': 1000},
      {'expires_at': 1331},
      {'expires_at': '1240'},
      {'contract_version': 2},
      {'access_token': ''},
      {'native_api_base': 'https://other.invalid'}
    ]) {
      expect(
          () => validateNativeLease({...valid(), ...change}, identity,
              'https://native.invalid', 1000),
          throwsFormatException);
    }
  });
  test(
      'native API origin cannot be downgraded, redirected or carry credentials',
      () {
    for (final url in [
      'http://native.invalid',
      'https://user:secret@native.invalid',
      'https://native.invalid/api',
      'https://native.invalid?secret=value'
    ]) {
      expect(() => nativeApiOrigin(url), throwsFormatException);
    }
  });
  test(
      'late response after actor, pairing, source or Office change never writes',
      () async {
    for (final other in [
      const ExantasNativeIdentity('https://office.invalid', 'other',
          'synthetic-companion', '1234567890'),
      const ExantasNativeIdentity(
          'https://office.invalid', 'actor', 'other-pairing', '1234567890'),
      const ExantasNativeIdentity('https://office.invalid', 'actor',
          'synthetic-companion', '9999999999'),
      const ExantasNativeIdentity(
          'https://other.invalid', 'actor', 'synthetic-companion', '1234567890')
    ]) {
      int writes = 0;
      await expectLater(
          ExantasNativeAuthFence().exchange(
              before: identity,
              current: () async => other,
              request: () async => valid(),
              store: (_) async {
                writes++;
              },
              nativeApi: 'https://native.invalid',
              now: () => 1000),
          throwsStateError);
      expect(writes, 0);
    }
  });
  test(
      'login, logout and refresh cannot overlap and failure releases the fence',
      () async {
    final fence = ExantasNativeAuthFence();
    final pending = Completer<void>();
    final held = fence.run(() async {
      await pending.future;
    });
    await expectLater(fence.run(() async {}), throwsStateError);
    pending.complete();
    await held;
    await expectLater(fence.run(() async {
      throw StateError('synthetic');
    }), throwsStateError);
    expect(await fence.run(() async => true), isTrue);
  });
  test('unconfirmed request is attempted once and writes nothing', () async {
    int calls = 0, writes = 0;
    await expectLater(
        ExantasNativeAuthFence().exchange(
            before: identity,
            current: () async => identity,
            request: () async {
              calls++;
              throw TimeoutException('synthetic');
            },
            store: (_) async {
              writes++;
            },
            nativeApi: 'https://native.invalid',
            now: () => 1000),
        throwsA(isA<TimeoutException>()));
    expect(calls, 1);
    expect(writes, 0);
  });
}
