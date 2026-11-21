import 'dart:async';
import 'dart:io';

import 'exantas_field_visit.dart';
import 'exantas_office_response.dart';

/// Owner/API pair a request must still match when it is sent (the Office
/// account may change while the app is open).
class FvScope {
  const FvScope(this.owner, this.api);
  final String owner, api;
  @override
  bool operator ==(Object other) =>
      other is FvScope && other.owner == owner && other.api == api;
  @override
  int get hashCode => Object.hash(owner, api);
}

typedef FvGet = Future<Map<String, dynamic>> Function(String path, FvScope? scope);
typedef FvPost = Future<Map<String, dynamic>> Function(
    String path, Map<String, dynamic> body, FvScope? scope);

/// True when the deployed Office has no field-visit routes or has the feature
/// switched off: the mobile entry point must stay hidden.
bool fvIsFeatureOff(Object e) {
  if (e is ExantasOfficeRejection) {
    return (e.statusCode == 404) ||
        (e.statusCode == 409 && e.code == 'field_visits_unavailable');
  }
  // androidOfficeRequest turns "Route not found." into a plain Exception.
  return e.toString().contains('χρειάζεται ενημέρωση');
}

bool fvIsOfflineError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e.runtimeType.toString() == 'ClientException';

/// Thin POST/GET wrappers over `ExantasCompanionService.androidOfficeRequest`
/// (injected as [get]/[post] so this file stays free of the native bridge).
/// Every mutation is POST; paths all start with `/support-workflow/`.
class ExantasFieldVisitApi {
  ExantasFieldVisitApi({required this.get, required this.post});
  final FvGet get;
  final FvPost post;

  static const base = '/support-workflow/field-visits';

  static String savePath(String id) => '$base/$id/save';
  static String attendancePath(String id) => '$base/$id/attendance';
  static String paymentPath(String id) => '$base/$id/payments';
  static String photoRequestPath(String id) => '$base/$id/photos/request';
  static String photoConfirmPath(String id, String photoId) =>
      '$base/$id/photos/$photoId/confirm';
  static String closePath(String id) => '$base/$id/close';
  static String cancelPath(String id) => '$base/$id/cancel';
  static String previewPath(String id) => '$base/$id/charge-preview';
  static String appointmentCreatePath() => '$base/appointments';
  static String appointmentSavePath(String id) => '$base/$id/appointment';
  static String equipmentSavePath() => '$base/equipment';
  static String draftCustomerPath() => '$base/draft-customers';
  static String workCreatePath() => '$base/work-items';
  static String recoverPath(String key) => '/support-workflow/requests/$key';

  /// Once per session. 404/409 (and any non-enabled answer) = feature off.
  Future<bool> capabilities(FvScope? scope) async {
    try {
      final r = await get('$base/capabilities', scope);
      return r['enabled'] == true;
    } catch (e) {
      if (fvIsFeatureOff(e)) return false;
      rethrow;
    }
  }

  Future<FvConfig> config(FvScope? scope) async =>
      FvConfig.fromJson(await get('$base/config', scope));

  /// One page of VisitSummary rows plus the server clock for the next pull.
  Future<({List<Map<String, dynamic>> items, int? nextPage, String? serverTime})>
      list({String? updatedSince, int page = 1, int pageSize = 100, FvScope? scope}) async {
    final q = [
      'page=$page',
      'page_size=$pageSize',
      if (updatedSince != null) 'updated_since=${Uri.encodeQueryComponent(updatedSince)}',
    ].join('&');
    final r = await get('$base?$q', scope);
    final next = r['next_page'];
    return (
      items: [
        for (final e in (r['items'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e)
      ],
      nextPage: next is num ? next.toInt() : null,
      serverTime: r['server_time'] is String ? r['server_time'] as String : null
    );
  }

  Future<Map<String, dynamic>> getVisit(String id, FvScope? scope) async {
    final r = await get('$base/$id', scope);
    final v = r['visit'] ?? r;
    return Map<String, dynamic>.from(v as Map);
  }

  Future<List<Map<String, dynamic>>> calendar(DateTime from, DateTime to, FvScope? scope) async {
    final r = await get(
        '$base/calendar?from=${Uri.encodeQueryComponent(fvIso(from))}&to=${Uri.encodeQueryComponent(fvIso(to))}',
        scope);
    return [
      for (final e in (r['events'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  Future<List<Map<String, dynamic>>> workList(String? customerId, FvScope? scope) async {
    final q = customerId == null ? '' : '?customer_id=$customerId';
    final r = await get('$base/work-items$q', scope);
    return [
      for (final e in (r['items'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  Future<List<FvEquipment>> equipmentList(
      {String? customerId, String? draftCustomerId, String? barcode, String? q, FvScope? scope}) async {
    final params = [
      if (customerId != null) 'customer_id=$customerId',
      if (draftCustomerId != null) 'draft_customer_id=$draftCustomerId',
      if (barcode != null) 'barcode=${Uri.encodeQueryComponent(barcode)}',
      if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
    ].join('&');
    final r = await get('$base/equipment?$params', scope);
    return [
      for (final e in (r['items'] as List? ?? const []))
        if (e is Map) FvEquipment.fromJson({...Map<String, dynamic>.from(e), 'synced': true})
    ];
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query, FvScope? scope) async {
    final r = await get(
        '/rustdesk-reports/customers?status=active&page_size=50&search=${Uri.encodeQueryComponent(query.trim())}',
        scope);
    return [
      for (final e in (r['items'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  /// Read-only server estimate; never a close gate (the close is offline).
  Future<Map<String, dynamic>> chargePreview(
          String id, FvChargeSource source, int discountBps, FvScope? scope) =>
      post(previewPath(id), {'charge_source': source.wire, 'discount_bps': discountBps}, scope);

  /// GET-only recovery of a financial request (`supportV2Recover`).
  Future<Map<String, dynamic>> recover(String key, FvScope? scope) =>
      get(recoverPath(key), scope);
}
