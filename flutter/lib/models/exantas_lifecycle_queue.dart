// Dependency-free queue core. Persist before ACK; retry the exact close payload.
class ExantasLifecycleQueue {
  ExantasLifecycleQueue({required this.save, required this.send, this.bindLaunch});
  final Future<void> Function(Map<String, dynamic>) save;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) send;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? bindLaunch;
  final Map<String, Map<String, dynamic>> records = {};
  Future<void> _writes = Future.value();
  bool _syncing = false;
  int _offset = 0;
  int _launchOffset = 0;
  String? error;

  Future<void> capture(Map<String, dynamic> incoming) {
    final next = _writes.then((_) async {
      final key = incoming['event_id'] as String;
      final previous = records[key];
      if (previous != null && ['owner', 'api', 'from_peer', 'peer_id', 'local_session'].any((key) => previous[key] != incoming[key])) {
        throw StateError('Lifecycle owner changed.');
      }
      final oldId = previous?['rustdesk_session_id']?.toString() ?? '';
      if (oldId.isNotEmpty && oldId != '0' && incoming['rustdesk_session_id']?.toString() != oldId) {
        throw StateError('Native connection identity changed.');
      }
      final row = <String, dynamic>{...?previous, ...incoming};
      // Preserve the first close and acknowledgement under duplicate callbacks.
      if (previous != null && previous['ended_at'] != null) {
        row['ended_at'] = previous['ended_at'];
        row['event_id'] = previous['event_id'];
        row['acknowledged'] = previous['acknowledged'];
      }
      if (previous?['launch_linked'] == true) row['launch_linked'] = true;
      if (previous?['launch_closed'] == true) row['launch_closed'] = true;
      await save(row);
      records[key] = row;
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> sync(String owner, String api, String fromPeer) async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _writes;
      error = null;
      if (bindLaunch != null) {
        final launching = records.values.where((r) => r['owner'] == owner && r['api'] == api && r['from_peer'] == fromPeer
          && r['launch'] != null && (r['launch_linked'] != true || (r['ended_at'] != null && r['acknowledged'] == true && r['launch_closed'] != true))
          && r['rustdesk_session_id'] != null && r['rustdesk_session_id'] != '' && r['rustdesk_session_id'] != '0').toList();
        final size = launching.length < 20 ? launching.length : 20;
        final batch = List.generate(size, (i) => launching[(_launchOffset+i)%launching.length]);
        if (launching.isNotEmpty) _launchOffset = (_launchOffset+size)%launching.length;
        for (final snapshot in batch) {
          try {
            final receipt = await bindLaunch!(Map<String,dynamic>.from(snapshot));
            if (receipt['status'] != 'ok' || receipt['launch_request_id'] != snapshot['launch']['launch_request_id']
              || receipt['rustdesk_session_id'] != snapshot['rustdesk_session_id']) throw StateError('Native binding receipt mismatch.');
            if (receipt['linked'] != true) error = 'Αναμένεται η ακριβής εγγραφή audit για σύνδεση με την εργασία.';
            if (receipt['linked'] == true) {
              if (receipt['remote_session_id'] is! String || (receipt['remote_session_id'] as String).isEmpty) throw StateError('Missing exact source.');
              await capture({...records[snapshot['event_id']]!, 'launch_linked': true, 'launch_closed': receipt['ended_at'] != null});
            }
          } catch (_) { error = 'Η σύνδεση συνεδρίας με την εργασία εκκρεμεί. Θα επαναληφθεί με την ίδια ταυτότητα.'; }
        }
      }
      final pending = records.values.where((r) => r['owner'] == owner && r['api'] == api && r['from_peer'] == fromPeer
          && r['ended_at'] != null && r['acknowledged'] != true).toList();
      final count = pending.length < 20 ? pending.length : 20;
      final batch = List.generate(count, (i) => pending[(_offset + i) % pending.length]);
      if (pending.isNotEmpty) _offset = (_offset + count) % pending.length;
      for (final snapshot in batch) {
        final id = snapshot['rustdesk_session_id']?.toString() ?? '';
        if (id.isEmpty || id == '0') { error = 'Η λήξη διατηρείται τοπικά: λείπει επιβεβαιωμένο ID συνεδρίας.'; continue; }
        try {
          final receipt = await send(Map<String, dynamic>.from(snapshot));
          if (receipt['status'] != 'ok' || receipt['recorded'] != true || receipt['event_id'] != snapshot['event_id']
              || receipt['remote_session_id'] is! String || (receipt['remote_session_id'] as String).isEmpty) {
            throw StateError('Closure receipt did not match.');
          }
          final key = snapshot['event_id'] as String;
          // ACK persistence is serialized with duplicate close callbacks.
          final next = _writes.then((_) async {
            final row = <String, dynamic>{...records[key]!, 'acknowledged': true,
              'remote_session_id': receipt['remote_session_id']};
            await save(row); records[key] = row;
          });
          _writes = next.catchError((Object _) {});
          await next;
        } catch (_) {
          error = 'Η λήξη αποθηκεύτηκε τοπικά αλλά δεν επιβεβαιώθηκε από το Office. Θα επαναληφθεί η αποστολή.';
        }
      }
    } finally { _syncing = false; }
  }
}
