import 'dart:convert';

/// Proxies can return plain text/HTML. Never present it as a JSON parse error
/// or accept an unsuccessful/invalid response as an authenticated Office reply.
Map<String, dynamic> decodeExantasOfficeResponse(int statusCode, String body) {
  Map<String, dynamic>? decoded;
  try {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) decoded = value;
  } on FormatException {
    // Report the HTTP failure without displaying an untrusted proxy body.
  }
  if (statusCode < 200 || statusCode >= 300) {
    final message = decoded?['message'];
    throw Exception(message is String && message.trim().isNotEmpty
        ? message.trim()
        : 'Το Office δεν ολοκλήρωσε το αίτημα (HTTP $statusCode). Δοκιμάστε ξανά.');
  }
  if (decoded == null) {
    throw Exception('Μη έγκυρη απάντηση από το Office. Η ενέργεια δεν επιβεβαιώθηκε.');
  }
  return decoded;
}
