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
        final row = (jsonDecode(_store.unprotect(await file.readAsString())) as Map)
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
    await temporary.writeAsString(_store.protect(jsonEncode(row)), flush: true);
    await temporary.rename(file.path);
    _rows[id] = row;
  }

  Future<List<Map<String, dynamic>>> rows() async {
    await load();
    final status = await _service.loadStatus();
    if (!status.technicianLoggedIn) return [];
    final rows = _rows.values.where((row) =>
        row['owner'] == status.officeUserId && row['api'] == status.apiBase)
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
    if (existing.isNotEmpty) return existing.first;
    final row = <String, dynamic>{
      ...event,
      'id': Uuid().v4(),
      'owner': status.officeUserId,
      'from_peer': (await bind.mainGetMyId()).trim(),
      'api': status.apiBase,
      'technician_name': status.technicianName,
      'state': 'active',
      'local_report': true,
    };
    await _write(row);
    return row;
  }

  Future<Map<String, dynamic>?> ended(Map<String, dynamic> event) async {
    await _starts[event['local_session']];
    await load();
    final matches = _rows.values.where((row) => row['local_session'] == event['local_session']);
    if (matches.length != 1 || !canPromptExantasReport(matches.single['state'])) return null;
    // Office can confirm a disconnect before the user closes its remaining view.
    // That draft still needs the immediate close prompt.
    if (matches.single['state'] == 'draft') {
      return Map<String, dynamic>.from(matches.single);
    }
    final row = Map<String, dynamic>.from(matches.single);
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
    if (row['state'] != 'draft') throw StateError('Η αναφορά έχει ήδη αποθηκευτεί.');
    row.addAll({'outcome': outcome.name, 'note': note, 'state': 'queued'});
    await _write(row);
  }

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final local = await rows();
      if (local.isEmpty) return;
      final pending = await _service.pendingSessions().timeout(const Duration(seconds: 20));
      syncError = null;
      for (final snapshot in local) {
        final row = Map<String, dynamic>.from(_rows[snapshot['id']]!);
        if (row['state'] == 'synced' || row['state'] == 'review') continue;
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
}
