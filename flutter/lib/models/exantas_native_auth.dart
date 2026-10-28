import 'dart:convert';

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
    ExantasNativeIdentity identity, String nativeApi, int now) {
  final token = value['access_token'];
  final expiry = value['expires_at'];
  if (value['status'] != 'ok' ||
      value['contract_version'] != 1 ||
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
  }) async {
    final response = await request();
    final lease = validateNativeLease(response, before, nativeApi, now());
    if (!before.sameAs(await current())) {
      throw StateError('Η σύνδεση Office άλλαξε. Συνδεθείτε ξανά.');
    }
    await store(lease);
    return lease;
  }
}
