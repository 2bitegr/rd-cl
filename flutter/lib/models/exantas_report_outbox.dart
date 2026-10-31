import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'exantas_companion_model.dart';
import 'exantas_secure_store.dart';
import 'exantas_session_report.dart';
import 'platform_model.dart';

// Owned by the main window. Remote windows send lifecycle events to it.
class ExantasReportOutbox {
  static final instance = ExantasReportOutbox();
  Future<void> Function(Map<String, dynamic>)? openReport;
  final Map<String, Map<String, dynamic>> _rows = {};
  Future<void>? _loading;
  Directory? _directory;
  bool _syncing = false;
  String? syncError;
  Future<void> _writes = Future.value();
  final Map<String, Future<Map<String, dynamic>?>> _starts = {};
  final _service = ExantasCompanionService();
  static const _store = ExantasSecureStore();

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final root = await getApplicationSupportDirectory();
    _directory = await Directory('${root.path}/office-reports').create(recursive: true);
    await for (final file in _directory!.list()) {
      if (file is File && file.path.endsWith('.json')) {
        final row = (jsonDecode(await _store.unprotectAsync(await file.readAsString())) as Map)
            .cast<String, dynamic>();
        _rows[row['id'] as String] = row;
      }
    }
  }

  Future<void> _write(Map<String, dynamic> incoming) {
    final operation = _writes.then((_) => _writeNow(incoming));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _writeNow(Map<String, dynamic> incoming) async {
    final row = mergeExantasReportUpdate(_rows[incoming['id']], incoming);
    final id = row['id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
      throw StateError('Invalid local report identifier');
    }
    final file = File('${_directory!.path}/$id.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(await _store.protectAsync(jsonEncode(row)), flush: true);
    await temporary.rename(file.path);
    _rows[id] = row;
  }

  Future<List<Map<String, dynamic>>> rows() async {
    await load();
    final status = await _service.loadStatus();
    if (!status.technicianLoggedIn) return [];
    final rows = _rows.values.where((row) =>
        belongsToExantasOfficeScope(
            row,
            loggedIn: status.technicianLoggedIn,
            officeUserId: status.officeUserId,
            apiBase: status.apiBase) &&
        row['workflow_contract_version'] != 2)
        .map((row) => Map<String, dynamic>.from(row)).toList();
    rows.sort((a, b) => (b['started_at'] as String).compareTo(a['started_at'] as String));
    return rows;
  }

  Future<Map<String, dynamic>?> started(Map<String, dynamic> event) =>
      _starts.putIfAbsent(event['local_session'] as String, () => _started(event));

  Future<Map<String, dynamic>?> _started(Map<String, dynamic> event) async {
    await load();
    final status = await _service.loadStatus();
    if (!status.technicianLoggedIn || status.officeUserId.isEmpty) return null;
    final existing = _rows.values.where((row) => row['local_session'] == event['local_session']);
    if (existing.isNotEmpty) {
      final row = existing.first;
      if (!belongsToExantasOfficeScope(row,
          loggedIn: status.technicianLoggedIn,
          officeUserId: status.officeUserId,
          apiBase: status.apiBase)) {
        return null;
      }
      if (row['workflow_contract_version'] != 2 &&
          (row['state'] == 'active' || row['state'] == 'draft')) {
        final context = await _lookupV2Context(event,
            expectedOwner: row['owner']?.toString(),
            expectedApi: row['api']?.toString());
        if (context != null) {
          return _rememberV2Source(
              event: event,
              owner: row['owner'] as String,
              api: row['api'] as String,
              fromPeer: row['from_peer']?.toString() ?? '',
              context: context,
              existingId: row['id'] as String);
        }
      }
      return row['workflow_contract_version'] == 2 ? null : row;
    }
    final fromPeer = (await bind.mainGetMyId()).trim();
    final context = await _lookupV2Context(event,
        fromPeer: fromPeer,
        expectedOwner: status.officeUserId,
        expectedApi: status.apiBase);
    final current = await _service.loadStatus();
    _requireSameCompanion(status, current);
    if (!shouldCaptureLegacyExantasSession(context)) {
      return _rememberV2Source(
          event: event,
          owner: status.officeUserId,
          api: status.apiBase,
          fromPeer: fromPeer,
          context: context!);
    }
    final row = <String, dynamic>{
      ...event,
      'id': Uuid().v4(),
      'owner': status.officeUserId,
      'from_peer': fromPeer,
      'api': status.apiBase,
      'technician_name': status.technicianName,
      'state': 'active',
      'local_report': true,
      'workflow_contract_version': 1,
    };
    await _write(row);
    return row;
  }

  Future<Map<String, dynamic>?> ended(Map<String, dynamic> event) async {
    await _starts[event['local_session']];
    await load();
    final matches = _rows.values.where((row) => row['local_session'] == event['local_session']);
    final status = await _service.loadStatus();
    if (matches.length == 1 &&
        !belongsToExantasOfficeScope(matches.single,
            loggedIn: status.technicianLoggedIn,
            officeUserId: status.officeUserId,
            apiBase: status.apiBase)) {
      return null;
    }
    if (matches.length == 1 && matches.single['workflow_contract_version'] == 2) {
      await _refreshV2Source(Map<String, dynamic>.from(matches.single), event: event, force: true);
      return null;
    }
    if (matches.length == 1 &&
        (matches.single['state'] == 'active' || matches.single['state'] == 'draft')) {
      final context = await _lookupV2Context(event,
          fromPeer: matches.single['from_peer']?.toString(),
          expectedOwner: matches.single['owner']?.toString(),
          expectedApi: matches.single['api']?.toString());
      if (context != null) {
        await _rememberV2Source(
            event: event,
            owner: matches.single['owner'] as String,
            api: matches.single['api'] as String,
            fromPeer: matches.single['from_peer']?.toString() ?? '',
            context: context,
            existingId: matches.single['id'] as String);
        return null;
      }
    }
    if (matches.length != 1 || !canPromptExantasReport(matches.single['state'])) return null;
    // Office can confirm a disconnect before the user closes its remaining view.
    // That draft still needs the immediate close prompt.
    if (matches.single['state'] == 'draft') {
      return Map<String, dynamic>.from(matches.single);
    }
    final row = Map<String, dynamic>.from(matches.single);
    final finalConnectionId = resolveExantasRustDeskSessionId(
        row['rustdesk_session_id'], event['rustdesk_session_id']);
    if (finalConnectionId.isNotEmpty) {
      row['rustdesk_session_id'] = finalConnectionId;
    }
    row['ended_at'] = event['ended_at'];
    row['duration_seconds'] = DateTime.parse(row['ended_at']).difference(
        DateTime.parse(row['started_at'])).inSeconds;
    row['state'] = 'draft';
    await _write(row);
    return row;
  }

  Future<void> save(String id, ExantasSessionOutcome outcome, String note) async {
    await load();
    buildExantasSessionReportCommand(outcome, note);
    final row = Map<String, dynamic>.from(_rows[id]!);
    final status = await _service.loadStatus();
    if (row['owner'] != status.officeUserId || row['api'] != status.apiBase) {
      throw StateError('Ο λογαριασμός άλλαξε. Η αναφορά ανήκει στον αρχικό τεχνικό.');
    }
    if (row['workflow_contract_version'] == 2) {
      throw StateError('Η αναφορά ανήκει στη ροή εργασίας του Office.');
    }
    if (row['state'] != 'draft') throw StateError('Η αναφορά έχει ήδη αποθηκευτεί.');
    row.addAll({'outcome': outcome.name, 'note': note, 'state': 'queued'});
    await _write(row);
  }

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _refreshV2Markers();
      final local = await rows();
      if (local.isEmpty) return;
      final pending = await _service.pendingSessions(includeLegacyQueue: true).timeout(const Duration(seconds: 20));
      syncError = null;
      for (final snapshot in local) {
        final row = Map<String, dynamic>.from(_rows[snapshot['id']]!);
        if (row['state'] == 'queued') {
          Map<String, dynamic>? marker;
          for (final candidate in _rows.values) {
            if (quarantineLegacyExantasReportFromMarker(row, candidate) != null) {
              marker = candidate;
              break;
            }
          }
          if (marker != null) {
            final held = quarantineLegacyExantasReportFromMarker(row, marker)!;
            held['error'] = 'Η συνεδρία έχει νεότερη συσχέτιση στο Office. Η παλιά αναφορά διατηρείται τοπικά για έλεγχο.';
            await _write(held);
            continue;
          }
        }
        if (row['state'] == 'synced' || row['state'] == 'review') continue;
        if (row['state'] == 'queued') {
          final current = await _service.loadStatus();
          if (!belongsToExantasOfficeScope(row,
              loggedIn: current.technicianLoggedIn,
              officeUserId: current.officeUserId,
              apiBase: current.apiBase)) {
            continue;
          }
          try {
            final context = await _lookupV2Context(row,
                expectedOwner: row['owner']?.toString(),
                expectedApi: row['api']?.toString());
            if (!maySubmitLegacyExantasReport(context)) {
              if (context != null) {
                final quarantined = quarantineLegacyExantasReport(row, context);
                if (quarantined != null) {
                  quarantined['error'] = 'Η συνεδρία έχει νεότερη συσχέτιση στο Office. Η παλιά αναφορά διατηρείται τοπικά για έλεγχο.';
                  await _write(quarantined);
                }
              }
              continue;
            }
          } catch (_) {
            row['error'] = 'Δεν επιβεβαιώθηκε ο έλεγχος συσχέτισης στο Office. Η παλιά αναφορά παραμένει τοπικά.';
            await _write(row);
            continue;
          }
        }
        final matches = pending.where((remote) => matchesExantasSession(row, remote)).toList();
        if (row['remote_id'] == null && matches.length == 1) {
          final remote = matches.single;
          row.addAll({'remote_id': remote['id'], 'customer_name': remote['customer_name'],
            'customer_device_label': remote['customer_device_label']});
          if (row['state'] == 'active') {
            row.addAll({'state': 'draft', 'ended_at': remote['ended_at'],
              'duration_seconds': remote['duration_seconds']});
          }
          await _write(row);
        }
        if (matches.length > 1) {
          row['error'] = 'Βρέθηκαν πολλαπλές αντιστοιχίσεις. Η αναφορά διατηρείται για έλεγχο.';
          await _write(row);
          continue;
        }
        if (row['state'] != 'queued' || row['remote_id'] == null) continue;
        final current = await _service.loadStatus();
        if (current.officeUserId != row['owner'] || current.apiBase != row['api']) continue;
        try {
          final context = await _lookupV2Context(row,
              expectedOwner: row['owner']?.toString(),
              expectedApi: row['api']?.toString());
          if (!maySubmitLegacyExantasReport(context)) {
            if (context != null) {
              final quarantined = quarantineLegacyExantasReport(row, context);
              if (quarantined != null) {
                quarantined['error'] = 'Η συνεδρία έχει νεότερη συσχέτιση στο Office. Η παλιά αναφορά διατηρείται τοπικά για έλεγχο.';
                await _write(quarantined);
              }
            }
            continue;
          }
          final outcome = ExantasSessionOutcome.values.byName(row['outcome']);
          final response = await _service.submitSessionReport(row['remote_id'],
              outcome, row['note'],
              idempotencyKey: 'local-${row['id']}',
              expectedOfficeUserId: row['owner'], expectedApiBase: row['api'])
              .timeout(const Duration(seconds: 20));
          if (confirmsExantasReport(outcome, response['action'])) {
            row['state'] = 'synced';
            row.remove('error');
          } else {
            row['state'] = 'review';
            row['error'] = 'Χρειάζεται έλεγχος στο Office: δεν επιβεβαιώθηκε η ίδια αναφορά. Το σχόλιο διατηρείται τοπικά.';
          }
          await _write(row);
        } catch (_) {
          row['error'] = 'Δεν επιβεβαιώθηκε η παραλαβή. Θα γίνει νέα προσπάθεια.';
          await _write(row);
        }
      }
    } catch (_) {
      syncError = 'Δεν ολοκληρώθηκε ο έλεγχος συγχρονισμού. Οι αναφορές διατηρούνται τοπικά.';
    } finally {
      _syncing = false;
    }
  }

  void _requireSameCompanion(ExantasCompanionStatus before, ExantasCompanionStatus after) {
    if (before.officeUserId != after.officeUserId ||
        before.apiBase != after.apiBase ||
        before.companionToken != after.companionToken) {
      throw StateError('Office account changed during the session request.');
    }
  }

  Future<ExantasWorkContext?> _lookupV2Context(Map<String, dynamic> source,
      {String? fromPeer, String? expectedOwner, String? expectedApi}) async {
    final before = await _service.loadStatus();
    if ((expectedOwner != null && before.officeUserId != expectedOwner) ||
        (expectedApi != null && before.apiBase != expectedApi)) {
      throw StateError('Office account changed before workflow lookup.');
    }
    final actorPeer = fromPeer?.trim().isNotEmpty == true
        ? fromPeer!.trim()
        : (await bind.mainGetMyId()).trim();
    final context = await _service.lookupWorkContext(
        peerId: source['peer_id']?.toString().trim() ?? '',
        fromPeer: actorPeer,
        rustDeskSessionId: source['rustdesk_session_id']?.toString());
    _requireSameCompanion(before, await _service.loadStatus());
    return context;
  }

  Future<Map<String, dynamic>?> _rememberV2Source({
    required Map<String, dynamic> event,
    required String owner,
    required String api,
    required String fromPeer,
    required ExantasWorkContext context,
    String? existingId,
  }) async {
    final row = <String, dynamic>{
      'id': existingId ?? Uuid().v4(),
      'owner': owner,
      'api': api,
      'from_peer': fromPeer,
      'peer_id': (event['peer_id'] as String? ?? '').trim(),
      'local_session': event['local_session'],
      'rustdesk_session_id': _nonZeroId(event['rustdesk_session_id']),
      'workflow_contract_version': 2,
      'workflow_classification': context.classification.name,
      'work_item_id': context.workItemId,
      'work_revision': context.workRevision,
      'remote_session_id': context.remoteSessionId,
      'state': _v2State(context.classification),
      'last_context_checked_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _write(row);
    return null;
  }

  Future<void> _refreshV2Source(Map<String, dynamic> row,
      {Map<String, dynamic>? event, bool force = false}) async {
    if (row['workflow_classification'] == ExantasWorkContextClassification.excluded.name) return;
    final before = await _service.loadStatus();
    if (!belongsToExantasOfficeScope(row,
        loggedIn: before.technicianLoggedIn,
        officeUserId: before.officeUserId,
        apiBase: before.apiBase)) {
      return;
    }
    final checked = DateTime.tryParse(row['last_context_checked_at']?.toString() ?? '');
    if (!force && checked != null && DateTime.now().toUtc().difference(checked) < const Duration(minutes: 5)) return;
    final sessionId = _nonZeroId(event?['rustdesk_session_id'] ?? row['rustdesk_session_id']);
    try {
      final context = await _service.lookupWorkContext(
          peerId: (event?['peer_id'] ?? row['peer_id'])?.toString().trim() ?? '',
          fromPeer: row['from_peer']?.toString().trim() ?? '',
          rustDeskSessionId: sessionId);
      final current = await _service.loadStatus();
      if (!belongsToExantasOfficeScope(row,
          loggedIn: current.technicianLoggedIn,
          officeUserId: current.officeUserId,
          apiBase: current.apiBase) ||
          current.companionToken != before.companionToken ||
          context == null) {
        return;
      }
      row.addAll({
        'workflow_classification': context.classification.name,
        'work_item_id': context.workItemId,
        'work_revision': context.workRevision,
        'remote_session_id': context.remoteSessionId,
        'state': _v2State(context.classification),
        'last_context_checked_at': DateTime.now().toUtc().toIso8601String(),
        if (sessionId.isNotEmpty) 'rustdesk_session_id': sessionId,
      });
      await _write(row);
    } catch (_) {
      final current = await _service.loadStatus();
      if (belongsToExantasOfficeScope(row,
              loggedIn: current.technicianLoggedIn,
              officeUserId: current.officeUserId,
              apiBase: current.apiBase) &&
          current.companionToken == before.companionToken) {
        await _write(retainExantasV2SuppressionAfterLookupFailure(
            row, DateTime.now().toUtc()));
      }
    }
  }

  Future<void> _refreshV2Markers() async {
    await load();
    final status = await _service.loadStatus();
    if (!status.technicianLoggedIn) return;
    final now = DateTime.now().toUtc();
    final due = _rows.values.where((row) =>
        row['workflow_contract_version'] == 2 &&
        belongsToExantasOfficeScope(row,
            loggedIn: status.technicianLoggedIn,
            officeUserId: status.officeUserId,
            apiBase: status.apiBase) &&
        row['workflow_classification'] != ExantasWorkContextClassification.excluded.name &&
        row['workflow_classification'] != ExantasWorkContextClassification.bound.name &&
        (DateTime.tryParse(row['last_context_checked_at']?.toString() ?? '') == null ||
         now.difference(DateTime.parse(row['last_context_checked_at'] as String)) >= const Duration(minutes: 5)))
        .take(20).toList();
    for (final row in due) {
      await _refreshV2Source(Map<String, dynamic>.from(row));
    }
  }

  String _v2State(ExantasWorkContextClassification classification) => switch (classification) {
    ExantasWorkContextClassification.excluded => 'v2_excluded',
    ExantasWorkContextClassification.bound => 'v2_bound',
    ExantasWorkContextClassification.unassigned || ExantasWorkContextClassification.pendingIdentity => 'v2_pending_identity',
  };

  String _nonZeroId(dynamic value) {
    final id = value?.toString().trim() ?? '';
    return id == '0' ? '' : id;
  }
}
