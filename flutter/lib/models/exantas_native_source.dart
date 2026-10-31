import 'dart:convert';
import 'package:http/http.dart' show Response;
import 'exantas_native_auth.dart';

/// The existing RustDesk /sysinfo registration, using only this installation's
/// native identity. Outgoing-only Android does not run the incoming-service sync.
/// Office credentials and target/customer/work identities never go to /sysinfo.
Future<void> prepareAndroidOfficeSource({
  required ExantasNativeIdentity before,
  required Future<ExantasNativeIdentity> Function() current,
  required String nativeApi,
  required String deviceUuid,
  required String version,
  required Future<Response> Function(Uri, Map<String, String>, String) send,
}) async {
  final origin = nativeApiOrigin(nativeApi);
  if (before.actor.isEmpty ||
      before.companion.isEmpty ||
      !RegExp(r'^[0-9]{6,10}$').hasMatch(before.peer) ||
      !RegExp(r'^[a-zA-Z0-9+/_=-]{1,128}$').hasMatch(deviceUuid)) {
    throw StateError('Δεν επιβεβαιώθηκε η ταυτότητα αυτής της συσκευής.');
  }
  if (!before.sameAs(await current()))
    throw StateError('Η σύνδεση Office άλλαξε.');
  final response = await send(
      Uri.parse('$origin/api/sysinfo'),
      const {'content-type': 'application/json'},
      jsonEncode({
        'id': before.peer,
        'uuid': deviceUuid,
        'version': version,
        'os': 'Android',
        'hostname': 'Exantas Support Android',
      }));
  if (!before.sameAs(await current()))
    throw StateError('Η σύνδεση Office άλλαξε.');
  if (response.statusCode != 200 || response.body.trim() != 'SYSINFO_UPDATED') {
    throw StateError(
        'Δεν επιβεβαιώθηκε η καταχώριση του κινητού στο RustDesk. Η σύνδεση Office διατηρείται.');
  }
}
