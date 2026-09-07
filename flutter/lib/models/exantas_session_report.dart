enum ExantasSessionOutcome {
  completed,
  followUp,
  noRecord,
}

bool matchesExantasSession(Map<String, dynamic> local, Map<String, dynamic> remote) {
  final id = local['rustdesk_session_id']?.toString() ?? '';
  return id.isNotEmpty && id != '0' &&
      id == remote['rustdesk_session_id']?.toString() &&
      local['peer_id'] == remote['peer_id'] &&
      local['from_peer'] != null && local['from_peer'] != '' &&
      local['from_peer'] == remote['from_peer'] &&
      local['owner'] == remote['technician_admin_id'];
}

bool confirmsExantasReport(ExantasSessionOutcome outcome, dynamic action) {
  switch (outcome) {
    case ExantasSessionOutcome.completed: return action == 'final';
    case ExantasSessionOutcome.followUp: return action == 'pending';
    case ExantasSessionOutcome.noRecord: return action == 'noop';
  }
}

// A network refresh must never overwrite a report saved while it was in flight.
Map<String, dynamic> mergeExantasReportUpdate(
    Map<String, dynamic>? current, Map<String, dynamic> incoming) {
  const rank = {'active': 0, 'draft': 1, 'queued': 2, 'review': 3, 'synced': 4};
  final result = <String, dynamic>{...?current, ...incoming};
  if (current != null &&
      (rank[current['state']] ?? 0) > (rank[incoming['state']] ?? 0)) {
    for (final key in ['state', 'outcome', 'note']) {
      if (current.containsKey(key)) result[key] = current[key];
    }
  }
  if (result['state'] == 'synced') result.remove('error');
  return result;
}

String buildExantasSessionReportCommand(
  ExantasSessionOutcome outcome,
  String note,
) {
  final trimmedNote = note.trim();
  switch (outcome) {
    case ExantasSessionOutcome.completed:
      if (trimmedNote.isEmpty) {
        throw ArgumentError('A final support note is required.');
      }
      return '~ $trimmedNote';
    case ExantasSessionOutcome.followUp:
      if (trimmedNote.isEmpty) {
        throw ArgumentError('A follow-up support note is required.');
      }
      return '# $trimmedNote';
    case ExantasSessionOutcome.noRecord:
      return '-';
  }
}
