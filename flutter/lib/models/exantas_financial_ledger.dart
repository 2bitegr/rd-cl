import 'exantas_office_response.dart';

/// Minimum age of a financial reservation before the technician may abandon it.
const exantasAbandonAfter = Duration(minutes: 2);

/// Pure rule shared by financial operations and work creation.
/// [marks] holds `reserved_at`, `not_found_at` (a recovery GET answered
/// not_found) and `rejected` (definitive 4xx from the original POST). Abandoning
/// is allowed only with proof the key was never applied AND a reservation older
/// than [exantasAbandonAfter]. Legacy marks without `reserved_at` age from the
/// first observed not_found.
bool exantasAbandonEligible(Map marks, DateTime now) {
  final proven = marks['not_found_at'] != null || marks['rejected'] is Map;
  final since = DateTime.tryParse(
      '${marks['reserved_at'] ?? marks['not_found_at'] ?? ''}');
  return proven && since != null && now.difference(since) >= exantasAbandonAfter;
}

/// Owns the durable intent -> single POST -> GET-only recovery protocol for
/// finalize / source-exclusion. Dependency-free so it is unit-testable.
///
/// Invariants:
///  * the operation (with its key) is persisted before the POST;
///  * a row with a financial_operation can never start another one;
///  * the only automatic follow-up is a GET; the POST is never retried;
///  * abandoning is user initiated, needs a fresh GET not_found, and clears the
///    operation so the next finalize needs a NEW preview and a NEW key.
class ExantasFinancialLedger {
  ExantasFinancialLedger(
      {required this.record,
      required this.save,
      required this.get,
      required this.post,
      required this.requireOwner,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  final Map<String, dynamic>? Function(String eventId) record;
  final Future<void> Function(Map<String, dynamic> row, Map<String, dynamic> values) save;
  final Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> row) get;
  final Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body, Map<String, dynamic> row) post;
  final Future<void> Function(Map<String, dynamic> row) requireOwner;
  final DateTime Function() now;
  final Set<String> _inflight = {}, _spent = {};

  String _stamp() => now().toUtc().toIso8601String();

  /// Single entry point for a financial POST. [spendToken] identifies the
  /// reviewed preview; it can reserve only one operation.
  Future<void> submit(Map<String, dynamic> row, Map<String, dynamic> operation,
      String path, Map<String, dynamic> body, {String? spendToken}) async {
    final id = row['event_id'] as String;
    // Synchronous guard: a double tap never reaches a second reservation.
    if (!_inflight.add(id)) throw StateError('Υπάρχει ήδη αίτημα σε εξέλιξη.');
    try {
      await requireOwner(row);
      final current = record(id);
      if (current == null || current['financial_operation'] != null) {
        throw StateError('Ελέγξτε το προηγούμενο αίτημα.');
      }
      if (spendToken != null && _spent.contains(spendToken)) {
        throw StateError('Απαιτείται νέα προεπισκόπηση Office.');
      }
      final abandonedAt = DateTime.tryParse('${current['last_abandoned_at'] ?? ''}');
      final previewedAt = DateTime.tryParse('${body['previewed_at'] ?? ''}');
      if (abandonedAt != null && (previewedAt == null || !previewedAt.isAfter(abandonedAt))) {
        throw StateError('Απαιτείται νέα προεπισκόπηση Office.');
      }
      final reserved = {...operation, 'reserved_at': _stamp()};
      await save(row, {'financial_operation': reserved});
      if (spendToken != null) _spent.add(spendToken);
      final sent = {...body}..remove('previewed_at');
      Map<String, dynamic> result;
      try {
        result = await post(path, {...sent, 'idempotency_key': reserved['key']}, row);
      } on ExantasOfficeRejection catch (e) {
        if (e.definitive) {
          await save(row, {'financial_operation': {...reserved, 'rejected': {'status': e.statusCode, 'code': e.code}}});
        }
        rethrow;
      }
      await accept(row, result);
    } finally {
      _inflight.remove(id);
    }
  }

  Future<void> accept(Map<String, dynamic> row, Map<String, dynamic> result) async {
    final operation = record(row['event_id'] as String)?['financial_operation'];
    if (operation is Map && operation['kind'] == 'source_exclusion') {
      if (result['status'] != 'ok' || result['exclusion']?['peer_id'] != row['peer_id'] ||
          result['exclusion']?['from_peer'] != row['from_peer']) {
        throw StateError('Δεν επιβεβαιώθηκε η εξαίρεση πηγής.');
      }
      await save(row, {'decision': 'excluded', 'financial_operation': null});
      return;
    }
    if (result['status'] != 'ok' || result['item']?['id'] != row['work_item_id'] ||
        !['finalized', 'ignored'].contains(result['item']?['support_state'])) {
      throw StateError('Το Office δεν επιβεβαίωσε ολοκλήρωση.');
    }
    await save(row, {
      'decision': result['item']['support_state'] == 'ignored' ? 'excluded' : 'completed',
      'financial_operation': null
    });
  }

  /// GET only. Applied -> stored result accepted, no second POST. not_found is
  /// remembered (first observation) but never clears the operation.
  Future<bool> recover(Map<String, dynamic> row) async {
    await requireOwner(row);
    final id = row['event_id'] as String;
    final operation = record(id)?['financial_operation'];
    if (operation is! Map) return true;
    final response = await get('/support-workflow/requests/${operation['key']}', row);
    final state = response['request']?['state'];
    if (state == 'applied') {
      await accept(row, Map<String, dynamic>.from(response['request']['result'] as Map));
      return true;
    }
    if (state == 'not_found' && operation['not_found_at'] == null) {
      await save(row, {'financial_operation': {...operation, 'not_found_at': _stamp()}});
    }
    return false;
  }

  bool canAbandon(Map<String, dynamic> row) {
    final operation = record(row['event_id'] as String)?['financial_operation'] ?? row['financial_operation'];
    return operation is Map && exantasAbandonEligible(operation, now());
  }

  /// User-initiated. Returns true when the operation was cleared. Re-checks the
  /// server first: an applied result is accepted instead (never abandoned).
  Future<bool> abandon(Map<String, dynamic> row) async {
    await requireOwner(row);
    final id = row['event_id'] as String;
    final operation = record(id)?['financial_operation'];
    if (operation is! Map) return false;
    if (!exantasAbandonEligible(operation, now())) {
      throw StateError('Η ακύρωση επιτρέπεται μόνο όταν το Office δεν έχει το αίτημα και έχουν περάσει 2 λεπτά.');
    }
    final response = await get('/support-workflow/requests/${operation['key']}', row);
    final state = response['request']?['state'];
    if (state == 'applied') {
      await accept(row, Map<String, dynamic>.from(response['request']['result'] as Map));
      return false;
    }
    if (state != 'not_found') throw StateError('Δεν επιβεβαιώθηκε η απουσία του αιτήματος.');
    final history = [...?(record(id)?['abandoned_operations'] as List?), {'key': operation['key'], 'at': _stamp()}];
    await save(row, {'financial_operation': null, 'last_abandoned_at': _stamp(), 'abandoned_operations': history});
    return true;
  }
}
