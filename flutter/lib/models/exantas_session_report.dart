enum ExantasSessionOutcome {
  completed,
  followUp,
  noRecord,
}

class ExantasWorkflowCapabilities {
  const ExantasWorkflowCapabilities({
    required this.enabled,
    required this.contractVersions,
  });

  final bool enabled;
  final Set<int> contractVersions;

  bool get supportsV2 => enabled && contractVersions.contains(2);
}

enum ExantasWorkContextClassification {
  excluded,
  unassigned,
  bound,
  pendingIdentity,
}

class ExantasWorkContext {
  const ExantasWorkContext({
    required this.classification,
    required this.workItemId,
    required this.workRevision,
    required this.remoteSessionId,
    required this.suppressLegacy,
  });

  final ExantasWorkContextClassification classification;
  final String? workItemId;
  final String? workRevision;
  final String? remoteSessionId;
  final bool suppressLegacy;

  bool get isV2Bound =>
      classification == ExantasWorkContextClassification.bound &&
      workItemId != null &&
      remoteSessionId != null &&
      suppressLegacy;
}

ExantasWorkContext parseExantasWorkContext(Map<String, dynamic> response) {
  final classification = switch (response['classification']) {
    'excluded' => ExantasWorkContextClassification.excluded,
    'unassigned' => ExantasWorkContextClassification.unassigned,
    'bound' => ExantasWorkContextClassification.bound,
    'pending_identity' => ExantasWorkContextClassification.pendingIdentity,
    _ => null,
  };
  if (response['status'] != 'ok' ||
      response['contract_version'] != 2 ||
      classification == null ||
      response['suppress_legacy'] != true) {
    throw const FormatException('Invalid Office work context response.');
  }
  String? optionalId(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  final workItemId = optionalId(response['work_item_id']);
  final remoteSessionId = optionalId(response['remote_session_id']);
  final workRevision = optionalId(response['work_revision']);
  if (classification == ExantasWorkContextClassification.bound &&
      (workItemId == null || remoteSessionId == null || workRevision == null)) {
    throw const FormatException('Bound Office work context is incomplete.');
  }
  return ExantasWorkContext(
    classification: classification,
    workItemId: workItemId,
    workRevision: workRevision,
    remoteSessionId: remoteSessionId,
    suppressLegacy: true,
  );
}

bool canPromptExantasReport(dynamic state) =>
    state == 'active' || state == 'draft';

/// A null context is returned only by the explicit disabled/404 compatibility
/// path. Any v2 classification, including an unassigned/pending identity, must
/// avoid creating a new v1 capture.
bool shouldCaptureLegacyExantasSession(ExantasWorkContext? context) =>
    context == null;

/// The explicit disabled/404 compatibility path is represented by null. Once
/// the authenticated API returns any v2 classification, old queued reports
/// are held for Office review rather than resubmitted through the legacy API.
bool maySubmitLegacyExantasReport(ExantasWorkContext? context) =>
    context == null;

bool belongsToExantasOfficeScope(
  Map<String, dynamic> row, {
  required bool loggedIn,
  required String officeUserId,
  required String apiBase,
}) =>
    loggedIn &&
    officeUserId.isNotEmpty &&
    row['owner'] == officeUserId &&
    row['api'] == apiBase;

/// Marks an old queued entry for review without changing its original payload.
/// All authenticated v2 contexts suppress legacy submission, including sources
/// that are still unassigned or pending identity.
Map<String, dynamic>? quarantineLegacyExantasReport(
  Map<String, dynamic> row,
  ExantasWorkContext context,
) {
  if (!context.suppressLegacy) return null;
  return {
    ...row,
    'workflow_review': context.classification.name,
    'state': 'review',
    'error': 'This report is held for Office review.',
  };
}

bool matchesExantasV2SuppressionMarker(
  Map<String, dynamic> legacyRow,
  Map<String, dynamic> marker,
) {
  final classification = marker['workflow_classification'];
  if (marker['workflow_contract_version'] != 2 ||
      !ExantasWorkContextClassification.values
          .any((value) => value.name == classification) ||
      legacyRow['owner'] != marker['owner'] ||
      legacyRow['api'] != marker['api']) {
    return false;
  }
  final legacySession = legacyRow['local_session']?.toString() ?? '';
  final markerSession = marker['local_session']?.toString() ?? '';
  if (legacySession.isNotEmpty && legacySession == markerSession) return true;
  final sessionId = legacyRow['rustdesk_session_id']?.toString() ?? '';
  final markerSessionId = marker['rustdesk_session_id']?.toString() ?? '';
  return sessionId.isNotEmpty &&
      sessionId != '0' &&
      sessionId == markerSessionId &&
      legacyRow['peer_id'] == marker['peer_id'] &&
      legacyRow['from_peer'] == marker['from_peer'];
}

Map<String, dynamic>? quarantineLegacyExantasReportFromMarker(
  Map<String, dynamic> row,
  Map<String, dynamic> marker,
) {
  if (!matchesExantasV2SuppressionMarker(row, marker)) return null;
  return {
    ...row,
    'workflow_review': marker['workflow_classification'],
    'state': 'review',
    'error': 'This report is held for Office review.',
  };
}

Map<String, dynamic> retainExantasV2SuppressionAfterLookupFailure(
  Map<String, dynamic> marker,
  DateTime checkedAt,
) =>
    {
      ...marker,
      'last_context_checked_at': checkedAt.toUtc().toIso8601String(),
    };

String buildExantasLocalSessionKey(String peerId, Object flutterSessionId) {
  final peer = peerId.trim();
  final session = flutterSessionId.toString().trim();
  if (peer.isEmpty || session.isEmpty) {
    throw ArgumentError('Peer and Flutter session identifiers are required.');
  }
  return '$peer:$session';
}

String resolveExantasRustDeskSessionId(dynamic started, dynamic ended) {
  final finalId = ended?.toString().trim() ?? '';
  return finalId.isNotEmpty && finalId != '0'
      ? finalId
      : started?.toString().trim() ?? '';
}

bool matchesExantasSession(
    Map<String, dynamic> local, Map<String, dynamic> remote) {
  final id = local['rustdesk_session_id']?.toString() ?? '';
  return id.isNotEmpty &&
      id != '0' &&
      id == remote['rustdesk_session_id']?.toString() &&
      local['peer_id'] == remote['peer_id'] &&
      local['from_peer'] != null &&
      local['from_peer'] != '' &&
      local['from_peer'] == remote['from_peer'] &&
      local['owner'] == remote['technician_admin_id'];
}

bool confirmsExantasReport(ExantasSessionOutcome outcome, dynamic action) {
  switch (outcome) {
    case ExantasSessionOutcome.completed:
      return action == 'final';
    case ExantasSessionOutcome.followUp:
      return action == 'pending';
    case ExantasSessionOutcome.noRecord:
      return action == 'noop';
  }
}

// A network refresh must never overwrite a report saved while it was in flight.
Map<String, dynamic> mergeExantasReportUpdate(
    Map<String, dynamic>? current, Map<String, dynamic> incoming) {
  if (incoming['workflow_contract_version'] == 2) {
    // V2 source markers deliberately replace an unsent v1 capture with the
    // minimum identity needed for exclusion/requery; no report text or timing
    // survives the transition into the v2-owned workflow.
    return Map<String, dynamic>.from(incoming);
  }
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
