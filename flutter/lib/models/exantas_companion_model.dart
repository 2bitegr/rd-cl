import 'dart:convert';
import 'dart:math';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/exantas_secure_store.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

const String kExantasOfficeApiBase = 'exantas.office.api_base';
const String kExantasDeviceToken = 'exantas.office.device_token';
const String kExantasDeviceId = 'exantas.office.device_id';
const String kExantasDevicePolicy = 'exantas.office.device_policy';
const String kExantasDeviceCustomerName = 'exantas.office.customer_name';
const String kExantasCompanionToken = 'exantas.office.companion_token';
const String kExantasTechnicianName = 'exantas.office.technician_name';
const String kExantasSupportRole = 'exantas.office.support_role';
const String kExantasTechnicianToken = 'exantas.office.technician_token';
const String kExantasUnattendedPasswordStatus =
    'exantas.office.unattended_password_status';
const String kExantasUnattendedPasswordError =
    'exantas.office.unattended_password_error';

const String kExantasUnattendedDisabled = 'disabled';
const String kExantasUnattendedEnabled = 'enabled';
const String kExantasUnattendedPending = 'pending';

const String kDefaultExantasOfficeApiBase =
    'https://api-office.exantas.eu/api/v1';

class ExantasCompanionStatus {
  ExantasCompanionStatus({
    required this.apiBase,
    required this.enrolled,
    required this.technicianLoggedIn,
    required this.deviceToken,
    required this.companionToken,
    required this.customerName,
    required this.technicianName,
    required this.supportRole,
    required this.unattendedPasswordStatus,
    required this.unattendedPasswordError,
    required this.policy,
  });

  final String apiBase;
  final bool enrolled;
  final bool technicianLoggedIn;
  final String deviceToken;
  final String companionToken;
  final String customerName;
  final String technicianName;
  final String supportRole;
  final String unattendedPasswordStatus;
  final String unattendedPasswordError;
  final Map<String, dynamic> policy;

  String get modeLabel =>
      enrolled ? 'Διαχειριζόμενη συσκευή από Exantas Support' : '';

  bool get unattendedPasswordPending =>
      enrolled &&
      policy['unattended_enabled'] == true &&
      unattendedPasswordStatus != kExantasUnattendedEnabled;

  String get unattendedPasswordMessage => unattendedPasswordPending
      ? unattendedPasswordError.isNotEmpty
          ? unattendedPasswordError
          : 'Η συσκευή γράφτηκε, αλλά η πρόσβαση χωρίς παρουσία δεν ενεργοποιήθηκε. Πάτησε «Ενεργοποίηση unattended» για νέα προσπάθεια.'
      : '';
}

class ExantasCompanionService {
  final ExantasSecureStore _secureStore = const ExantasSecureStore();

  String get apiBase {
    final configured =
        bind.mainGetLocalOption(key: kExantasOfficeApiBase).trim();
    return configured.isEmpty ? kDefaultExantasOfficeApiBase : configured;
  }

  Future<ExantasCompanionStatus> loadStatus() async {
    final deviceToken = await _getSecretLocalOption(kExantasDeviceToken);
    final companionToken = await _getSecretLocalOption(kExantasCompanionToken);
    final policyText = bind.mainGetLocalOption(key: kExantasDevicePolicy);
    return ExantasCompanionStatus(
      apiBase: apiBase,
      enrolled: deviceToken.trim().isNotEmpty,
      technicianLoggedIn: companionToken.trim().isNotEmpty,
      deviceToken: deviceToken,
      companionToken: companionToken,
      customerName: bind.mainGetLocalOption(key: kExantasDeviceCustomerName),
      technicianName: bind.mainGetLocalOption(key: kExantasTechnicianName),
      supportRole: bind.mainGetLocalOption(key: kExantasSupportRole),
      unattendedPasswordStatus:
          bind.mainGetLocalOption(key: kExantasUnattendedPasswordStatus),
      unattendedPasswordError:
          bind.mainGetLocalOption(key: kExantasUnattendedPasswordError),
      policy: _decodeMap(policyText),
    );
  }

  Future<ExantasCompanionStatus> enrollDevice(String installCode) async {
    final code = installCode.trim();
    if (code.isEmpty) {
      throw Exception('Install code is required.');
    }

    final peerId = (await bind.mainGetMyId()).trim();
    if (peerId.isEmpty) {
      throw Exception('RustDesk ID is not ready yet.');
    }

    final version = await bind.mainGetVersion();
    final response = await _post('/rustdesk-devices/enroll', {
      'install_code': code,
      'peer_id': peerId,
      'label': 'Exantas Support $peerId',
      'device_name': 'Exantas Support $peerId',
      'client_version': version,
      'install_mode': isRunningInPortableMode() ? 'portable' : 'msi',
      'platform': 'windows',
    });

    final deviceToken = _string(response['device_token']);
    if (deviceToken.isEmpty) {
      throw Exception('Office did not return a device token.');
    }

    final device = _decodeMap(response['device']);
    final policy = _decodeMap(response['policy']);
    final unattendedEnabled = policy['unattended_enabled'] == true;

    await _setSecretLocalOption(kExantasDeviceToken, deviceToken);
    await bind.mainSetLocalOption(
        key: kExantasDeviceId, value: _string(device['id']));
    await bind.mainSetLocalOption(
        key: kExantasDeviceCustomerName,
        value: _string(device['customer_name']));
    await bind.mainSetLocalOption(
        key: kExantasDevicePolicy, value: jsonEncode(policy));

    if (unattendedEnabled) {
      await _configureUnattendedPassword(deviceToken);
    } else {
      await bind.mainSetOption(
          key: 'verification-method', value: kUseTemporaryPassword);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordStatus,
          value: kExantasUnattendedDisabled);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordError, value: '');
    }
    return loadStatus();
  }

  Future<ExantasCompanionStatus> retryUnattendedPassword() async {
    final status = await loadStatus();
    if (!status.enrolled) {
      throw Exception('Η συσκευή δεν έχει εγγραφεί στο Exantas Support.');
    }
    if (status.policy['unattended_enabled'] != true) {
      throw Exception(
          'Η πρόσβαση χωρίς παρουσία δεν επιτρέπεται από το policy της συσκευής.');
    }
    if (!await _configureUnattendedPassword(status.deviceToken)) {
      throw Exception((await loadStatus()).unattendedPasswordMessage);
    }
    return loadStatus();
  }

  Future<ExantasCompanionStatus> pairTechnicianFromExistingLogin() async {
    final officeToken = bind.mainGetLocalOption(key: 'access_token').trim();
    if (officeToken.isEmpty) {
      throw Exception('Συνδέσου πρώτα από τις ρυθμίσεις.');
    }
    return pairTechnicianWithOfficeToken(officeToken);
  }

  Future<ExantasCompanionStatus> pairTechnicianWithOfficeToken(
      String officeToken) async {
    final peerId = (await bind.mainGetMyId()).trim();
    if (peerId.isEmpty) {
      throw Exception('RustDesk ID is not ready yet.');
    }

    final pair = await _post('/rustdesk-companion/pair', {
      'office_access_token': officeToken,
      'rustdesk_peer_id': peerId,
      'rustdesk_uuid': await bind.mainGetUuid(),
      ..._rustDeskAccountIdentity(),
      'device_name': 'Exantas Support Technician',
    });
    final companionToken = _string(pair['token']);
    if (companionToken.isEmpty) {
      throw Exception('Office did not return a companion token.');
    }

    await _setSecretLocalOption(kExantasTechnicianToken, '');
    await _setSecretLocalOption(kExantasCompanionToken, companionToken);
    await bind.mainSetLocalOption(
        key: kExantasTechnicianName, value: _string(pair['technician_name']));
    await bind.mainSetLocalOption(
        key: kExantasSupportRole, value: _string(pair['support_role']));
    return loadStatus();
  }

  Future<void> logoutTechnician() async {
    await _setSecretLocalOption(kExantasTechnicianToken, '');
    await _setSecretLocalOption(kExantasCompanionToken, '');
    await bind.mainSetLocalOption(key: kExantasTechnicianName, value: '');
    await bind.mainSetLocalOption(key: kExantasSupportRole, value: '');
  }

  Future<void> heartbeat() async {
    final status = await loadStatus();
    if (!status.enrolled) {
      return;
    }
    final peerId = (await bind.mainGetMyId()).trim();
    final version = await bind.mainGetVersion();
    await _post(
        '/rustdesk-devices/heartbeat',
        {
          'peer_id': peerId,
          'client_version': version,
          'install_mode': isRunningInPortableMode() ? 'portable' : 'msi',
          'platform': 'windows',
        },
        bearerToken: status.deviceToken);
  }

  Future<List<Map<String, dynamic>>> pendingSessions() async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      return [];
    }
    await _post('/rustdesk-companion/sessions/sync', {},
        bearerToken: status.companionToken);
    final response = await _get('/rustdesk-companion/sessions/pending',
        bearerToken: status.companionToken);
    final items = response['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return [];
  }

  Future<void> submitSessionComment(String sessionId, String comment) async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      throw Exception('Technician login is required.');
    }
    await _post(
        '/rustdesk-companion/sessions/$sessionId/comment',
        {
          'comment': comment,
          'idempotency_key': _commentIdempotencyKey(sessionId, comment),
        },
        bearerToken: status.companionToken);
  }

  Future<Map<String, dynamic>> _get(String path, {String? bearerToken}) async {
    final response = await http.get(
      Uri.parse('$apiBase$path'),
      headers: _headers(bearerToken),
    );
    return _decodeResponse(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {String? bearerToken}) async {
    final response = await http.post(
      Uri.parse('$apiBase$path'),
      headers: _headers(bearerToken),
      body: jsonEncode(body),
    );
    return _decodeResponse(response.statusCode, response.body);
  }

  Map<String, String> _headers(String? bearerToken) {
    return {
      'content-type': 'application/json',
      if (bearerToken != null && bearerToken.trim().isNotEmpty)
        'authorization': 'Bearer $bearerToken',
    };
  }

  Map<String, dynamic> _decodeResponse(int statusCode, String body) {
    final decoded = _decodeMap(body);
    if (statusCode < 200 || statusCode >= 300) {
      final message = _string(decoded['message']);
      throw Exception(message.isEmpty ? 'Office request failed.' : message);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeMap(dynamic value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return {};
  }

  Map<String, String> _rustDeskAccountIdentity() {
    final userInfo = _decodeMap(bind.mainGetLocalOption(key: 'user_info'));
    return {
      if (_string(userInfo['name']).isNotEmpty)
        'rustdesk_user_name': _string(userInfo['name']),
      if (_string(userInfo['email']).isNotEmpty)
        'rustdesk_user_email': _string(userInfo['email']),
    };
  }

  String _string(dynamic value) => value is String ? value.trim() : '';

  Future<String> _getSecretLocalOption(String key) async {
    final storedValue = bind.mainGetLocalOption(key: key);
    if (storedValue.isEmpty) {
      return '';
    }
    final value = _secureStore.unprotect(storedValue).trim();
    if (value.isNotEmpty && !_secureStore.isProtected(storedValue)) {
      await _setSecretLocalOption(key, value);
    }
    return value;
  }

  Future<void> _setSecretLocalOption(String key, String value) async {
    final protectedValue = _secureStore.protect(value.trim());
    await bind.mainSetLocalOption(key: key, value: protectedValue);
  }

  String _generatePassword() {
    const alphabet = '0123456789';
    final random = Random.secure();
    return List.generate(10, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  Future<bool> _configureUnattendedPassword(String deviceToken) async {
    await bind.mainSetLocalOption(
        key: kExantasUnattendedPasswordStatus,
        value: kExantasUnattendedPending);
    await bind.mainSetLocalOption(
        key: kExantasUnattendedPasswordError, value: '');
    final unattendedPassword = _generatePassword();
    if (!await _setPermanentPasswordWithRetry(unattendedPassword)) {
      await bind.mainSetOption(
          key: 'verification-method', value: kUseTemporaryPassword);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordError,
          value:
              'Η συσκευή γράφτηκε, αλλά το Exantas Support service δεν δέχτηκε το unattended password. Βεβαιώσου ότι το service τρέχει και πάτησε «Ενεργοποίηση unattended».');
      return false;
    }
    try {
      await _post(
          '/rustdesk-devices/credential',
          {
            'unattended_password': unattendedPassword,
          },
          bearerToken: deviceToken);
      await bind.mainSetOption(
          key: 'verification-method', value: kUseBothPasswords);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordStatus,
          value: kExantasUnattendedEnabled);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordError, value: '');
      return true;
    } catch (_) {
      await bind.mainSetPermanentPasswordWithResult(password: '');
      await bind.mainSetOption(
          key: 'verification-method', value: kUseTemporaryPassword);
      await bind.mainSetLocalOption(
          key: kExantasUnattendedPasswordError,
          value:
              'Η συσκευή γράφτηκε, αλλά το credential δεν αποθηκεύτηκε στο Exantas Support. Έλεγξε τη σύνδεση και πάτησε «Ενεργοποίηση unattended».');
      return false;
    }
  }

  Future<bool> _setPermanentPasswordWithRetry(String password) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final ok =
          await bind.mainSetPermanentPasswordWithResult(password: password);
      if (ok) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return false;
  }

  String _commentIdempotencyKey(String sessionId, String comment) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode('$sessionId|$comment')) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final safeSessionId = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'flutter_${hash.toRadixString(16).padLeft(8, '0')}_$safeSessionId';
  }
}
