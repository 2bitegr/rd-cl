import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';
import '../lib/models/exantas_launch_ticket.dart';

void main() {
  test('same-user credential mailbox validates scope and removes only its random ticket', () {
    final ticket = Uuid().v4().replaceAll('-', '');
    final target = 'Exantas.OfficeCallPopup.Handoff.v1.native-$ticket';
    final bytes = utf8.encode(jsonEncode({'api':'https://synthetic.invalid/api/v1', 'peer_id':'222',
      'launch_request_id':'synthetic-launch', 'opaque_locator':'synthetic-locator', 'capability':'synthetic-only'}));
    using((alloc) {
      final c = alloc<CREDENTIAL>();
      c.ref.Type = CRED_TYPE_GENERIC;
      c.ref.TargetName = target.toNativeUtf16(allocator:alloc);
      c.ref.Persist = CRED_PERSIST_LOCAL_MACHINE;
      c.ref.CredentialBlobSize = bytes.length;
      final blob = alloc<Uint8>(bytes.length);
      blob.asTypedList(bytes.length).setAll(0,bytes);
      c.ref.CredentialBlob = blob;
      expect(CredWrite(c,0),isNot(0));
    });
    try {
      final value = readExantasLaunchTicket(ticket,'https://synthetic.invalid/api/v1','222');
      expect(value['capability'],'synthetic-only');
      expect(value.containsKey('api'),false);
      expect(()=>readExantasLaunchTicket(ticket,'https://other.invalid/api/v1','222'),throwsStateError);
      expect(()=>readExantasLaunchTicket(ticket,'https://synthetic.invalid/api/v1','other'),throwsStateError);
      expect(()=>readExantasLaunchTicket('../bad','https://synthetic.invalid/api/v1','222'),throwsStateError);
    } finally { deleteExantasLaunchTicket(ticket); }
    expect(()=>readExantasLaunchTicket(ticket,'https://synthetic.invalid/api/v1','222'),throwsStateError);
  },skip:!Platform.isWindows);
}
