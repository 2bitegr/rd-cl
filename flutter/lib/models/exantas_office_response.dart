import 'dart:convert';

/// Proxies can return plain text/HTML. Never present it as a JSON parse error
/// or accept an unsuccessful/invalid response as an authenticated Office reply.
Map<String, dynamic> decodeExantasOfficeResponse(int statusCode, String body,
    {bool androidSupport = false}) {
  Map<String, dynamic>? decoded;
  try {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) decoded = value;
  } on FormatException {
    // Report the HTTP failure without displaying an untrusted proxy body.
  }
  if (statusCode < 200 || statusCode >= 300) {
    final message = decoded?['message'];
    if (androidSupport) {
      final code = decoded?['status'];
      if (statusCode == 404 && message == 'Route not found.') {
        throw Exception(
            'Το Office χρειάζεται ενημέρωση για υποστήριξη από Android. Η σύνδεσή σας διατηρείται.');
      }
      const nativeErrors = {
        'native_auth_rejected':
            'Το RustDesk δεν δέχθηκε την ταυτότητα της συσκευής. Η σύνδεση Office διατηρείται.',
        'native_auth_unconfirmed':
            'Δεν επιβεβαιώθηκε η σύνδεση με το RustDesk. Ελέγξτε το δίκτυο και επιβεβαιώστε ξανά.',
        'native_auth_invalid_response':
            'Δεν επιστράφηκε έγκυρη επιβεβαίωση από το RustDesk. Η σύνδεση Office διατηρείται.',
        'native_auth_disabled':
            'Η σύνδεση Office–RustDesk δεν έχει ενεργοποιηθεί στον server.',
        'native_auth_configuration':
            'Η σύνδεση Office–RustDesk χρειάζεται ρύθμιση στον server.',
      };
      if (nativeErrors.containsKey(code)) throw Exception(nativeErrors[code]);
    }

    throw Exception(message is String && message.trim().isNotEmpty
        ? message.trim()
        : 'Το Office δεν ολοκλήρωσε το αίτημα (HTTP $statusCode). Δοκιμάστε ξανά.');
  }
  if (decoded == null) {
    throw Exception(
        'Μη έγκυρη απάντηση από το Office. Η ενέργεια δεν επιβεβαιώθηκε.');
  }
  return decoded;
}
