import 'package:uuid/uuid.dart';
import 'exantas_session_timing.dart';
import 'exantas_companion_model.dart';
import 'exantas_lifecycle_outbox.dart';
import 'exantas_session_report.dart';
import 'exantas_office_response.dart';
import 'exantas_financial_ledger.dart';
import 'platform_model.dart';
export 'exantas_native_auth.dart' show normalizeAndroidPeerId;
export 'exantas_session_timing.dart' show androidSessionVerified;

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
  late final ExantasFinancialLedger ledger = ExantasFinancialLedger(
      record: (id) => journal.queue.records[id], save: save,
      get: (path, row) => get(path, scope: row), post: (path, body, row) => post(path, body, scope: row),
      requireOwner: requireOwner);
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
            await save(row, {'office_review': 'conflict'});
            throw StateError('Η συνεδρία ανήκει σε άλλη εργασία. Απαιτείται έλεγχος Office.');
          }
          await save(row, {'remote_session_id': context.remoteSessionId, 'work_item_id': context.workItemId});
          final authoritative = await get('/support-workflow/items/${context.workItemId}', scope: row);
          await _remember(row, authoritative);
          if (authoritative['item']?['support_state'] == 'finalized' && authoritative['current_report']?['id'] != null &&
              (authoritative['activities']?['sessions'] as List? ?? []).whereType<Map>().any((s) => s['id'] == context!.remoteSessionId)) {
            await save(row, {'decision': 'completed', 'resolved_in_office_report': authoritative['current_report']['id'],
              'resolved_operation': journal.queue.records[row['event_id']]?['financial_operation'], 'financial_operation': null});
          }

        }
      }
    } finally { _refreshing = false; }
  }

  /// Display/classification facts taken from Office only; written when changed.
  Future<void> _remember(Map<String, dynamic> row, Map<String, dynamic> authoritative) async {
    final stored = journal.queue.records[row['event_id']] ?? {};
    final sessions = (authoritative['activities']?['sessions'] as List? ?? []).whereType<Map>().toList();
    final mine = sessions.where((s) => s['id'] == stored['remote_session_id']).toList();
    final verified = mine.length == 1 && sessions.every((s) => androidSessionVerified(Map<String, dynamic>.from(s)));
    final item = authoritative['item'];
    final values = <String, dynamic>{
      'customer_name': item is Map ? (item['customer_name'] ?? (authoritative['customer'] as Map?)?['company_name']) : null,
      'work_title': item is Map ? item['title'] : null,
      'timing_verified': verified,
      'provider_ended_at': mine.length == 1 ? mine.single['ended_at'] : null,
      'provider_duration_seconds': mine.length == 1 && verified ? mine.single['duration_seconds'] : null,
      'office_review': item is Map && item['support_state'] == 'finalized' ? 'finalized' : stored['office_review'],
    };
    if (values.entries.any((e) => stored[e.key] != e.value)) await save(row, values);
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

  /// Unresolved work-creation requests of this account (not session rows).
  Future<List<Map<String, dynamic>>> creations() async {
    await journal.load();
    final status = await service.loadStatus();
    return journal.queue.records.values.where((r) => r['kind'] == 'work_creation' &&
      r['owner'] == status.officeUserId && r['api'] == status.apiBase && r['creation_pending'] == true)
        .map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// User-initiated, same rule as financial operations: a fresh receipt GET must
  /// say not_found and the reservation must be older than 2 minutes.
  Future<bool> abandonCreation(Map<String, dynamic> row) async {
    await requireOwner(row);
    final current = journal.queue.records[row['event_id']];
    if (current == null || current['creation_pending'] != true) return false;
    final receipt = await get('/support-workflow/requests/${current['request_key']}', scope: current);
    final state = receipt['request']?['state'];
    if (state == 'applied') return false;
    if (state != 'not_found') throw StateError('Δεν επιβεβαιώθηκε η απουσία του αιτήματος.');
    final marks = {...current, 'not_found_at': current['not_found_at'] ?? DateTime.now().toUtc().toIso8601String()};
    if (!exantasAbandonEligible(marks, DateTime.now())) {
      await save(current, {'not_found_at': marks['not_found_at']});
      throw StateError('Η ακύρωση επιτρέπεται μετά από 2 λεπτά.');
    }
    await save(current, {'creation_pending': false, 'creation_abandoned_at': DateTime.now().toUtc().toIso8601String()});
    return true;
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
        if (receipt['request']?['state'] == 'not_found' && original['not_found_at'] == null) {
          await save(original, {'not_found_at': DateTime.now().toUtc().toIso8601String()});
        }
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
      'customer_id': customerId, 'creation_pending': true, 'request_key': 'android_create_$id',
      'reserved_at': DateTime.now().toUtc().toIso8601String()};
    await journal.queue.capture(record);
    final Map<String, dynamic> result;
    try {
      result = await post('/support-workflow/items', {'customer_id': customerId, 'title': title,
        'support_kind': 'remote_support', 'idempotency_key': record['request_key']}, scope: record);
    } on ExantasOfficeRejection catch (e) {
      if (e.definitive) {
        // Server rolled back (definitive 4xx): free the reservation now so a
        // retry uses a NEW key. Uncertain failures keep it pending (2-min rule).
        await save(record, {'rejected': {'status': e.statusCode, 'code': e.code}, 'creation_pending': false});
      }
      rethrow;
    }
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
    return {'preview': Map<String, dynamic>.from(preview), 'intent': intent,
      'previewed_at': DateTime.now().toUtc().toIso8601String(),
      // Office work context, shown beside the preview; never used for amounts.
      'context': {'customer_name': context['item']?['customer_name'] ?? context['customer']?['company_name'],
        'title': context['item']?['title'], 'sessions': sessions.map((e) => Map<String, dynamic>.from(e)).toList()}};
  }

  Future<void> finalize(Map<String, dynamic> row, Map<String, dynamic> reviewed) async {
    final preview = reviewed['preview'] as Map;
    if (preview['can_finalize'] != true) throw StateError('Απαιτείται έλεγχος στο Office.');
    final operation = {'key': 'android_${Uuid().v4()}', 'work_item_id': row['work_item_id'],
      'body': {...Map<String, dynamic>.from(reviewed['intent'] as Map),
        'expected_revision': preview['revision'], 'preview_hash': preview['preview_hash']}};
    // Durable intent before sending. A timeout remains unresolved; only GET
    // recovery is automatic, never a second financial POST.
    await ledger.submit(row, operation, '/support-workflow/items/${operation['work_item_id']}/finalize',
      {...Map<String, dynamic>.from(operation['body'] as Map), 'previewed_at': reviewed['previewed_at']},
      spendToken: '${row['event_id']}:${preview['preview_hash']}:${preview['revision']}:${reviewed['previewed_at']}');
  }

  Future<void> excludeUnassigned(Map<String, dynamic> row, String reason) async {
    await requireOwner(row);
    if ((await service.loadStatus()).supportRole != 'admin') throw StateError('Η εξαίρεση πηγής απαιτεί διαχειριστή Office.');
    if (row['work_item_id'] != null || reason.trim().isEmpty) throw StateError('Απαιτείται αιτιολογία εξαίρεσης πηγής.');
    if (journal.queue.records[row['event_id']]?['financial_operation'] != null) throw StateError('Ελέγξτε το προηγούμενο αίτημα.');
    await ledger.submit(row, {'key': 'android_exclude_${Uuid().v4()}', 'kind': 'source_exclusion'},
      '/support-workflow/exclusions', {'peer_id': row['peer_id'], 'from_peer': row['from_peer'], 'reason': reason.trim()});
  }

  Future<void> accept(Map<String, dynamic> row, Map<String, dynamic> result) => ledger.accept(row, result);

  Future<bool> recover(Map<String, dynamic> row) => ledger.recover(row);

  bool canAbandon(Map<String, dynamic> row) => ledger.canAbandon(row);

  Future<bool> abandon(Map<String, dynamic> row) => ledger.abandon(row);
}
