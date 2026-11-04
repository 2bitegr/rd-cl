import 'dart:convert';
import 'dart:math';

/// Keep RustDesk numeric and custom IDs intact while retaining the configured
/// self-hosted server. Direct-IP and URI/server overrides bypass provider audit.
String normalizeAndroidPeerId(String input) {
  final id = input.replaceAll(' ', '').trim();
  if (id.isEmpty || id.length > 128 || RegExp(r'[\s.@:/\\?#\x00-\x1f\x7f]').hasMatch(id)) {
    throw const FormatException('Εισάγετε RustDesk ID του υπάρχοντος server.');
  }
  return id;
}


/// The pinned native API acknowledges authenticated logout with HTTP 200/null.
/// An HTML proxy reply or rejected request must not erase the migration token.
bool legacyLogoutConfirmed(int statusCode, String body) {
  if (statusCode != 200) return false;
  try {
    return jsonDecode(body) == null;
  } on FormatException {
    return false;
  }
}

/// Pure native-lease policy. Network/storage adapters live in the companion.
class ExantasNativeIdentity {
  const ExantasNativeIdentity(
      this.apiBase, this.actor, this.companion, this.peer);
  final String apiBase, actor, companion, peer;
  bool sameAs(ExantasNativeIdentity other) =>
      apiBase == other.apiBase &&
      actor == other.actor &&
      companion == other.companion &&
      peer == other.peer;
}

String nativeApiOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('Απαιτείται ασφαλής διεύθυνση RustDesk API.');
  }
  return uri.origin;
}

Map<String, dynamic> validateNativeLease(Map<String, dynamic> value,
    ExantasNativeIdentity identity, String nativeApi, int now, {int contractVersion = 1}) {
  final token = value['access_token'];
  final expiry = value['expires_at'];
  if (value['status'] != 'ok' ||
      value['contract_version'] != contractVersion ||
      value['office_user_id'] != identity.actor ||
      value['peer_id'] != identity.peer ||
      value['pairing_id'] is! String ||
      (value['pairing_id'] as String).isEmpty ||
      token is! String ||
      token.isEmpty ||
      token.length > 8192 ||
      expiry is! int ||
      expiry <= now + 15 ||
      expiry > now + 330 ||
      nativeApiOrigin(value['native_api_base'] is String
              ? value['native_api_base']
              : '') !=
          nativeApiOrigin(nativeApi)) {
    throw const FormatException(
        'Δεν επιβεβαιώθηκε η ταυτότητα σύνδεσης RustDesk.');
  }
  return {
    'office_api_base': identity.apiBase,
    for (final key in [
      'access_token',
      'expires_at',
      'office_user_id',
      'pairing_id',
      'peer_id',
      'native_api_base'
    ])
      key: value[key]
  };
}

/// Serializes login, refresh and logout across companion service instances.
/// Late exchange responses must recheck identity before any credential write.
class ExantasNativeAuthFence {
  bool _busy = false;
  Future<T> run<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('Μια αλλαγή σύνδεσης Office είναι ήδη σε εξέλιξη.');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>> exchange({
    required ExantasNativeIdentity before,
    required Future<ExantasNativeIdentity> Function() current,
    required Future<Map<String, dynamic>> Function() request,
    required Future<void> Function(Map<String, dynamic>) store,
    required String nativeApi,
    required int Function() now,
    int contractVersion = 1,
  }) async {
    final response = await request();
    final lease = validateNativeLease(response, before, nativeApi, now(), contractVersion: contractVersion);
    if (!before.sameAs(await current())) {
      throw StateError('Η σύνδεση Office άλλαξε. Συνδεθείτε ξανά.');
    }
    await store(lease);
    return lease;
  }
}

/// Office's persistent pairing renews short support-only grants; expiration
/// means refresh, never implicit logout or retention of the user's password.
Map<String, dynamic> validateOfficeStaffLease(Map<String, dynamic> value,
    ExantasNativeIdentity identity, int now) {
  if (value['status'] != 'ok' || value['contract_version'] != 1 ||
      value['office_user_id'] != identity.actor || value['peer_id'] != identity.peer ||
      value['pairing_id'] is! String || (value['pairing_id'] as String).isEmpty ||
      value['access_token'] is! String || (value['access_token'] as String).isEmpty ||
      (value['access_token'] as String).length > 8192 || value['expires_at'] is! int ||
      value['expires_at'] <= now + 15 || value['expires_at'] > now + 330) {
    throw const FormatException('Δεν επιβεβαιώθηκε η άδεια υποστήριξης Office.');
  }
  return {for (final key in ['status', 'contract_version', 'office_user_id', 'pairing_id', 'peer_id', 'access_token', 'expires_at']) key: value[key],
    'office_api_base': identity.apiBase, 'companion_token': identity.companion};
}
String cachedOfficeStaffToken(Map<String, dynamic> lease, ExantasNativeIdentity identity, int now) {
  if (lease['office_api_base'] != identity.apiBase || lease['office_user_id'] != identity.actor ||
      lease['peer_id'] != identity.peer || lease['companion_token'] != identity.companion) return '';
  try {
    final checked = validateOfficeStaffLease(lease, identity, now);
    return (checked['expires_at'] as int) > now + 30 ? checked['access_token'] as String : '';
  } on FormatException { return ''; }
}
Future<Map<String, dynamic>> exchangeOfficeStaffLease({
  required ExantasNativeIdentity before,
  required Future<ExantasNativeIdentity> Function() current,
  required Future<Map<String, dynamic>> Function() request,
  required Future<void> Function(Map<String, dynamic>) store,
  required int Function() now,
}) async {
  final lease = validateOfficeStaffLease(await request(), before, now());
  if (!before.sameAs(await current())) throw StateError('Η σύνδεση Office άλλαξε.');
  await store(lease);
  return lease;
}

/// Validate only the current source response; never accept a provider secret or
/// another source as evidence that this installation was approved.
Map<String, dynamic> validateOfficeInstallation(Map<String, dynamic> response, String peer) {
  final rows = response['installations'];
  if (response['status'] != 'ok' || rows is! List || rows.length != 1 || rows.first is! Map) {
    throw const FormatException('Δεν επιβεβαιώθηκε η εγγραφή εγκατάστασης.');
  }
  final row = Map<String, dynamic>.from(rows.first as Map);
  if (row['peer_id'] != peer || row['id'] is! String ||
      !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(row['id']) ||
      row['key_fingerprint'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['key_fingerprint']) ||
      !['pending', 'approved', 'revoked'].contains(row['state'])) {
    throw const FormatException('Δεν επιβεβαιώθηκε η ταυτότητα εγκατάστασης.');
  }
  return row;
}

/// One random capability per protected installation profile, shared across
/// Office operator changes. A failed request never rotates or erases it.
Future<String> officeInstallationKey({
  required Future<String> Function() load,
  required Future<void> Function(String) save,
}) async {
  var key = await load();
  if (key.isEmpty) {
    final random = Random.secure();
    key = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
    await save(key);
  }
  try {
    final bytes = base64Decode(key);
    if (bytes.length == 32 && base64Encode(bytes) == key) return key;
  } on FormatException { /* fail closed without replacing the approved key */ }
  throw const FormatException('Δεν επιβεβαιώθηκε το αποδεικτικό εγκατάστασης. Απαιτείται έλεγχος διαχειριστή.');
}
