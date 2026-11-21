import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'platform_model.dart';

// Same Windows user/machine credential store. Only a random lookup ID is public.
Map<String, dynamic> readExantasLaunchTicket(String ticket, String api, String peer) {
  if (Platform.isLinux && RegExp(r'^[a-f0-9]{32}$').hasMatch(ticket)) {
    // Office Call Popup on Ubuntu writes the same JSON to the desktop keyring.
    final stored = bind.mainOfficeReadLaunchTicket(ticket: ticket);
    if (stored.isEmpty) throw StateError('Office launch credential unavailable.');
    return _scopedLaunchTicket(stored, api, peer);
  }
  if (!Platform.isWindows || !RegExp(r'^[a-f0-9]{32}$').hasMatch(ticket)) throw StateError('Invalid Office ticket.');
  return using((alloc) {
    final target = 'Exantas.OfficeCallPopup.Handoff.v1.native-$ticket'.toNativeUtf16(allocator: alloc);
    final pointer = alloc<Pointer<CREDENTIAL>>();
    if (CredRead(target, CRED_TYPE_GENERIC, 0, pointer) == 0) throw StateError('Office launch credential unavailable.');
    try {
      final c = pointer.value.ref;
      if (c.CredentialBlobSize == 0 || c.CredentialBlobSize > 5120) throw StateError('Invalid Office credential size.');
      return _scopedLaunchTicket(utf8.decode(c.CredentialBlob.asTypedList(c.CredentialBlobSize)), api, peer);
    } finally { CredFree(pointer.value); }
  });
}

Map<String, dynamic> _scopedLaunchTicket(String stored, String api, String peer) {
  final row = (jsonDecode(stored) as Map).cast<String, dynamic>();
  if (row['api'] != api.replaceFirst(RegExp(r'/$'), '') || row['peer_id'] != peer) throw StateError('Office ticket scope changed.');
  return {for (final key in ['launch_request_id', 'opaque_locator', 'capability']) key: row[key]};
}

void deleteExantasLaunchTicket(String ticket) {
  if (Platform.isLinux && RegExp(r'^[a-f0-9]{32}$').hasMatch(ticket)) {
    if (!bind.mainOfficeDeleteLaunchTicket(ticket: ticket)) throw StateError('Office launch credential cleanup failed.');
    return;
  }
  if (!Platform.isWindows || !RegExp(r'^[a-f0-9]{32}$').hasMatch(ticket)) return;
  using((alloc) {
    final target = 'Exantas.OfficeCallPopup.Handoff.v1.native-$ticket'.toNativeUtf16(allocator: alloc);
    if (CredDelete(target, CRED_TYPE_GENERIC, 0) == 0 && GetLastError() != 1168) throw StateError('Office launch credential cleanup failed.');
  });
}
