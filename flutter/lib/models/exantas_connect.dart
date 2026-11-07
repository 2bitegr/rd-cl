/// Pure connection-with-work rules. Office decides; the phone only checks the
/// fresh work context it just loaded before binding the existing mobile
/// selection (`mobile_work`) that the lifecycle outbox copies into the journal.

class ConnectCheck {
  const ConnectCheck.ok(this.selection) : reason = null;
  const ConnectCheck.fail(this.reason) : selection = null;
  final Map<String, dynamic>? selection;
  final String? reason;
  bool get ok => selection != null;
}

/// [context] is a fresh GET /support-workflow/items/{id}. Requires can_edit, an
/// open work, a device of THIS work's customer (Office lists only those) that
/// can_connect, and, when given, the customer the user picked.
ConnectCheck evaluateWorkConnect(Map<String, dynamic> context,
    {required String peer,
    required String owner,
    required String api,
    String? expectedWorkId,
    String? expectedCustomerId}) {
  final item = context['item'];
  if (item is! Map || item['id'] == null || item['revision'] == null) {
    return const ConnectCheck.fail('Δεν φορτώθηκε η εργασία από το Office.');
  }
  if (expectedWorkId != null && item['id'] != expectedWorkId) {
    return const ConnectCheck.fail('Η εργασία άλλαξε. Επιλέξτε ξανά.');
  }
  if (context['permissions']?['can_edit'] != true) {
    return const ConnectCheck.fail('Δεν επιτρέπεται αλλαγή αυτής της εργασίας.');
  }
  if (!['draft', 'review'].contains(item['support_state'])) {
    return const ConnectCheck.fail('Η εργασία δεν είναι ανοιχτή.');
  }
  if (expectedCustomerId != null && item['customer_id'] != expectedCustomerId) {
    return const ConnectCheck.fail('Ο πελάτης της εργασίας άλλαξε.');
  }
  final devices = (context['devices'] as List? ?? []).whereType<Map>().where((d) => d['peer_id'] == peer).toList();
  if (devices.isEmpty) {
    return const ConnectCheck.fail('Ο υπολογιστής δεν ανήκει στον πελάτη αυτής της εργασίας.');
  }
  if (!devices.any((d) => d['can_connect'] == true)) {
    return const ConnectCheck.fail('Ο υπολογιστής δεν επιτρέπεται για σύνδεση.');
  }
  return ConnectCheck.ok({
    'peer_id': peer,
    'work_item_id': item['id'],
    'revision': item['revision'],
    'owner': owner,
    'api': api,
  });
}

/// Suggestion = an open own work whose customer lists [peer] as a connectable
/// device. Returns work ids only; the user must tap one.
List<String> suggestWorkIds(String peer, Iterable<Map<String, dynamic>> contexts) => [
      for (final c in contexts)
        if (c['permissions']?['can_edit'] == true &&
            ['draft', 'review'].contains(c['item']?['support_state']) &&
            (c['devices'] as List? ?? []).whereType<Map>().any((d) => d['peer_id'] == peer && d['can_connect'] == true))
          '${c['item']['id']}'
    ];

/// Runs one action at a time; a second call while busy is ignored (null).
class ExantasSingleFlight {
  bool _busy = false;
  bool get busy => _busy;
  Future<T?> run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}
