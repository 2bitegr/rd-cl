import 'dart:convert';
import 'dart:math';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/exantas_secure_store.dart';
import 'package:flutter_hbb/models/exantas_session_report.dart';
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
const String kExantasOfficeUserId = 'exantas.office.user_id';
const String kExantasSupportRole = 'exantas.office.support_role';
const String kExantasTechnicianToken = 'exantas.office.technician_token';

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
    required this.policy,
    required this.officeUserId,
  });

  final String apiBase;
  final String officeUserId;
  final bool enrolled;
  final bool technicianLoggedIn;
  final String deviceToken;
  final String companionToken;
  final String customerName;
  final String technicianName;
  final String supportRole;
  final Map<String, dynamic> policy;

  String get modeLabel =>
      enrolled ? 'Managed by Exantas Office' : 'Basic support mode';
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
      officeUserId: bind.mainGetLocalOption(key: kExantasOfficeUserId),
      enrolled: deviceToken.trim().isNotEmpty,
      technicianLoggedIn: companionToken.trim().isNotEmpty,
      deviceToken: deviceToken,
      companionToken: companionToken,
      customerName: bind.mainGetLocalOption(key: kExantasDeviceCustomerName),
      technicianName: bind.mainGetLocalOption(key: kExantasTechnicianName),
      supportRole: bind.mainGetLocalOption(key: kExantasSupportRole),
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

    if (unattendedEnabled) {
      final unattendedPassword = _generatePassword();
      try {
        final passwordSet = await bind.mainSetPermanentPasswordWithResult(
            password: unattendedPassword);
        if (!passwordSet) {
          throw Exception('Could not set per-device unattended password.');
        }
        await bind.mainSetOption(
            key: 'verification-method', value: kUseBothPasswords);
        await _post(
            '/rustdesk-devices/credential',
            {
              'unattended_password': unattendedPassword,
            },
            bearerToken: deviceToken);
      } catch (_) {
        await bind.mainSetPermanentPasswordWithResult(password: '');
        await bind.mainSetOption(
            key: 'verification-method', value: kUseTemporaryPassword);
        rethrow;
      }
    } else {
      await bind.mainSetOption(
          key: 'verification-method', value: kUseTemporaryPassword);
    }

    await _setSecretLocalOption(kExantasDeviceToken, deviceToken);
    await bind.mainSetLocalOption(
        key: kExantasDeviceId, value: _string(device['id']));
    await bind.mainSetLocalOption(
        key: kExantasDeviceCustomerName,
        value: _string(device['customer_name']));
    await bind.mainSetLocalOption(
        key: kExantasDevicePolicy, value: jsonEncode(policy));
    return loadStatus();
  }

  Future<ExantasCompanionStatus> loginTechnician(
      String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.trim().isEmpty) {
      throw Exception('Email and password are required.');
    }

    final login = await _post('/admin/auth/login', {
      'email': normalizedEmail,
      'password': password,
    });
    final officeToken = _string(login['access_token']);
    if (officeToken.isEmpty) {
      throw Exception('Office login did not return a token.');
    }

    final peerId = (await bind.mainGetMyId()).trim();
    if (peerId.isEmpty) {
      throw Exception('RustDesk ID is not ready yet.');
    }

    final pair = await _post('/rustdesk-companion/pair', {
      'office_access_token': officeToken,
      'rustdesk_peer_id': peerId,
      'device_name': 'Exantas Support Technician',
    });
    final companionToken = _string(pair['token']);
    if (companionToken.isEmpty) {
      throw Exception('Office did not return a companion token.');
    }

    await _setSecretLocalOption(kExantasTechnicianToken, '');
    await _setSecretLocalOption(kExantasCompanionToken, companionToken);
    await bind.mainSetLocalOption(key: kExantasOfficeUserId,
        value: _string(pair['office_user_id']));
    await bind.mainSetLocalOption(
        key: kExantasTechnicianName, value: _string(pair['technician_name']));
    await bind.mainSetLocalOption(
        key: kExantasSupportRole, value: _string(pair['support_role']));
    return loadStatus();
  }

  Future<void> logoutTechnician() async {
    final status = await loadStatus();
    if (status.companionToken.isNotEmpty) {
      // Keep local credentials if Office cannot confirm the revocation.
      // Clearing only local storage leaves a live server-side pairing interval.
      await _post('/rustdesk-companion/logout', {},
          bearerToken: status.companionToken);
    }
    await _setSecretLocalOption(kExantasTechnicianToken, '');
    await _setSecretLocalOption(kExantasCompanionToken, '');
    await bind.mainSetLocalOption(key: kExantasOfficeUserId, value: '');
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

  Future<Map<String, dynamic>> submitSessionReport(
    String sessionId,
    ExantasSessionOutcome outcome,
    String note, {
    required String idempotencyKey,
    String? expectedOfficeUserId,
    String? expectedApiBase,
  }) async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      throw Exception('Office login is required.');
    }
    if ((expectedOfficeUserId != null && expectedOfficeUserId != status.officeUserId) ||
        (expectedApiBase != null && expectedApiBase != status.apiBase)) {
      throw Exception('Ο λογαριασμός Office άλλαξε. Η αναφορά παραμένει τοπικά.');
    }
    return _post(
      '/rustdesk-companion/sessions/$sessionId/comment',
      {
        'comment': buildExantasSessionReportCommand(outcome, note),
        'idempotency_key': idempotencyKey,
      },
      bearerToken: status.companionToken,
    );
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
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%+=';
    final random = Random.secure();
    return List.generate(20, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }
}
