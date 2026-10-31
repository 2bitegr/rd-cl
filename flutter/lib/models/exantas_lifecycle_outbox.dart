import 'exantas_launch_ticket.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'exantas_companion_model.dart';
import 'exantas_lifecycle_queue.dart';
import 'exantas_secure_store.dart';
import 'exantas_session_report.dart';
import 'platform_model.dart';

// Main-window owned, separate from report text and v1/v2 suppression markers.
class ExantasLifecycleOutbox {
  static final instance = ExantasLifecycleOutbox();
  final _service = ExantasCompanionService();
  static const _store = ExantasSecureStore();
  Directory? _directory;
  Future<void>? _loading;
  final Map<String, Future<void>> _starts = {};
  late final queue = ExantasLifecycleQueue(save: _save, send: _service.submitSessionClose, bindLaunch: _service.bindNativeLaunch);
  String? _captureError;
  // Explicit current mobile selection; copied into the existing encrypted
  // journal only when the native client reports an actual peer_info event.
  Map<String, dynamic>? mobileWork;
  String? get error => _captureError ?? queue.error;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final root = await getApplicationSupportDirectory();
    _directory = await Directory('${root.path}/office-lifecycle').create(recursive: true);
    await for (final entry in _directory!.list()) {
      if (entry is File && entry.path.endsWith('.json')) {
        final row = (jsonDecode(await _store.unprotectAsync(await entry.readAsString())) as Map).cast<String, dynamic>();
        queue.records[row['event_id'] as String] = row;
      }
    }
  }
  Future<void> _save(Map<String, dynamic> row) async {
    final id = row['event_id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) throw StateError('Invalid lifecycle identifier.');
    final target = File('${_directory!.path}/$id.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(await _store.protectAsync(jsonEncode(row)), flush: true);
    await temporary.rename(target.path);
  }
  Future<void> started(Map<String, dynamic> event) {
    final captured = <String, dynamic>{...event,
      if (Platform.isAndroid && mobileWork != null) 'mobile_work': Map<String, dynamic>.from(mobileWork!)};
    final key = event['local_session'] as String;
    final before = _starts[key] ?? Future<void>.value();
    final operation = before.catchError((Object _) {}).then((_) => _started(captured));
    _starts[key] = operation;
    return operation.then((_) { _captureError = null; }).catchError((Object error) {
      _captureError = 'Δεν αποθηκεύτηκε η έναρξη συνεδρίας Office. Ελέγξτε την τοπική αποθήκευση πριν από δοκιμές.';
      throw error;
    }).whenComplete(() { if (identical(_starts[key], operation)) _starts.remove(key); });
  }
  Future<void> _started(Map<String, dynamic> event) async {
    await load();
    final status = await _service.loadStatus();
    if (!status.technicianLoggedIn || status.officeUserId.isEmpty) return;
    if (queue.records.values.any((row) => row['local_session'] == event['local_session']
        && row['owner'] == status.officeUserId && row['api'] == status.apiBase
        && row['rustdesk_session_id'] == event['rustdesk_session_id'] && row['ended_at'] == null)) return;
    final from = (await bind.mainGetMyId()).trim();
    final current = await _service.loadStatus();
    if (current.officeUserId != status.officeUserId || current.apiBase != status.apiBase
        || current.companionToken != status.companionToken) throw StateError('Lifecycle account changed.');
    final work = event['mobile_work'];
    final actual = Map<String, dynamic>.from(event)..remove('mobile_work');
    await queue.capture({...actual,
      if (Platform.isAndroid && work is Map && work['peer_id'] == event['peer_id'] &&
          work['owner'] == status.officeUserId && work['api'] == status.apiBase) 'mobile_work': work,
      'decision': 'later', 'owner': status.officeUserId, 'api': status.apiBase,
      'from_peer': from, 'event_id': Uuid().v4(), 'acknowledged': false});
  }
  Future<bool> identified(Map<String, dynamic> event) async {
    await _starts[event['local_session']];
    await load();
    final id = event['rustdesk_session_id']?.toString() ?? '';
    if (id.isEmpty || id == '0') return false;
    final rows = queue.records.values.where((row) => row['local_session'] == event['local_session'] && row['ended_at'] == null).toList();
    if (rows.any((row) => row['rustdesk_session_id']?.toString() == id)) return true;
    final pending = rows.where((row) => row['rustdesk_session_id'] == '0' || row['rustdesk_session_id'] == null || row['rustdesk_session_id'] == '').toList();
    if (pending.length != 1) return false;
    await queue.capture({...pending.single, 'rustdesk_session_id': id});
    await sync();
    return true;
  }
  Future<void> ended(Map<String, dynamic> event) async {
    try { await _ended(event); _captureError = null; }
    catch (_) { _captureError = 'Η λήξη δεν αποθηκεύτηκε τοπικά. Χρειάζεται έλεγχος της συγκεκριμένης συνεδρίας.'; rethrow; }
  }
  Future<void> _ended(Map<String, dynamic> event) async {
    await _starts[event['local_session']];
    await load();
    final rows = queue.records.values.where((row) => row['local_session'] == event['local_session']).toList();
    final identity = event['rustdesk_session_id']?.toString() ?? '';
    final exact = identity.isEmpty || identity == '0' ? <Map<String, dynamic>>[]
        : rows.where((row) => row['rustdesk_session_id']?.toString() == identity).toList();
    final candidates = exact.isNotEmpty ? exact
        : identity.isEmpty || identity == '0'
          ? (rows.length == 1 ? rows : rows.where((row) => row['ended_at'] == null).toList())
          : rows.where((row) => row['ended_at'] == null
              && (row['rustdesk_session_id'] == '0' || row['rustdesk_session_id'] == null || row['rustdesk_session_id'] == '')).toList();
    if (candidates.isEmpty && !(await _service.loadStatus()).technicianLoggedIn) return;
    if (candidates.length != 1) throw StateError('Unique session start was not captured; closure cannot be attributed.');
    final row = candidates.single;
    final end = DateTime.tryParse(event['ended_at']?.toString() ?? '');
    final start = DateTime.tryParse(row['started_at']?.toString() ?? '');
    if (end == null || start == null || end.isBefore(start)) throw StateError('Invalid session closure time.');
    await queue.capture({...row, 'ended_at': end.toUtc().toIso8601String(),
      'rustdesk_session_id': resolveExantasRustDeskSessionId(row['rustdesk_session_id'], event['rustdesk_session_id'])});
  }
  Future<void> sync() async {
    try {
      await load();
      final status = await _service.loadStatus();
      if (!status.technicianLoggedIn) return;
      final from = (await bind.mainGetMyId()).trim();
      var ticketError = false;
      final pending = queue.records.values.where((row) => row['owner'] == status.officeUserId
        && row['api'] == status.apiBase && row['from_peer'] == from && row['office_ticket'] != null).toList();
      for (final row in pending) {
        final ticket = row['office_ticket']?.toString() ?? '';
        if (ticket.isEmpty) continue;
        try {
          if (row['launch'] == null) {
            final launch = readExantasLaunchTicket(ticket, status.apiBase, row['peer_id'] as String);
            await queue.capture({...row, 'launch': launch});
          }
          deleteExantasLaunchTicket(ticket);
        } catch (_) { ticketError = true; }
      }
      await queue.sync(status.officeUserId, status.apiBase, from);
      if (ticketError) queue.error = 'Δεν ανακτήθηκε ή καθαρίστηκε το προστατευμένο αίτημα του Popup. Η λήξη διατηρείται ανεξάρτητα.';
    } catch (_) {
      queue.error = 'Δεν διαβάστηκε η τοπική ουρά λήξεων. Διατηρήστε τα τοπικά αρχεία και ελέγξτε τη σύνδεση Office.';
    }
  }
}
