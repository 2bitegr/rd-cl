import 'dart:async';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'exantas_session_timing.dart';

/// Office read models for the mobile Εργασίες screens. Everything here is
/// display data taken from Office responses. Durations are shown only when
/// Office marks the timing verified; nothing billable or monetary is computed.

/// Europe/Athens wall clock for [instant] (EET UTC+2, EEST UTC+3). The returned
/// value is UTC-flagged and meant only for formatting.
DateTime athensWallClock(DateTime instant) {
  final utc = instant.toUtc();
  DateTime lastSunday(int month) {
    final last = DateTime.utc(utc.year, month + 1, 0);
    return DateTime.utc(utc.year, month, last.day - last.weekday % 7, 1);
  }

  final summer =
      !utc.isBefore(lastSunday(3)) && utc.isBefore(lastSunday(10));
  return utc.add(Duration(hours: summer ? 3 : 2));
}

String formatAthens(DateTime? instant, {bool date = true, bool time = true}) {
  if (instant == null) return '—';
  final wall = athensWallClock(instant);
  return [
    if (date) DateFormat('dd/MM/yyyy').format(wall),
    if (time) DateFormat('HH:mm').format(wall),
  ].join(' ');
}

String formatDurationSeconds(num seconds) {
  final total = seconds.round();
  final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
  if (h > 0) return '$h ω ${m.toString().padLeft(2, '0')} λ';
  return '$m λ ${s.toString().padLeft(2, '0')} δ';
}

String? _text(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
List<Map<String, dynamic>> _maps(dynamic rows) => (rows as List? ?? [])
    .whereType<Map>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();

@immutable
class OfficeWorkCard {
  const OfficeWorkCard(
      {required this.id,
      required this.title,
      required this.customerId,
      required this.customerName,
      required this.branchName,
      required this.status,
      required this.supportState,
      required this.updatedAt});
  final String id, title, customerId, customerName, branchName;
  final String status, supportState;
  final DateTime? updatedAt;

  /// my-day / my-open-work row: `{item:{...}, customer_name, branch_name, updated_at}`.
  static OfficeWorkCard? fromDayRow(Map<String, dynamic> row) {
    final item = row['item'];
    if (item is! Map) return null;
    return _build(Map<String, dynamic>.from(item), row);
  }

  /// supportV2List / workDto row (flat).
  static OfficeWorkCard? fromFlat(Map<String, dynamic> row) =>
      _build(row, row);

  static OfficeWorkCard? _build(
      Map<String, dynamic> item, Map<String, dynamic> outer) {
    final id = _text(item['id']);
    if (id == null) return null;
    return OfficeWorkCard(
        id: id,
        title: _text(item['title']) ?? 'Εργασία χωρίς τίτλο',
        customerId: _text(item['customer_id']) ?? '',
        customerName: _text(outer['customer_name']) ?? '',
        branchName: _text(outer['branch_name']) ?? '',
        status: _text(item['status']) ?? '',
        supportState: _text(item['support_state']) ?? '',
        updatedAt: DateTime.tryParse('${outer['updated_at'] ?? ''}'));
  }
}

enum OfficeLoad { idle, loading, ready, error }

class OfficeFeed<T> {
  const OfficeFeed(
      {this.state = OfficeLoad.idle,
      this.items = const [],
      this.error,
      this.offline = false,
      this.truncated = false,
      this.nextPage});
  final OfficeLoad state;
  final List<T> items;
  final String? error;
  final bool offline, truncated;
  final int? nextPage;
  OfficeFeed<T> copy(
          {OfficeLoad? state,
          List<T>? items,
          String? error,
          bool? offline,
          bool? truncated,
          int? nextPage,
          bool clearError = false}) =>
      OfficeFeed<T>(
          state: state ?? this.state,
          items: items ?? this.items,
          error: clearError ? null : (error ?? this.error),
          offline: offline ?? this.offline,
          truncated: truncated ?? this.truncated,
          nextPage: nextPage ?? this.nextPage);
}

bool isOfflineError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e.runtimeType.toString() == 'ClientException';

String describeOfficeError(Object e) {
  if (isOfflineError(e)) {
    return 'Δεν υπάρχει σύνδεση με το Office. Δοκιμάστε ξανά.';
  }
  return e.toString().replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');
}

@immutable
class WorkDevice {
  const WorkDevice(
      {required this.id,
      required this.peerId,
      required this.label,
      required this.canConnect});
  final String id, peerId, label;
  final bool canConnect;
  Map<String, dynamic> toMap() =>
      {'id': id, 'peer_id': peerId, 'label': label, 'can_connect': canConnect};
}

enum TimelineKind { session, call }

@immutable
class TimelineEntry {
  const TimelineEntry(
      {required this.kind,
      required this.id,
      required this.start,
      required this.end,
      required this.technician,
      required this.computer,
      required this.verified,
      required this.durationSeconds,
      this.callLabel = ''});
  final TimelineKind kind;
  final String id, technician, computer, callLabel;
  final DateTime? start, end;

  /// True only when Office timing is verified (androidSessionVerified).
  final bool verified;
  final num? durationSeconds;
}

class WorkDetail {
  WorkDetail(
      {required this.id,
      required this.title,
      required this.status,
      required this.supportState,
      required this.customerId,
      required this.customerName,
      required this.branchName,
      required this.description,
      required this.canEdit,
      required this.devices,
      required this.timeline,
      required this.rawItem});
  final String id, title, status, supportState, customerId, customerName;
  final String branchName, description;
  final bool canEdit;
  final List<WorkDevice> devices;
  final List<TimelineEntry> timeline;
  final Map<String, dynamic> rawItem;

  /// supportV2Context: item, customer, devices, activities{sessions,calls},
  /// permissions.can_edit.
  static WorkDetail parse(Map<String, dynamic> ctx) {
    final item = Map<String, dynamic>.from(ctx['item'] as Map? ?? {});
    final customer = ctx['customer'] is Map
        ? Map<String, dynamic>.from(ctx['customer'] as Map)
        : <String, dynamic>{};
    final devices = <WorkDevice>[];
    for (final d in _maps(ctx['devices'])) {
      final peer = _text(d['peer_id']);
      if (peer == null) continue;
      devices.add(WorkDevice(
          id: '${d['id'] ?? peer}',
          peerId: peer,
          label: _text(d['label']) ?? peer,
          canConnect: d['can_connect'] == true));
    }
    String labelFor(String? peer) {
      if (peer == null) return '';
      for (final d in devices) {
        if (d.peerId == peer) return d.label == peer ? peer : '${d.label} ($peer)';
      }
      return peer;
    }

    final activities = ctx['activities'] is Map
        ? Map<String, dynamic>.from(ctx['activities'] as Map)
        : <String, dynamic>{};
    final entries = <TimelineEntry>[];
    for (final s in _maps(activities['sessions'])) {
      final verified = androidSessionVerified(s);
      entries.add(TimelineEntry(
          kind: TimelineKind.session,
          id: _text(s['id']) ?? '${entries.length}',
          start: DateTime.tryParse('${s['started_at'] ?? ''}'),
          end: DateTime.tryParse('${s['ended_at'] ?? ''}'),
          technician: _text(s['technician_name']) ?? '',
          computer: labelFor(_text(s['peer_id'])),
          verified: verified,
          durationSeconds: verified ? num.tryParse('${s['duration_seconds']}') : null));
    }
    for (final c in _maps(activities['calls'])) {
      final start = DateTime.tryParse('${c['answered_at'] ?? c['observed_at'] ?? ''}') ??
          DateTime.tryParse('${c['observed_at'] ?? ''}');
      final inbound = c['direction'] == 'inbound' || c['direction'] == 'incoming';
      entries.add(TimelineEntry(
          kind: TimelineKind.call,
          id: _text(c['id']) ?? 'call-${entries.length}',
          start: start,
          end: DateTime.tryParse('${c['ended_at'] ?? ''}'),
          technician: '',
          computer: '',
          verified: false,
          durationSeconds: null,
          callLabel: [
            inbound ? 'Εισερχόμενη κλήση' : 'Εξερχόμενη κλήση',
            _text(inbound ? c['caller_number'] : c['callee_number']) ?? ''
          ].where((e) => e.isNotEmpty).join(' · ')));
    }
    entries.sort((a, b) {
      final x = a.start, y = b.start;
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
      return x.compareTo(y);
    });
    final perms = ctx['permissions'];
    return WorkDetail(
        id: _text(item['id']) ?? '',
        title: _text(item['title']) ?? 'Εργασία χωρίς τίτλο',
        status: _text(item['status']) ?? '',
        supportState: _text(item['support_state']) ?? '',
        customerId: _text(item['customer_id']) ?? '',
        customerName: _text(item['customer_name']) ??
            _text(customer['company_name']) ??
            '',
        branchName: _text(item['branch_name']) ?? '',
        description: _text(item['description']) ?? '',
        canEdit: perms is Map && perms['can_edit'] == true,
        devices: devices,
        timeline: entries,
        rawItem: item);
  }
}

class CustomerDetail {
  const CustomerDetail({required this.devices, required this.works});
  final List<Map<String, dynamic>> devices;
  final List<OfficeWorkCard> works;
}

/// Loads Office work lists. Every async result is checked against the identity
/// epoch ([reset] on account/API change or logout) and a per-feed sequence, so
/// a slow response never overwrites newer state or another account's data.
class ExantasOfficeWork extends ChangeNotifier {
  ExantasOfficeWork(this.get);
  final Future<Map<String, dynamic>> Function(String path) get;
  int _epoch = 0, _today = 0, _open = 0, _customers = 0, _detail = 0, _customer = 0;
  bool _disposed = false;
  int get epoch => _epoch;

  OfficeFeed<OfficeWorkCard> today = const OfficeFeed();
  OfficeFeed<OfficeWorkCard> open = const OfficeFeed();
  OfficeFeed<Map<String, dynamic>> customers = const OfficeFeed();
  String customerQuery = '';

  /// Clears all cached Office data and invalidates every request in flight.
  void reset() {
    _epoch++;
    today = const OfficeFeed();
    open = const OfficeFeed();
    customers = const OfficeFeed();
    customerQuery = '';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadToday() async {
    final epoch = _epoch, seq = ++_today;
    today = today.copy(state: OfficeLoad.loading, clearError: true);
    _notify();
    try {
      final r = await get('/support-workflow/my-day');
      if (epoch != _epoch || seq != _today) return;
      today = OfficeFeed(
          state: OfficeLoad.ready,
          items: _cards(r['items']),
          truncated: r['truncated'] == true);
    } catch (e) {
      if (epoch != _epoch || seq != _today) return;
      today = today.copy(
          state: OfficeLoad.error,
          error: describeOfficeError(e),
          offline: isOfflineError(e));
    }
    _notify();
  }

  Future<void> loadOpen({bool more = false}) async {
    final epoch = _epoch, seq = ++_open;
    final page = more ? (open.nextPage ?? 1) : 1;
    open = open.copy(state: OfficeLoad.loading, clearError: true);
    _notify();
    try {
      final r = await get('/support-workflow/my-open-work?page=$page');
      if (epoch != _epoch || seq != _open) return;
      final fresh = _cards(r['items']);
      final next = r['next_page'];
      final known = more ? open.items : <OfficeWorkCard>[];
      final ids = known.map((c) => c.id).toSet();
      open = OfficeFeed(
          state: OfficeLoad.ready,
          items: [...known, ...fresh.where((c) => !ids.contains(c.id))],
          truncated: r['truncated'] == true,
          nextPage: next is int ? next : null);
    } catch (e) {
      if (epoch != _epoch || seq != _open) return;
      open = open.copy(
          state: OfficeLoad.error,
          error: describeOfficeError(e),
          offline: isOfflineError(e));
    }
    _notify();
  }

  Future<void> searchCustomers(String query) async {
    final epoch = _epoch, seq = ++_customers;
    final q = query.trim();
    customerQuery = q;
    customers = customers.copy(state: OfficeLoad.loading, clearError: true);
    _notify();
    try {
      final r = await get(
          '/rustdesk-reports/customers?status=active&page_size=50&search=${Uri.encodeQueryComponent(q)}');
      if (epoch != _epoch || seq != _customers) return;
      customers = OfficeFeed(state: OfficeLoad.ready, items: _maps(r['items']));
    } catch (e) {
      if (epoch != _epoch || seq != _customers) return;
      customers = customers.copy(
          state: OfficeLoad.error,
          error: describeOfficeError(e),
          offline: isOfflineError(e));
    }
    _notify();
  }

  /// Null when superseded by a newer call or an identity change.
  Future<WorkDetail?> loadDetail(String workId) async {
    final epoch = _epoch, seq = ++_detail;
    final r = await get('/support-workflow/items/${Uri.encodeComponent(workId)}');
    if (epoch != _epoch || seq != _detail) return null;
    return WorkDetail.parse(r);
  }

  Future<CustomerDetail?> loadCustomer(String customerId) async {
    final epoch = _epoch, seq = ++_customer;
    final id = Uri.encodeComponent(customerId);
    final devices = await get('/rustdesk-reports/customers/$id/devices');
    final works = await get('/support-workflow/items?customer_id=$id');
    if (epoch != _epoch || seq != _customer) return null;
    return CustomerDetail(
        devices: _maps(devices['items']), works: _cards(works['items'], flat: true)
            .where((w) => !const ['finalized', 'ignored'].contains(w.supportState))
            .toList());
  }

  List<OfficeWorkCard> _cards(dynamic rows, {bool flat = false}) => [
        for (final r in _maps(rows))
          if ((flat ? OfficeWorkCard.fromFlat(r) : OfficeWorkCard.fromDayRow(r))
              case final card?)
            card
      ];
}
