import 'package:uuid/uuid.dart';
import 'exantas_companion_model.dart';
import 'exantas_lifecycle_outbox.dart';
import 'exantas_session_report.dart';
import 'platform_model.dart';
export 'exantas_native_auth.dart' show normalizeAndroidPeerId;

/// No client duration or price is promoted to Office evidence.
bool androidSessionVerified(Map<String, dynamic> session) {
  final start = DateTime.tryParse('${session['started_at'] ?? ''}');
  final end = DateTime.tryParse('${session['ended_at'] ?? ''}');
  final seconds = num.tryParse('${session['duration_seconds'] ?? ''}');
  return session['timing_quality'] == 'verified' && start != null && end != null &&
      end.isAfter(start) && seconds != null && seconds.isFinite && seconds > 0;
}

/// Auto-open a completion only for its exact native source tuple.
bool androidClosureMatches(Map<String, dynamic> row, Map<String, dynamic>? closure) {
  if (closure == null || closure['rustdesk_session_id'] is! String ||
      closure['rustdesk_session_id'] == '' || closure['rustdesk_session_id'] == '0') return false;
  return ['owner', 'api', 'from_peer', 'peer_id', 'rustdesk_session_id'].every((key) =>
    closure[key] != null && closure[key] == row[key]);
}

class ExantasAndroidSupport {
  ExantasAndroidSupport({ExantasCompanionService? service, ExantasLifecycleOutbox? journal,
    Future<String> Function()? sourcePeer}) : service = service ?? ExantasCompanionService(),
    journal = journal ?? ExantasLifecycleOutbox.instance,
    sourcePeer = sourcePeer ?? (() => bind.mainGetMyId());
  final ExantasCompanionService service;
  final ExantasLifecycleOutbox journal;
  final Future<String> Function() sourcePeer;
  bool _refreshing = false;
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? scope}) => service.androidOfficeRequest(path,
    expectedOwner: scope?['owner'] as String?, expectedApi: scope?['api'] as String?);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {Map<String, dynamic>? scope}) =>
      service.androidOfficeRequest(path, body: body, expectedOwner: scope?['owner'] as String?, expectedApi: scope?['api'] as String?);

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await journal.load();
      final status = await service.loadStatus();
      if (!status.technicianLoggedIn) return;
      // Existing audit import. An empty/delayed result never means zero time.
      final imported = await service.pendingSessions(includeWorkflowSessions: true);
      final from = await _source();
      for (final session in imported) {
        final native = session['rustdesk_session_id'];
        if (native is! String || native.isEmpty || native == '0' || session['from_peer'] != from ||
            session['technician_admin_id'] != status.officeUserId) continue;
        if (journal.queue.records.values.any((r) => r['owner'] == status.officeUserId &&
            r['api'] == status.apiBase && r['from_peer'] == from && r['peer_id'] == session['peer_id'] &&
            r['rustdesk_session_id'] == native)) continue;
        final id = session['id'];
        if (id is! String || !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) continue;
        await journal.queue.capture({'event_id': 'provider-$id', 'local_session': 'provider-$id',
          'owner': status.officeUserId, 'api': status.apiBase, 'from_peer': from,
          'peer_id': session['peer_id'], 'rustdesk_session_id': native,
          'remote_session_id': id, 'started_at': session['started_at'], 'decision': 'later'});
      }
      final rows = journal.queue.records.values.where((r) => r['owner'] == status.officeUserId &&
        r['api'] == status.apiBase && r['from_peer'] == from &&
        (r['financial_operation'] != null || (r['decision'] != 'completed' && r['decision'] != 'excluded'))).toList();
      for (final row in rows) {
        final native = row['rustdesk_session_id']?.toString() ?? '';
        if (native.isEmpty || native == '0') continue;
        var context = await service.lookupWorkContext(peerId: row['peer_id'] as String,
          fromPeer: from, rustDeskSessionId: native);
        if (context == null || context.classification == ExantasWorkContextClassification.pendingIdentity) continue;
        if (context.classification == ExantasWorkContextClassification.excluded) {
          await save(row, {'decision': 'excluded'}); continue;
        }
        final selection = row['mobile_work'];
        if (!context.isV2Bound && selection is Map && context.remoteSessionId != null) {
          context = await service.claimWorkContext(workItemId: selection['work_item_id'] as String,
            remoteSessionId: context.remoteSessionId!, expectedRevision: selection['revision'].toString(),
            idempotencyKey: 'android_claim_${row['event_id']}',
            expectedOfficeUserId: row['owner'] as String, expectedApiBase: row['api'] as String);
        }
        if (context.isV2Bound) {
          if (selection is Map && context.workItemId != selection['work_item_id']) {
            throw StateError('Η συνεδρία ανήκει σε άλλη εργασία. Απαιτείται έλεγχος Office.');
          }
          await save(row, {'remote_session_id': context.remoteSessionId, 'work_item_id': context.workItemId});
          final authoritative = await get('/support-workflow/items/${context.workItemId}', scope: row);
          if (authoritative['item']?['support_state'] == 'finalized' && authoritative['current_report']?['id'] != null &&
              (authoritative['activities']?['sessions'] as List? ?? []).whereType<Map>().any((s) => s['id'] == context!.remoteSessionId)) {
            await save(row, {'decision': 'completed', 'resolved_in_office_report': authoritative['current_report']['id'],
              'resolved_operation': journal.queue.records[row['event_id']]?['financial_operation'], 'financial_operation': null});
          }

        }
      }
    } finally { _refreshing = false; }
  }

  Future<String> _source() async => (await sourcePeer()).trim();

  Future<List<Map<String, dynamic>>> rows() async {
    await journal.load();
    final status = await service.loadStatus();
    final from = await _source();
    return journal.queue.records.values.where((r) => r['owner'] == status.officeUserId &&
      r['api'] == status.apiBase && r['from_peer'] == from && r['kind'] != 'work_creation' &&
      (r['financial_operation'] != null || (r['decision'] != 'completed' && r['decision'] != 'excluded'))).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<Map<String, dynamic>> createWork(String customerId, String title) async {
    await journal.load();
    final status = await service.loadStatus();
    final from = await _source();
    final unresolved = journal.queue.records.values.where((r) => r['kind'] == 'work_creation' &&
      r['owner'] == status.officeUserId && r['api'] == status.apiBase && r['creation_pending'] == true).toList();
    if (unresolved.isNotEmpty) {
      final original = unresolved.first;
      final receipt = await get('/support-workflow/requests/${original['request_key']}', scope: original);
      if (receipt['request']?['state'] != 'applied') {
        throw StateError('Η δημιουργία εργασίας παραμένει ανεπιβεβαίωτη. Ελέγξτε το Office πριν δημιουργήσετε άλλη.');
      }
      final result = Map<String, dynamic>.from(receipt['request']['result'] as Map);
      if (result['item']?['customer_id'] != original['customer_id']) throw StateError('Creation receipt mismatch');
      await save(original, {'creation_pending': false});
      return Map<String, dynamic>.from(result['item'] as Map);
    }
    final id = Uuid().v4();
    final record = <String, dynamic>{'event_id': id, 'local_session': id, 'kind': 'work_creation',
      'owner': status.officeUserId, 'api': status.apiBase, 'from_peer': from,
      'customer_id': customerId, 'creation_pending': true, 'request_key': 'android_create_$id'};
    await journal.queue.capture(record);
    final result = await post('/support-workflow/items', {'customer_id': customerId, 'title': title,
      'support_kind': 'remote_support', 'idempotency_key': record['request_key']}, scope: record);
    if (result['item']?['customer_id'] != customerId) throw StateError('Creation receipt mismatch');
    await save(record, {'creation_pending': false});
    return Map<String, dynamic>.from(result['item'] as Map);
  }

  Future<void> save(Map<String, dynamic> row, Map<String, dynamic> values) async {
    await requireOwner(row);
    await journal.queue.capture({...journal.queue.records[row['event_id']]!, ...values});
  }

  Future<void> later(Map<String, dynamic> row) => save(row, {'decision': 'later'});

  Future<Map<String, dynamic>> work(Map<String, dynamic> row) async {
    await requireOwner(row);
    final id = row['work_item_id'];
    if (id is! String || id.isEmpty) throw StateError('Εκκρεμεί ακριβής αντιστοίχιση στο Office.');
    return get('/support-workflow/items/$id', scope: row);
  }

  Future<void> requireOwner(Map<String, dynamic> row) async {
    final status = await service.loadStatus();
    if (!status.technicianLoggedIn || status.officeUserId != row['owner'] || status.apiBase != row['api'] ||
        await _source() != row['from_peer']) throw StateError('Η σύνδεση Office άλλαξε.');
  }

  Future<Map<String, dynamic>> preview(Map<String, dynamic> row, String mode, String note) async {
    await requireOwner(row);
    if (journal.queue.records[row['event_id']]?['financial_operation'] != null) {
      throw StateError('Εκκρεμεί έλεγχος του προηγούμενου αιτήματος.');
    }
    final context = await work(row);
    final sessions = (context['activities']?['sessions'] as List? ?? []).whereType<Map>();
    final matches = sessions.where((s) => s['id'] == row['remote_session_id']).toList();
    if (matches.length != 1 || sessions.any((s) => !androidSessionVerified(Map<String, dynamic>.from(s)))) {
      throw StateError('Αναμένεται επιβεβαιωμένη λήξη και διάρκεια από τον πάροχο.');
    }
    if (context['permissions']?['can_finalize'] != true) throw StateError('Δεν επιτρέπεται ολοκλήρωση εργασίας.');
    if (!['automatic', 'free', 'ignore'].contains(mode)) throw ArgumentError('Invalid decision');
    final intent = <String, dynamic>{'text': note, 'billing_mode': mode, 'send_email': false, 'interpret_imported_command': true};
    final response = await post('/support-workflow/items/${row['work_item_id']}/preview', intent, scope: row);
    final preview = response['preview'];
    if (preview is! Map || preview['billing_mode'] != mode || preview['preview_hash'] is! String ||
        preview['revision'] == null) throw StateError('Μη έγκυρη προεπισκόπηση Office.');
    return {'preview': Map<String, dynamic>.from(preview), 'intent': intent};
  }

  Future<void> finalize(Map<String, dynamic> row, Map<String, dynamic> reviewed) async {
    await requireOwner(row);
    final current = journal.queue.records[row['event_id']]!;
    if (current['financial_operation'] != null) throw StateError('Ελέγξτε το προηγούμενο αίτημα.');
    final preview = reviewed['preview'] as Map;
    if (preview['can_finalize'] != true) throw StateError('Απαιτείται έλεγχος στο Office.');
    final operation = {'key': 'android_${Uuid().v4()}', 'work_item_id': row['work_item_id'],
      'body': {...Map<String, dynamic>.from(reviewed['intent'] as Map),
        'expected_revision': preview['revision'], 'preview_hash': preview['preview_hash']}};
    // Durable intent before sending. A timeout remains unresolved; only GET
    // recovery is automatic, never a second financial POST.
    await save(row, {'financial_operation': operation});
    final result = await post('/support-workflow/items/${operation['work_item_id']}/finalize',
      {...Map<String, dynamic>.from(operation['body'] as Map), 'idempotency_key': operation['key']}, scope: row);
    await accept(row, result);
  }

  Future<void> excludeUnassigned(Map<String, dynamic> row, String reason) async {
    await requireOwner(row);
    if ((await service.loadStatus()).supportRole != 'admin') throw StateError('Η εξαίρεση πηγής απαιτεί διαχειριστή Office.');
    if (row['work_item_id'] != null || reason.trim().isEmpty) throw StateError('Απαιτείται αιτιολογία εξαίρεσης πηγής.');
    if (journal.queue.records[row['event_id']]?['financial_operation'] != null) throw StateError('Ελέγξτε το προηγούμενο αίτημα.');
    final operation = {'key': 'android_exclude_${Uuid().v4()}', 'kind': 'source_exclusion'};
    await save(row, {'financial_operation': operation});
    final result = await post('/support-workflow/exclusions', {'peer_id': row['peer_id'], 'from_peer': row['from_peer'],
      'reason': reason.trim(), 'idempotency_key': operation['key']}, scope: row);
    await accept(row, result);
  }

  Future<void> accept(Map<String, dynamic> row, Map<String, dynamic> result) async {
    final operation = journal.queue.records[row['event_id']]?['financial_operation'];
    if (operation is Map && operation['kind'] == 'source_exclusion') {
      if (result['status'] != 'ok' || result['exclusion']?['peer_id'] != row['peer_id'] ||
          result['exclusion']?['from_peer'] != row['from_peer']) throw StateError('Δεν επιβεβαιώθηκε η εξαίρεση πηγής.');
      await save(row, {'decision': 'excluded', 'financial_operation': null}); return;
    }

    if (result['status'] != 'ok' || result['item']?['id'] != row['work_item_id'] ||
        !['finalized', 'ignored'].contains(result['item']?['support_state'])) {
      throw StateError('Το Office δεν επιβεβαίωσε ολοκλήρωση.');
    }
    await save(row, {'decision': result['item']['support_state'] == 'ignored' ? 'excluded' : 'completed',
      'financial_operation': null});
  }

  Future<bool> recover(Map<String, dynamic> row) async {
    await requireOwner(row);
    final operation = journal.queue.records[row['event_id']]?['financial_operation'];
    if (operation is! Map) return true;
    final response = await get('/support-workflow/requests/${operation['key']}', scope: row);
    if (response['request']?['state'] == 'applied') {
      await accept(row, Map<String, dynamic>.from(response['request']['result'] as Map)); return true;
    }
    // not_found can race an in-flight request: keep the original operation.
    return false;
  }
}
