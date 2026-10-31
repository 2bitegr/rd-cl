import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';
const identity = ExantasNativeIdentity('https://office.invalid/api/v1','actor','paired-secret','phone');
Map<String,dynamic> grant() => {'status':'ok','contract_version':1,'office_user_id':'actor','pairing_id':'pair',
  'peer_id':'phone','access_token':'synthetic-support-grant','expires_at':1300};
void main() {
  test('expired access grant requires renewal while the durable pairing stays intact', () {
    final lease = validateOfficeStaffLease({...grant(), 'debug': 'not-retained'}, identity, 1000);
    expect(lease.containsKey('debug'), false);
    expect(cachedOfficeStaffToken(lease, identity, 1000),'synthetic-support-grant');
    expect(cachedOfficeStaffToken(lease, identity, 1301),'');
    expect(identity.companion,'paired-secret'); expect(lease['access_token'],'synthetic-support-grant');
  });
  test('renewed grant is bound to actor, API, source and exact persistent pairing', () {
    final lease = validateOfficeStaffLease(grant(), identity, 1000);
    for (final other in [
      const ExantasNativeIdentity('https://other.invalid','actor','paired-secret','phone'),
      const ExantasNativeIdentity('https://office.invalid/api/v1','other','paired-secret','phone'),
      const ExantasNativeIdentity('https://office.invalid/api/v1','actor','new-pair','phone'),
      const ExantasNativeIdentity('https://office.invalid/api/v1','actor','paired-secret','other-phone')]) {
      expect(cachedOfficeStaffToken(lease, other, 1000),'');
    }
  });
  test('offline or revoked renewal never clears login, stores a password or fabricates a token', () async {
    var stores = 0;
    await expectLater(exchangeOfficeStaffLease(before: identity, current: () async => identity,
      request: () async => throw StateError('offline or revoked'), store: (_) async { stores++; }, now: () => 1000),throwsStateError);
    expect(stores,0); expect(identity.companion,'paired-secret');
  });
  test('late renewal after account switch never overwrites the new account', () async {
    var stores = 0;
    await expectLater(exchangeOfficeStaffLease(before: identity,
      current: () async => const ExantasNativeIdentity('https://office.invalid/api/v1','other','new-pair','phone'),
      request: () async => grant(), store: (_) async { stores++; }, now: () => 1000),throwsStateError);
    expect(stores,0);
  });
  test('malformed, foreign or excessive grants cannot become staff authority', () {
    for (final update in [{'office_user_id':'other'},{'peer_id':'other-phone'}, {'expires_at':1000},
      {'expires_at':2000},{'contract_version':2},{'access_token':''}]) {
      expect(() => validateOfficeStaffLease({...grant(),...update},identity,1000),throwsFormatException);
    }
  });
}
