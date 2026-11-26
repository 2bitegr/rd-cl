import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';

void main() {
  test('valid Office JSON retains fields', () {
    expect(decodeExantasOfficeResponse(200, '{"token":"synthetic"}'),
        {'token': 'synthetic'});
  });
  test('plain proxy failure reports HTTP status without raw body', () {
    expect(
        () => decodeExantasOfficeResponse(502, 'error code: 502'),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('HTTP 502') &&
            !e.toString().contains('FormatException'))));
  });
  test('JSON rejection remains rejection with safe producer message', () {
    expect(() => decodeExantasOfficeResponse(403, '{"message":"Denied"}'),
        throwsA(predicate((e) => e.toString() == 'Exception: Denied')));
  });
  test('error-only native response is not mistaken for Office success', () {
    expect(() => decodeExantasOfficeResponse(401, '{"error":"unauthorized"}'),
        throwsA(predicate((e) => e.toString().contains('HTTP 401'))));
  });
  test('malformed, empty and non-object successful responses fail closed', () {
    for (final body in ['<html>proxy</html>', '', 'null', '[]', '"ok"']) {
      expect(() => decodeExantasOfficeResponse(200, body), throwsException);
    }
  });
  test(
      'Android missing route explains required Office update without discarding login',
      () {
    expect(
        () => decodeExantasOfficeResponse(
            404, '{"status":"not_found","message":"Route not found."}',
            androidSupport: true),
        throwsA(predicate((e) =>
            e.toString().contains('Office χρειάζεται ενημέρωση') &&
            e.toString().contains('διατηρείται'))));
    expect(
        () => decodeExantasOfficeResponse(
            404, '{"status":"not_found","message":"Route not found."}'),
        throwsA(
            predicate((e) => e.toString() == 'Exception: Route not found.')));
  });
  test(
      'Android native failure reports classified safe message instead of proxy content',
      () {
    expect(
        () => decodeExantasOfficeResponse(502,
            '{"status":"native_auth_rejected","message":"private provider content"}',
            androidSupport: true),
        throwsA(predicate((e) =>
            e.toString().contains('ταυτότητα της συσκευής') &&
            !e.toString().contains('private provider'))));
  });
  test('revoked or missing companion pairing asks for a new technician login', () {
    for (final reason in ['device_revoked', 'device_not_found']) {
      expect(
          () => decodeExantasOfficeResponse(401,
              '{"status":"access_denied","message":"Invalid companion session.","details":{"reason":"$reason"}}'),
          throwsA(predicate((e) =>
              e is ExantasCompanionPairingGone &&
              e.statusCode == 401 &&
              !e.definitive &&
              e.toString().contains('Συνδεθείτε ξανά') &&
              !e.toString().contains('Invalid companion'))));
    }
  });
  test('inactive Office account is explained but is not a revoked pairing', () {
    expect(
        () => decodeExantasOfficeResponse(401,
            '{"status":"access_denied","message":"Invalid companion session.","details":{"reason":"admin_inactive"}}'),
        throwsA(predicate((e) =>
            e is ExantasOfficeRejection &&
            e is! ExantasCompanionPairingGone &&
            e.toString().contains('ανενεργός'))));
  });
  test('other 401 rejections never clear a technician sign-in', () {
    for (final body in [
      '{"status":"access_denied","message":"Invalid RustDesk device session.","details":{"reason":"device_revoked"}}',
      '{"status":"access_denied","message":"Invalid admin session.","details":{"reason":"session_revoked"}}',
      '{"status":"access_denied","message":"Invalid companion session.","details":{"reason":"other"}}',
      '{"status":"unauthorized","message":"Missing bearer token.","details":null}',
      'error code: 401',
    ]) {
      expect(() => decodeExantasOfficeResponse(401, body),
          throwsA(predicate((e) => e is! ExantasCompanionPairingGone)));
    }
    expect(
        () => decodeExantasOfficeResponse(403,
            '{"status":"access_denied","message":"Invalid companion session.","details":{"reason":"device_revoked"}}'),
        throwsA(predicate((e) => e is! ExantasCompanionPairingGone)));
  });
}
