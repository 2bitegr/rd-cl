import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';

void main() {
 final row = {'id':'33333333-3333-4333-8333-333333333333','peer_id':'1234567890',
   'state':'pending','key_fingerprint':List.filled(64,'a').join()};
 test('installation key persists across technicians and failed network requests', () async {
   var stored = ''; var writes = 0;
   Future<String> read() async => stored;
   Future<void> save(String key) async { stored = key; writes++; }
   final first = await officeInstallationKey(load:read,save:save);
   expect(base64Decode(first),hasLength(32));
   final second = await officeInstallationKey(load:read,save:save);
   expect(second,first);expect(writes,1);
   var another = '';
   final other = await officeInstallationKey(load:() async=>another,save:(key) async {another=key;});
   expect(other,isNot(first));
 });
 test('unreadable or corrupt approved credential is never silently replaced', () async {
   var writes = 0;
   await expectLater(officeInstallationKey(load:()async=>'corrupt',save:(_)async{writes++;}),throwsFormatException);
   expect(writes,0);
   await expectLater(officeInstallationKey(load:()async=>'',save:(_)async{throw StateError('synthetic secure store failure');}),throwsStateError);
 });
 test('approval binds the exact source and fingerprint', () {
   expect(validateOfficeInstallation({'status':'ok','installations':[row]},'1234567890')['state'],'pending');
   for(final bad in [ {...row,'peer_id':'999999'}, {...row,'key_fingerprint':'short'}, {...row,'state':'auto-approved'}, {...row,'id':'not-uuid'} ]) {
     expect(()=>validateOfficeInstallation({'status':'ok','installations':[bad]},'1234567890'),throwsFormatException);
   }
   expect(()=>validateOfficeInstallation({'status':'ok','installations':[row,row]},'1234567890'),throwsFormatException);
 });
 test('v2 lease cannot be downgraded to legacy contract', () {
   const identity=ExantasNativeIdentity('https://office.invalid','actor','pair-token','1234567890');
   final lease={'status':'ok','contract_version':2,'office_user_id':'actor','pairing_id':'pair','peer_id':'1234567890','access_token':'synthetic','expires_at':1240,'native_api_base':'https://native.invalid'};
   expect(validateNativeLease(lease,identity,'https://native.invalid',1000,contractVersion:2)['access_token'],'synthetic');
   expect(()=>validateNativeLease({...lease,'contract_version':1},identity,'https://native.invalid',1000,contractVersion:2),throwsFormatException);
 });
 test('classified installation errors are clear and never display provider secrets', () {
   for(final code in ['native_installation_required','native_installation_conflict','native_installation_busy']) {
     expect(()=>decodeExantasOfficeResponse(409,jsonEncode({'status':code,'message':'private-provider-content'})),throwsA(predicate((e)=>!e.toString().contains('private-provider-content')&&!e.toString().contains('HTTP 502'))));
   }
 });
}
