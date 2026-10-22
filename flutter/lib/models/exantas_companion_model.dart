import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/exantas_secure_store.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';
import 'package:flutter_hbb/models/exantas_identity.dart';
import 'package:flutter_hbb/models/exantas_session_report.dart';
import 'package:flutter_hbb/models/exantas_workflow_http_policy.dart';
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
const String kExantasNativeLease = 'exantas.office.native_lease';
const String kExantasNativeReady = 'exantas.office.native_ready';
const String kExantasNativeExpiry = 'exantas.office.native_expiry';
const String kExantasNativeConfirm = 'exantas.office.native_confirmation_required';

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
    this.nativeReady = false,
  });

  final bool nativeReady;
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

class ExantasCompanionService implements ExantasIdentityActions {
  static final accountChanges = ChangeNotifier();
  static final _nativeFence = ExantasNativeAuthFence();
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
      nativeReady: bind.mainGetLocalOption(key: kExantasNativeReady) == 'Y' &&
          bind.mainGetLocalOption(key: kExantasNativeConfirm).isEmpty,
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

  @override
  Future<ExantasIdentityAccess?> authorizeIdentityReset() async {
    final before = await loadStatus();
    if (!before.technicianLoggedIn || before.officeUserId.isEmpty ||
        !['technician', 'admin'].contains(before.supportRole) ||
        before.apiBase.replaceFirst(RegExp(r'/+$'), '') != kDefaultExantasOfficeApiBase) return null;
    final response = await _get('/rustdesk-companion/workflow-capabilities',
      bearerToken: before.companionToken).timeout(const Duration(seconds: 12));
    _requireSameCompanion(before, await loadStatus());
    if (response['status'] != 'ok' || response['office_user_id'] != before.officeUserId ||
        response['pairing_id'] is! String || (response['pairing_id'] as String).isEmpty) return null;
    final id = (await bind.mainGetMyId()).trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(id)) return null;
    return ExantasIdentityAccess(apiBase: before.apiBase, officeUserId: before.officeUserId,
      companionToken: before.companionToken, currentId: id);
  }

  @override
  Future<bool> identitySessionMatches(ExantasIdentityAccess access) async {
    final now = await loadStatus();
    return now.technicianLoggedIn && now.companionToken == access.companionToken &&
      now.officeUserId == access.officeUserId && now.apiBase == access.apiBase &&
      ['technician', 'admin'].contains(now.supportRole) &&
      (await bind.mainGetMyId()).trim() == access.currentId;
  }

  @override
  Future<ExantasIdentityResult> regenerateIdentity(ExantasIdentityAccess access) async {
    if (!await identitySessionMatches(access)) {
      return const ExantasIdentityResult(success: false, code: 'office_login_required', officeSignedOut: false);
    }
    Map<String, dynamic> response;
    try {
      response = _decodeMap(await bind.mainRegenerateOfficeId(request: jsonEncode({
        'api_base': access.apiBase, 'companion_token': access.companionToken,
        'office_user_id': access.officeUserId, 'expected_id': access.currentId,
      })));
    } catch (_) {
      // A lost bridge reply can follow a committed daemon operation. Expose the
      // ambiguity and fence this exact local sign-in; never retry automatically.
      response = {'status': 'error', 'code': 'result_unconfirmed', 'office_signed_out': true};
    }
    final signedOut = response['office_signed_out'] == true;
    final current = await loadStatus();
    if (signedOut && current.companionToken == access.companionToken &&
        current.officeUserId == access.officeUserId && current.apiBase == access.apiBase) {
      // The daemon revoked this exact pairing. Never call logout again or clear
      // credentials belonging to a different sign-in after a delayed response.
      await _setSecretLocalOption(kExantasCompanionToken, '');
    }
    return ExantasIdentityResult(success: response['status'] == 'ok', code: _string(response['code']),
      officeSignedOut: signedOut, newId: _string(response['new_id']), backupPath: _string(response['backup_path']));
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

  Future<ExantasCompanionStatus> loginTechnician(String email, String password) =>
      _nativeFence.run(() => _loginTechnician(email, password));

  Future<ExantasCompanionStatus> _loginTechnician(
      String email, String password) async {
    nativeApiOrigin(apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    if (Platform.isWindows && bind.mainGetLocalOption(key: 'access_token').isNotEmpty) {
      throw StateError('Αποσυνδεθείτε πρώτα από τον ξεχωριστό λογαριασμό RustDesk.');
    }
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

    final old = await loadStatus();
    if (old.technicianLoggedIn) await _logoutTechnician();
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
    await bind.mainSetLocalOption(
        key: kExantasOfficeUserId, value: _string(pair['office_user_id']));
    await bind.mainSetLocalOption(
        key: kExantasTechnicianName, value: _string(pair['technician_name']));
    await bind.mainSetLocalOption(
        key: kExantasSupportRole, value: _string(pair['support_role']));
    if (Platform.isWindows) await _ensureNativeReady(force: true);
    return loadStatus();
  }

  Future<void> logoutTechnician() => _nativeFence.run(_logoutTechnician);

  Future<void> _logoutTechnician() async {
    final status = await loadStatus();
    if (status.companionToken.isNotEmpty) {
      // Keep local credentials if Office cannot confirm the revocation.
      // Clearing only local storage leaves a live server-side pairing interval.
      final hasLease = bind.mainGetLocalOption(key: kExantasNativeLease).isNotEmpty ||
          bind.mainGetLocalOption(key: kExantasNativeConfirm).isNotEmpty;
      await _post(hasLease ? '/rustdesk-companion/native-logout' : '/rustdesk-companion/logout', {},
          bearerToken: status.companionToken).timeout(const Duration(seconds: 12));
    }
    await _setSecretLocalOption(kExantasNativeLease, '');
    await bind.mainSetLocalOption(key: kExantasNativeExpiry, value: '');
    await bind.mainSetLocalOption(key: kExantasNativeConfirm, value: '');
    await _setSecretLocalOption(kExantasTechnicianToken, '');
    await _setSecretLocalOption(kExantasCompanionToken, '');
    await bind.mainSetLocalOption(key: kExantasOfficeUserId, value: '');
    await bind.mainSetLocalOption(key: kExantasTechnicianName, value: '');
    await bind.mainSetLocalOption(key: kExantasSupportRole, value: '');
  }

  Future<ExantasNativeIdentity> _nativeIdentity() async {
    final status = await loadStatus();
    return ExantasNativeIdentity(status.apiBase, status.officeUserId,
        status.companionToken, (await bind.mainGetMyId()).trim());
  }

  Future<void> ensureNativeReady({bool force = false}) =>
      _nativeFence.run(() => _ensureNativeReady(force: force));

  Future<void> _ensureNativeReady({bool force = false}) async {
    final before = await _nativeIdentity();
    if (!Platform.isWindows || before.companion.isEmpty) return;
    if (before.actor.isEmpty) throw StateError('Απαιτείται νέα είσοδος στο Office.');
    if (!force && bind.mainGetLocalOption(key: kExantasNativeConfirm).isNotEmpty) {
      throw StateError('Ελέγξτε τη σύνδεση και πατήστε Επιβεβαίωση RustDesk. Δεν έγινε αυτόματη επανάληψη.');
    }
    if (!Platform.isWindows) throw UnsupportedError('Απαιτείται προστασία διαπιστευτηρίων Windows.');
    nativeApiOrigin(before.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    final nativeApi = nativeApiOrigin(await bind.mainGetApiServer());
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiry = int.tryParse(bind.mainGetLocalOption(key: kExantasNativeExpiry)) ?? 0;
    if (!force && expiry > now + 90 && bind.mainGetLocalOption(key: kExantasNativeReady) == 'Y') return;
    // Persist the ambiguity fence before sending. A lost reply or restart must
    // require an explicit retry instead of silently repeating an issuance.
    await bind.mainSetLocalOption(key: kExantasNativeConfirm, value: 'Y');
    await _nativeFence.exchange(
      before: before, current: _nativeIdentity, nativeApi: nativeApi,
      now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      request: () async => await _post('/rustdesk-companion/native-session',
        {'device_uuid': await bind.mainGetUuid()}, bearerToken: before.companion)
          .timeout(const Duration(seconds: 12)),
      store: (lease) async {
        await _setSecretLocalOption(kExantasNativeLease, jsonEncode(lease));
        await bind.mainSetLocalOption(key: kExantasNativeExpiry, value: '${lease['expires_at']}');
      },
    );
    if (bind.mainGetLocalOption(key: kExantasNativeReady) != 'Y') {
      throw StateError('Το rd-cl δεν επιβεβαίωσε την ασφαλή σύνδεση RustDesk.');
    }
    await bind.mainSetLocalOption(key: kExantasNativeConfirm, value: '');
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

  Future<List<Map<String, dynamic>>> pendingSessions({
    bool includeLegacyQueue = false,
  }) async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      return [];
    }
    await _post('/rustdesk-companion/sessions/sync', {},
        bearerToken: status.companionToken);
    final response = await _get('/rustdesk-companion/sessions/pending',
        bearerToken: status.companionToken);
    _requireSameCompanion(status, await loadStatus());
    final items = response['items'];
    if (items is List) {
      final sessions = items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final capabilities = await workflowCapabilities();
      if (capabilities == null || !capabilities.supportsV2) return sessions;
      final fromPeer = (await bind.mainGetMyId()).trim();
      final result = <Map<String, dynamic>>[];
      for (final session in sessions) {
        final context = await lookupWorkContext(
          peerId: _string(session['peer_id']),
          fromPeer: fromPeer,
          rustDeskSessionId: _string(session['rustdesk_session_id']),
          capabilities: capabilities,
        );
        if (context == null || (includeLegacyQueue && !context.isV2Bound)) {
          // Pre-v2 encrypted queue entries retain their legacy contract. A
          // confirmed v2 binding is still never submitted through v1.
          result.add(session);
        }
      }
      _requireSameCompanion(status, await loadStatus());
      return result;
    }
    return [];
  }

  /// Returns null only when the endpoint is absent (404), which preserves the
  /// pre-v2 client contract. Other errors remain visible to the caller.
  Future<ExantasWorkflowCapabilities?> workflowCapabilities() async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      throw Exception('Office login is required.');
    }
    final response = await _getOptional404(
      '/rustdesk-companion/workflow-capabilities',
      bearerToken: status.companionToken,
    );
    if (response == null) {
      _requireSameCompanion(status, await loadStatus());
      return null;
    }
    if (response['status'] != 'ok' || response['enabled'] is! bool) {
      throw const FormatException('Invalid workflow capabilities response.');
    }
    final rawVersions = response['contract_versions'];
    if (rawVersions is! List || rawVersions.any((value) => value is! int)) {
      throw const FormatException('Invalid workflow capabilities response.');
    }
    final current = await loadStatus();
    _requireSameCompanion(status, current);
    return ExantasWorkflowCapabilities(
      enabled: response['enabled'] as bool,
      contractVersions: rawVersions.cast<int>().toSet(),
    );
  }

  /// Performs an authenticated, read-only lookup using the paired technician
  /// identity established by Office. The client never supplies an owner ID.
  Future<ExantasWorkContext?> lookupWorkContext({
    required String peerId,
    required String fromPeer,
    String? rustDeskSessionId,
    ExantasWorkflowCapabilities? capabilities,
  }) async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn || status.officeUserId.isEmpty) {
      throw Exception('Office login is required.');
    }
    final peer = peerId.trim();
    final actorPeer = fromPeer.trim();
    if (peer.isEmpty || actorPeer.isEmpty) {
      throw ArgumentError('RustDesk peer identifiers are required.');
    }
    final resolvedCapabilities = capabilities ?? await workflowCapabilities();
    if (resolvedCapabilities == null || !resolvedCapabilities.supportsV2) {
      return null;
    }
    _requireSameCompanion(status, await loadStatus());
    final body = <String, dynamic>{'peer_id': peer, 'from_peer': actorPeer};
    final sessionId = rustDeskSessionId?.trim() ?? '';
    if (sessionId.isNotEmpty && sessionId != '0') {
      body['rustdesk_session_id'] = sessionId;
    }
    final response = await _post(
      '/rustdesk-companion/work-context',
      body,
      bearerToken: status.companionToken,
    );
    final current = await loadStatus();
    _requireSameCompanion(status, current);
    return parseExantasWorkContext(response);
  }

  Future<List<Map<String, dynamic>>> workflowItems() async {
    final status = await loadStatus();
    if (!status.technicianLoggedIn) {
      throw Exception('Office login is required.');
    }
    final capabilities = await workflowCapabilities();
    if (capabilities == null || !capabilities.supportsV2) return [];
    final response = await _get(
      '/rustdesk-companion/work-items',
      bearerToken: status.companionToken,
    );
    final current = await loadStatus();
    _requireSameCompanion(status, current);
    final items = response['items'];
    if (items is! List) {
      throw const FormatException('Invalid Office work items response.');
    }
    return items
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<ExantasWorkContext> claimWorkContext({
    required String workItemId,
    required String remoteSessionId,
    required String expectedRevision,
    required String idempotencyKey,
    required String expectedOfficeUserId,
    required String expectedApiBase,
  }) async {
    final status = await loadStatus();
    _requireExpectedCompanion(status, expectedOfficeUserId, expectedApiBase);
    if (!status.technicianLoggedIn || status.officeUserId.isEmpty) {
      throw Exception('Office login is required.');
    }
    final capabilities = await workflowCapabilities();
    if (capabilities == null || !capabilities.supportsV2) {
      throw StateError('Office support workflow v2 is unavailable.');
    }
    _requireSameCompanion(status, await loadStatus());
    final response = await _post(
      '/rustdesk-companion/work-context/claim',
      {
        'work_item_id': workItemId,
        'remote_session_id': remoteSessionId,
        'expected_revision': expectedRevision,
        'idempotency_key': idempotencyKey,
      },
      bearerToken: status.companionToken,
    );
    final current = await loadStatus();
    _requireSameCompanion(status, current);
    final context = parseExantasWorkContext(response);
    if (!context.isV2Bound) {
      throw const FormatException('Office did not confirm the work binding.');
    }
    return context;
  }

  Future<Map<String, dynamic>> saveWorkDraft({
    required String workItemId,
    required String remoteSessionId,
    required String text,
    required String expectedRevision,
    required String idempotencyKey,
    required String expectedOfficeUserId,
    required String expectedApiBase,
  }) async {
    final status = await loadStatus();
    _requireExpectedCompanion(status, expectedOfficeUserId, expectedApiBase);
    if (!status.technicianLoggedIn || status.officeUserId.isEmpty) {
      throw Exception('Office login is required.');
    }
    final capabilities = await workflowCapabilities();
    if (capabilities == null || !capabilities.supportsV2) {
      throw StateError('Office support workflow v2 is unavailable.');
    }
    _requireSameCompanion(status, await loadStatus());
    final response = await _post(
      '/rustdesk-companion/work-drafts',
      {
        'work_item_id': workItemId,
        'remote_session_id': remoteSessionId,
        'text': text,
        'expected_revision': expectedRevision,
        'idempotency_key': idempotencyKey,
      },
      bearerToken: status.companionToken,
    );
    final current = await loadStatus();
    _requireSameCompanion(status, current);
    if (response['status'] != 'ok' || response['action'] != 'draft_saved') {
      throw const FormatException('Office did not confirm the work draft.');
    }
    return response;
  }

  void _requireSameCompanion(
    ExantasCompanionStatus before,
    ExantasCompanionStatus after,
  ) {
    if (before.officeUserId != after.officeUserId ||
        before.apiBase != after.apiBase ||
        before.companionToken != after.companionToken) {
      throw Exception('Office account changed during the request.');
    }
  }

  void _requireExpectedCompanion(
    ExantasCompanionStatus status,
    String expectedOfficeUserId,
    String expectedApiBase,
  ) {
    if (status.officeUserId != expectedOfficeUserId ||
        status.apiBase != expectedApiBase) {
      throw Exception('Office account changed. The draft remains local.');
    }
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
    if ((expectedOfficeUserId != null &&
            expectedOfficeUserId != status.officeUserId) ||
        (expectedApiBase != null && expectedApiBase != status.apiBase)) {
      throw Exception(
          'Ο λογαριασμός Office άλλαξε. Η αναφορά παραμένει τοπικά.');
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

  Future<Map<String, dynamic>?> _getOptional404(String path,
      {String? bearerToken}) async {
    final response = await http.get(
      Uri.parse('$apiBase$path'),
      headers: _headers(bearerToken),
    );
    return decodeExantasOptional404(
      response.statusCode,
      () => _decodeResponse(response.statusCode, response.body),
    );
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
    return decodeExantasOfficeResponse(statusCode, body);
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
