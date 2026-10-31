import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/exantas_secure_store.dart';
import 'package:flutter_hbb/models/exantas_native_auth.dart';
import 'package:flutter_hbb/models/exantas_native_source.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';
import 'package:flutter_hbb/models/exantas_identity.dart';
import 'package:flutter_hbb/models/exantas_device_enrollment.dart';
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
const String kExantasAndroidStaffLease = 'exantas.office.android_staff_lease';
const String kExantasNativeConfirm = 'exantas.office.native_confirmation_required';

const String kExantasEnrollmentPending = 'exantas.office.enrollment_pending';
const String kExantasEnrollmentPassword = 'exantas.office.enrollment_password';
const String kExantasInstallerBootstrap = 'exantas.office.installer_bootstrap';

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
    this.enrollmentPending = false,
  });

  final bool nativeReady, enrollmentPending;
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

class _AccountChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

class ExantasCompanionService implements ExantasIdentityActions {
  static final _accountChanges = _AccountChanges();
  static Listenable get accountChanges => _accountChanges;
  static void notifyAccountChanged() => _accountChanges.changed();
  static final _nativeFence = ExantasNativeAuthFence();
  static Future<String>? _androidStaffRefresh;
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
      enrollmentPending: bind.mainGetLocalOption(key: kExantasEnrollmentPending).isNotEmpty,
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

  Future<bool> automaticCompletionPending() async {
    final status = await loadStatus();
    final attempt = _decodeMap(bind.mainGetLocalOption(key: kExantasEnrollmentPending));
    return status.enrolled && status.enrollmentPending && !status.technicianLoggedIn && attempt['automatic'] == true && attempt['automatic_retry_allowed'] != false;
  }

  Future<String> installerBootstrapCode(String launchCode) => _nativeFence.run(() async {
    final status = await loadStatus();
    nativeApiOrigin(status.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    if (status.enrolled || status.technicianLoggedIn || status.enrollmentPending ||
        bind.mainGetLocalOption(key: 'access_token').isNotEmpty) {
      await _setSecretLocalOption(kExantasInstallerBootstrap, '');
      return status.enrollmentPending ? launchCode : '';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (RegExp(r'^EXA-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(launchCode)) {
      await _setSecretLocalOption(kExantasInstallerBootstrap, jsonEncode({
        'code': launchCode, 'api_base': status.apiBase, 'expires_at': now + 3600000,
      }));
    }
    final queued = _decodeMap(await _getSecretLocalOption(kExantasInstallerBootstrap));
    final code = _string(queued['code']);
    if (queued['api_base'] != status.apiBase || queued['expires_at'] is! int ||
        (queued['expires_at'] as int) <= now || (queued['expires_at'] as int) > now + 3600000 ||
        !RegExp(r'^EXA-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(code)) {
      await _setSecretLocalOption(kExantasInstallerBootstrap, '');
      return '';
    }
    return code;
  });

  Future<ExantasDeviceEnrollmentPreview> previewDeviceEnrollment(String rawCode) async {
    final previewApi = apiBase;
    nativeApiOrigin(previewApi.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    final code = rawCode.trim().toUpperCase();
    if (!RegExp(r'^EXA-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(code)) {
      throw const FormatException('Μη έγκυρος κωδικός εγκατάστασης.');
    }
    final reply = await http.post(Uri.parse('$previewApi/rustdesk-devices/installation-info'),
      headers: _headers(null), body: jsonEncode({'install_code': code}),
    ).timeout(const Duration(seconds: 12));
    if (reply.statusCode == 410) throw const ExantasEnrollmentFailure('Το link έληξε ή άλλαξε η συσκευή. Αντιγράψτε νέο link από την καρτέλα του υπολογιστή στο Office.');
    if (reply.statusCode == 429) throw const ExantasEnrollmentFailure('Περιμένετε ένα λεπτό πριν δοκιμάσετε ξανά.');
    final response = _decodeResponse(reply.statusCode, reply.body);
    return ExantasDeviceEnrollmentPreview.parse(code, response, apiBase: previewApi);
  }

  Future<ExantasCompanionStatus> enrollDevice(ExantasDeviceEnrollmentPreview preview) =>
      _nativeFence.run(() => _enrollDevice(preview));

  Future<ExantasCompanionStatus> _enrollDevice(ExantasDeviceEnrollmentPreview preview) async {
    final before = await loadStatus();
    nativeApiOrigin(before.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    if (preview.apiBase != null && preview.apiBase != before.apiBase) throw const ExantasEnrollmentFailure('Η σύνδεση με το Office άλλαξε. Κάντε νέα λήψη από την επαφή.');
    if (before.enrolled || before.technicianLoggedIn || before.enrollmentPending ||
        bind.mainGetLocalOption(key: 'access_token').isNotEmpty) {
      throw StateError('Υπάρχει ήδη σύνδεση ή εκκρεμές αίτημα σε αυτόν τον υπολογιστή.');
    }
    var peerId = (await bind.mainGetMyId()).trim();
    // ID readiness is a read-only wait before any enrollment attempt marker/POST.
    for (var i = 0; preview.automatic && peerId.isEmpty && i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      peerId = (await bind.mainGetMyId()).trim();
    }
    if (!RegExp(r'^\d{6,10}$').hasMatch(peerId)) throw StateError('Το RustDesk ID δεν είναι έτοιμο.');
    requireEnrollmentPeer(preview, peerId);
    final version = await bind.mainGetVersion();
    final marker = jsonEncode({'api_base': before.apiBase, 'peer_id': peerId,
      'customer_id': preview.customerId, 'enrollment_id': preview.enrollmentId,
      'customer_name': preview.customerName, 'unattended_enabled': preview.unattended, 'automatic': preview.automatic});
    // Persist before a potentially committed request. A lost reply must not redeem
    // another use on refresh/restart; no automatic enrollment replay is allowed.
    await bind.mainSetLocalOption(key: kExantasEnrollmentPending, value: marker);
    // From this point a POST may commit: never automatically replay the code.
    await _setSecretLocalOption(kExantasInstallerBootstrap, '');
    final httpResponse = await http.post(Uri.parse('${before.apiBase}/rustdesk-devices/enroll'),
      headers: _headers(null), body: jsonEncode({
        'install_code': preview.code, 'peer_id': peerId,
        'expected_customer_id': preview.customerId,
        'expected_enrollment_id': preview.enrollmentId,
        'expected_unattended_enabled': preview.unattended,
        'label': 'Exantas Support $peerId', 'device_name': 'Exantas Support $peerId',
        'client_version': version, 'install_mode': isRunningInPortableMode() ? 'portable' : 'unknown',
        'platform': 'windows',
      })).timeout(const Duration(seconds: 20));
    if (httpResponse.statusCode >= 400 && httpResponse.statusCode < 500) {
      Map<String, dynamic> error = {};
      try { error = _decodeMap(jsonDecode(httpResponse.body)); } catch (_) {}
      if (['enrollment_confirmation_changed', 'invalid_enrollment_code',
          'enrollment_link_revoked', 'enrollment_link_expired',
          'enrollment_link_exhausted', 'customer_inactive', 'enrollment_customer_conflict',
          'device_already_managed', 'device_access_conflict'].contains(error['status']) &&
          bind.mainGetLocalOption(key: kExantasEnrollmentPending) == marker) {
        await bind.mainSetLocalOption(key: kExantasEnrollmentPending, value: '');
      }
    }
    final response = _decodeResponse(httpResponse.statusCode, httpResponse.body);
    final current = await loadStatus();
    final device = _decodeMap(response['device']);
    final deviceToken = _string(response['device_token']);
    if (current.apiBase != before.apiBase || current.enrolled || current.technicianLoggedIn ||
        bind.mainGetLocalOption(key: kExantasEnrollmentPending) != marker ||
        (await bind.mainGetMyId()).trim() != peerId || deviceToken.isEmpty ||
        device['customer_id'] != preview.customerId || device['enrollment_link_id'] != preview.enrollmentId) {
      throw StateError('Η σύνδεση δεν επιβεβαιώθηκε για αυτόν τον υπολογιστή.');
    }
    final policy = _decodeMap(response['policy']);
    if ((policy['unattended_enabled'] == true) != preview.unattended) {
      throw StateError('Η πολιτική πρόσβασης άλλαξε. Επικοινωνήστε με την υποστήριξη.');
    }
    // Persist the confirmed metadata before the grant. Explicit completion can
    // repair interrupted local writes without redeeming another enrollment use.
    final grantedMarker = jsonEncode({..._decodeMap(marker),
      'device_id': _string(device['id']), 'policy': policy});
    await bind.mainSetLocalOption(key: kExantasEnrollmentPending, value: grantedMarker);
    await _setSecretLocalOption(kExantasDeviceToken, deviceToken);
    await _completeDeviceEnrollment();
    return loadStatus();
  }

  Future<void> completeDeviceEnrollment() => _nativeFence.run(_completeDeviceEnrollment);

  Future<void> _completeDeviceEnrollment() async {
    final status = await loadStatus();
    final marker = bind.mainGetLocalOption(key: kExantasEnrollmentPending);
    final attempt = _decodeMap(marker);
    nativeApiOrigin(status.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    if (!status.enrolled || status.technicianLoggedIn || marker.isEmpty ||
        attempt['api_base'] != status.apiBase ||
        attempt['peer_id'] != (await bind.mainGetMyId()).trim()) {
      throw StateError('Δεν επιβεβαιώθηκε η εκκρεμής εγκατάσταση.');
    }
    final policy = _decodeMap(attempt['policy']);
    if (_string(attempt['device_id']).isEmpty || attempt['unattended_enabled'] is! bool ||
        policy['unattended_enabled'] != attempt['unattended_enabled']) {
      throw StateError('Δεν επιβεβαιώθηκαν οι ρυθμίσεις εγκατάστασης.');
    }
    await bind.mainSetLocalOption(key: kExantasDeviceId, value: _string(attempt['device_id']));
    await bind.mainSetLocalOption(key: kExantasDeviceCustomerName, value: _string(attempt['customer_name']));
    await bind.mainSetLocalOption(key: kExantasDevicePolicy, value: jsonEncode(policy));
    if (policy['unattended_enabled'] == true) {
      var password = await _getSecretLocalOption(kExantasEnrollmentPassword);
      if (password.isEmpty) {
        password = _generatePassword();
        await _setSecretLocalOption(kExantasEnrollmentPassword, password);
      }
      if (!await bind.mainSetPermanentPasswordWithResult(password: password)) {
        throw StateError('Δεν ολοκληρώθηκε η ρύθμιση πρόσβασης.');
      }
      await bind.mainSetOption(key: 'verification-method', value: kUseBothPasswords);
      // Explicit resume uses the same persisted per-device password. A lost
      // response does not generate another password or clear existing access.
      final credentialReply = await http.post(
        Uri.parse('${status.apiBase}/rustdesk-devices/credential'),
        headers: _headers(status.deviceToken),
        body: jsonEncode({'unattended_password': password}),
      ).timeout(const Duration(seconds: 20));
      _decodeResponse(credentialReply.statusCode, credentialReply.body);
    } else {
      await bind.mainSetOption(key: 'verification-method', value: kUseTemporaryPassword);
    }
    final current = await loadStatus();
    if (current.deviceToken != status.deviceToken || current.apiBase != status.apiBase ||
        (await bind.mainGetMyId()).trim() != attempt['peer_id'] ||
        bind.mainGetLocalOption(key: kExantasEnrollmentPending) != marker) {
      throw StateError('Η κατάσταση του υπολογιστή άλλαξε.');
    }
    if (attempt['automatic'] == true) {
      final reply = await http.post(Uri.parse('${status.apiBase}/rustdesk-devices/activation-complete'),
        headers: _headers(status.deviceToken), body: jsonEncode({'device_id': attempt['device_id'], 'peer_id': attempt['peer_id']}),
      ).timeout(const Duration(seconds: 20));
      if ([401,403,409].contains(reply.statusCode) && bind.mainGetLocalOption(key: kExantasEnrollmentPending) == marker) {
        await bind.mainSetLocalOption(key: kExantasEnrollmentPending, value: jsonEncode({...attempt, 'automatic_retry_allowed': false}));
      }
      final acknowledged = _decodeResponse(reply.statusCode, reply.body);
      if (acknowledged['device_id'] != attempt['device_id'] || acknowledged['peer_id'] != attempt['peer_id'] ||
          acknowledged['activation_status'] != 'active') throw StateError('Δεν επιβεβαιώθηκε η ενεργοποίηση από το Office.');
      final afterAck = await loadStatus();
      if (afterAck.deviceToken != status.deviceToken || afterAck.apiBase != status.apiBase ||
          (await bind.mainGetMyId()).trim() != attempt['peer_id'] || bind.mainGetLocalOption(key: kExantasEnrollmentPending) != marker) {
        throw StateError('Η κατάσταση του υπολογιστή άλλαξε.');
      }
    }
    await bind.mainSetLocalOption(key: kExantasEnrollmentPending, value: '');
    await _setSecretLocalOption(kExantasEnrollmentPassword, '');
    notifyAccountChanged();
  }

  Future<ExantasCompanionStatus> loginTechnician(String email, String password) =>
      _nativeFence.run(() => _loginTechnician(email, password));

  Future<ExantasCompanionStatus> _loginTechnician(
      String email, String password) async {
    nativeApiOrigin(apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    if (bind.mainGetLocalOption(key: kExantasEnrollmentPending).isNotEmpty) {
      throw StateError('Ολοκληρώστε πρώτα την εκκρεμή εγκατάσταση πελάτη.');
    }
    if ((Platform.isWindows || Platform.isAndroid) && bind.mainGetLocalOption(key: 'access_token').isNotEmpty) {
      throw StateError('Αποσυνδεθείτε πρώτα από τον ξεχωριστό λογαριασμό RustDesk.');
    }
    if (Platform.isAndroid) await _secureStore.protectAsync('office-storage-check');
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.trim().isEmpty) {
      throw Exception('Email and password are required.');
    }

    final loginBody = <String, dynamic>{'email': normalizedEmail, 'password': password};
    if (Platform.isAndroid) {
      const key = 'exantas.office.android_login_instance';
      var installation = bind.mainGetLocalOption(key: key);
      if (installation.isEmpty) {
        installation = Uuid().v4();
        await bind.mainSetLocalOption(key: key, value: installation);
      }
      loginBody['client_instance_id'] = installation;
    }
    // Existing native staff login isolates this installation from Web and
    // Windows clients. Its transient JWT is used only for the initial pairing.
    final login = await _post(Platform.isAndroid ? '/desktop/auth/login' : '/admin/auth/login', loginBody);
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
    if (Platform.isAndroid) await _setSecretLocalOption(kExantasAndroidStaffLease, '');
    if (Platform.isWindows || Platform.isAndroid) await _ensureNativeReady(force: true);
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
    if (Platform.isAndroid) await _setSecretLocalOption(kExantasAndroidStaffLease, '');
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
    if ((!Platform.isWindows && !Platform.isAndroid) || before.companion.isEmpty) return;
    if (before.actor.isEmpty) throw StateError('Απαιτείται νέα είσοδος στο Office.');
    if (!force && bind.mainGetLocalOption(key: kExantasNativeConfirm).isNotEmpty) {
      throw StateError('Ελέγξτε τη σύνδεση και πατήστε Επιβεβαίωση RustDesk. Δεν έγινε αυτόματη επανάληψη.');
    }
    nativeApiOrigin(before.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    final nativeApi = nativeApiOrigin(await bind.mainGetApiServer());
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiry = int.tryParse(bind.mainGetLocalOption(key: kExantasNativeExpiry)) ?? 0;
    if (!force && expiry > now + 90 && bind.mainGetLocalOption(key: kExantasNativeReady) == 'Y') return;
    String? androidSourceUuid;
    if (Platform.isAndroid) {
      androidSourceUuid = await bind.mainGetUuid();
      await prepareAndroidOfficeSource(before: before, current: _nativeIdentity,
        nativeApi: nativeApi, deviceUuid: androidSourceUuid,
        version: await bind.mainGetVersion(),
        send: (uri, headers, body) => http.post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 12)));
    }
    // Persist the ambiguity fence before sending. A lost reply or restart must
    // require an explicit retry instead of silently repeating an issuance.
    await bind.mainSetLocalOption(key: kExantasNativeConfirm, value: 'Y');
    await _nativeFence.exchange(
      before: before, current: _nativeIdentity, nativeApi: nativeApi,
      now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      request: () async => await _post('/rustdesk-companion/native-session',
        {'device_uuid': androidSourceUuid ?? await bind.mainGetUuid()}, bearerToken: before.companion)
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
          'install_mode': isRunningInPortableMode() ? 'portable' : 'unknown',
          'platform': 'windows',
        },
        bearerToken: status.deviceToken);
  }

  Future<String> _androidStaffToken(ExantasCompanionStatus status) async {
    final identity = ExantasNativeIdentity(status.apiBase, status.officeUserId,
      status.companionToken, (await bind.mainGetMyId()).trim());
    if (!status.technicianLoggedIn || identity.actor.isEmpty) throw StateError('Απαιτείται είσοδος στο Office.');
    final cached = cachedOfficeStaffToken(_decodeMap(await _getSecretLocalOption(kExantasAndroidStaffLease)),
      identity, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    if (cached.isNotEmpty) return cached;
    final pending = _androidStaffRefresh;
    if (pending != null) {
      await pending;
      _requireSameCompanion(status, await loadStatus());
      final renewed = cachedOfficeStaffToken(_decodeMap(await _getSecretLocalOption(kExantasAndroidStaffLease)),
        identity, DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (renewed.isEmpty) throw StateError('Η άδεια υποστήριξης άλλαξε. Δοκιμάστε ξανά.');
      return renewed;
    }
    final operation = exchangeOfficeStaffLease(before: identity, current: _nativeIdentity,
      now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      request: () => _post('/rustdesk-companion/staff-session', {}, bearerToken: status.companionToken)
        .timeout(const Duration(seconds: 12)),
      store: (lease) => _setSecretLocalOption(kExantasAndroidStaffLease, jsonEncode(lease)))
      .then((lease) => lease['access_token'] as String);
    _androidStaffRefresh = operation;
    try { return await operation; }
    finally { if (identical(_androidStaffRefresh, operation)) _androidStaffRefresh = null; }
  }

  /// Android renews support-only Office grants from the existing persistent
  /// pairing. Expiration/offline errors never clear login or retry a financial POST.
  Future<Map<String, dynamic>> androidOfficeRequest(String path, {Map<String, dynamic>? body, String? expectedOwner, String? expectedApi}) async {
    if (!Platform.isAndroid) throw UnsupportedError('Android Office request');
    if (!path.startsWith('/support-workflow/') && !path.startsWith('/rustdesk-reports/customers')) {
      throw ArgumentError('Unsupported Office path');
    }
    final before = await loadStatus();
    if ((expectedOwner != null && before.officeUserId != expectedOwner) ||
        (expectedApi != null && before.apiBase != expectedApi)) throw StateError('Η σύνδεση Office άλλαξε.');
    nativeApiOrigin(before.apiBase.replaceFirst(RegExp(r'/api/v1/?$'), ''));
    final token = await _androidStaffToken(before);
    if (!before.technicianLoggedIn || before.officeUserId.isEmpty || token.isEmpty) {
      throw StateError('Απαιτείται νέα είσοδος στο Office.');
    }
    _requireSameCompanion(before, await loadStatus());
    final uri = Uri.parse('${before.apiBase}$path');
    final response = await (body == null
      ? http.get(uri, headers: _headers(token))
      : http.post(uri, headers: _headers(token), body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    _requireSameCompanion(before, await loadStatus());
    return _decodeResponse(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> bindNativeLaunch(Map<String, dynamic> record) async {
    final before = await loadStatus();
    _requireExpectedCompanion(before, record['owner'] as String, record['api'] as String);
    final response = await http.post(Uri.parse('${before.apiBase}/rustdesk-companion/sessions/bind-launch'),
      headers: _headers(before.companionToken), body: jsonEncode({
        ...Map<String,dynamic>.from(record['launch'] as Map),
        for (final key in ['peer_id', 'from_peer', 'rustdesk_session_id']) key: record[key],
      })).timeout(const Duration(seconds: 15));
    _requireSameCompanion(before, await loadStatus());
    return _decodeResponse(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> submitSessionClose(Map<String, dynamic> record) async {
    final before = await loadStatus();
    _requireExpectedCompanion(before, record['owner'] as String, record['api'] as String);
    final response = await http.post(Uri.parse('${before.apiBase}/rustdesk-companion/sessions/close'),
      headers: _headers(before.companionToken), body: jsonEncode({
        for (final key in ['event_id', 'peer_id', 'from_peer', 'rustdesk_session_id', 'ended_at']) key: record[key],
      })).timeout(const Duration(seconds: 15));
    _requireSameCompanion(before, await loadStatus());
    return _decodeResponse(response.statusCode, response.body);
  }

  Future<List<Map<String, dynamic>>> pendingSessions({
    bool includeLegacyQueue = false,
    bool includeWorkflowSessions = false,
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
      if (includeWorkflowSessions && Platform.isAndroid) return sessions;
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
    return decodeExantasOfficeResponse(statusCode, body, androidSupport: Platform.isAndroid);
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
    var value = (await _secureStore.unprotectAsync(storedValue)).trim();
    if (Platform.isAndroid && key == kExantasCompanionToken) {
      final scoped = _decodeMap(value);
      if (scoped['office_api_base'] != apiBase || scoped['token'] is! String) {
        throw StateError('Η αποθηκευμένη σύνδεση ανήκει σε άλλο Office.');
      }
      value = scoped['token'] as String;
    }
    if (value.isNotEmpty && !_secureStore.isProtected(storedValue)) {
      await _setSecretLocalOption(key, value);
    }
    return value;
  }

  Future<void> _setSecretLocalOption(String key, String value) async {
    final plain = Platform.isAndroid && key == kExantasCompanionToken && value.trim().isNotEmpty
      ? jsonEncode({'office_api_base': apiBase, 'token': value.trim()}) : value.trim();
    final protectedValue = await _secureStore.protectAsync(plain);
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
