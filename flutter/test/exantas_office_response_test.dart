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
}
