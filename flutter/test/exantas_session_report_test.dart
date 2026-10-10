import 'package:flutter_hbb/models/exantas_session_report.dart';
import 'package:flutter_hbb/models/exantas_workflow_http_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local lifecycle key does not depend on the delayed native session id',
      () {
    const flutterSession = '25ff0f78-6f95-4be5-99fd-7c3a006d05ea';
    expect(buildExantasLocalSessionKey('86355592', flutterSession),
        '86355592:$flutterSession');
    expect(resolveExantasRustDeskSessionId('0', '18446744073709551615'),
        '18446744073709551615');
    expect(resolveExantasRustDeskSessionId('123', '0'), '123');
  });
  test(
      'close prompts an already discovered disconnect but never a saved report',
      () {
    expect(canPromptExantasReport('active'), isTrue);
    expect(canPromptExantasReport('draft'), isTrue);
    expect(canPromptExantasReport('queued'), isFalse);
    expect(canPromptExantasReport('synced'), isFalse);
    expect(canPromptExantasReport('review'), isFalse);
  });
  test('only explicit acknowledgement confirms the submitted report', () {
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, 'final'),
        isTrue);
    expect(confirmsExantasReport(ExantasSessionOutcome.followUp, 'pending'),
        isTrue);
    expect(
        confirmsExantasReport(ExantasSessionOutcome.noRecord, 'noop'), isTrue);
    expect(
        confirmsExantasReport(
            ExantasSessionOutcome.completed, 'already_processed'),
        isFalse);
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, 'pending'),
        isFalse);
    expect(
        confirmsExantasReport(ExantasSessionOutcome.completed, null), isFalse);
  });
  test('matches exact session, peer and Office owner without numeric rounding',
      () {
    final local = <String, dynamic>{
      'rustdesk_session_id': '18446744073709551615',
      'peer_id': '123',
      'from_peer': '321',
      'owner': 'owner-a'
    };
    final remote = <String, dynamic>{
      'rustdesk_session_id': '18446744073709551615',
      'peer_id': '123',
      'from_peer': '321',
      'technician_admin_id': 'owner-a'
    };
    expect(matchesExantasSession(local, remote), isTrue);
    expect(
        matchesExantasSession(local, {...remote, 'peer_id': '456'}), isFalse);
    expect(
        matchesExantasSession(local, {...remote, 'from_peer': '654'}), isFalse);
    expect(
        matchesExantasSession(
            local, {...remote, 'technician_admin_id': 'owner-b'}),
        isFalse);
    expect(
        matchesExantasSession(
            local, {...remote, 'rustdesk_session_id': '18446744073709551614'}),
        isFalse);
    expect(
        matchesExantasSession({...local, 'rustdesk_session_id': '0'},
            {...remote, 'rustdesk_session_id': '0'}),
        isFalse);
  });
  test('network refresh preserves a concurrently saved report', () {
    final merged = mergeExantasReportUpdate(
        {'state': 'queued', 'note': 'Saved offline', 'outcome': 'followUp'},
        {'state': 'draft', 'remote_id': 'remote-id'});
    expect(merged['state'], 'queued');
    expect(merged['note'], 'Saved offline');
    expect(merged['remote_id'], 'remote-id');
  });
  test('a confirmed v2 source marker drops only the unsent local v1 capture',
      () {
    final marker = mergeExantasReportUpdate(
      {
        'id': 'local-row',
        'workflow_contract_version': 1,
        'state': 'draft',
        'started_at': '2026-10-10T10:00:00Z',
        'duration_seconds': 120,
        'note': null,
      },
      {
        'id': 'local-row',
        'workflow_contract_version': 2,
        'workflow_classification': 'unassigned',
        'state': 'v2_pending_identity',
        'peer_id': 'remote-peer',
        'from_peer': 'paired-peer',
      },
    );
    expect(marker['workflow_contract_version'], 2);
    expect(marker['workflow_classification'], 'unassigned');
    expect(marker.containsKey('started_at'), isFalse);
    expect(marker.containsKey('duration_seconds'), isFalse);
    expect(marker.containsKey('note'), isFalse);
  });
  test('v2 context parser accepts only explicit, complete bound identities',
      () {
    final bound = parseExantasWorkContext({
      'status': 'ok',
      'contract_version': 2,
      'classification': 'bound',
      'work_item_id': 'work-a',
      'work_revision': '7',
      'remote_session_id': 'session-a',
      'suppress_legacy': true,
    });
    expect(bound.isV2Bound, isTrue);
    expect(bound.classification, ExantasWorkContextClassification.bound);

    for (final classification in [
      'excluded',
      'unassigned',
      'pending_identity',
    ]) {
      final context = parseExantasWorkContext({
        'status': 'ok',
        'contract_version': 2,
        'classification': classification,
        'work_item_id': null,
        'work_revision': null,
        'remote_session_id': null,
        'suppress_legacy': true,
      });
      expect(context.isV2Bound, isFalse);
    }

    expect(
      () => parseExantasWorkContext({
        'status': 'ok',
        'contract_version': 2,
        'classification': 'bound',
        'suppress_legacy': true,
      }),
      throwsFormatException,
    );
    expect(
      () => parseExantasWorkContext({
        'status': 'ok',
        'contract_version': 2,
        'classification': 'bound',
        'work_item_id': 'work-a',
        'work_revision': '7',
        'remote_session_id': 'session-a',
        'suppress_legacy': false,
      }),
      throwsFormatException,
    );
  });
  test('v2 enabled unknown identity never starts a new v1 capture', () {
    final unassigned = parseExantasWorkContext({
      'status': 'ok',
      'contract_version': 2,
      'classification': 'unassigned',
      'work_item_id': null,
      'work_revision': null,
      'remote_session_id': null,
      'suppress_legacy': true,
    });
    final pending = parseExantasWorkContext({
      'status': 'ok',
      'contract_version': 2,
      'classification': 'pending_identity',
      'work_item_id': null,
      'work_revision': null,
      'remote_session_id': null,
      'suppress_legacy': true,
    });
    expect(shouldCaptureLegacyExantasSession(unassigned), isFalse);
    expect(shouldCaptureLegacyExantasSession(pending), isFalse);
    // Only the explicit disabled/404 compatibility path is represented by null.
    expect(shouldCaptureLegacyExantasSession(null), isTrue);
  });
  test('all v2 source classifications quarantine old queues without resubmit',
      () {
    final oldQueue = <String, dynamic>{
      'id': 'legacy-row',
      'workflow_contract_version': 1,
      'state': 'queued',
      'remote_id': 'old-remote-id',
      'outcome': 'completed',
      'note': 'Keep this encrypted source for review',
    };
    for (final classification in [
      ExantasWorkContextClassification.bound,
      ExantasWorkContextClassification.excluded,
      ExantasWorkContextClassification.unassigned,
      ExantasWorkContextClassification.pendingIdentity,
    ]) {
      final context = ExantasWorkContext(
        classification: classification,
        workItemId: classification == ExantasWorkContextClassification.bound
            ? 'work-id'
            : null,
        workRevision: classification == ExantasWorkContextClassification.bound
            ? '3'
            : null,
        remoteSessionId:
            classification == ExantasWorkContextClassification.bound
                ? 'session-id'
                : null,
        suppressLegacy: true,
      );
      final quarantined = quarantineLegacyExantasReport(oldQueue, context)!;
      expect(quarantined['state'], 'review');
      expect(quarantined['workflow_contract_version'], 1);
      expect(quarantined['remote_id'], 'old-remote-id');
      expect(quarantined['outcome'], 'completed');
      expect(quarantined['note'], oldQueue['note']);
      expect(maySubmitLegacyExantasReport(context), isFalse);
      expect(canPromptExantasReport(quarantined['state']), isFalse);
    }
  });
  test('a v2 lookup failure keeps an already-bound source suppressed', () {
    final marker = <String, dynamic>{
      'workflow_contract_version': 2,
      'workflow_classification': 'bound',
      'state': 'v2_bound',
      'work_item_id': 'work-id',
      'remote_session_id': 'session-id',
      'owner': 'office-a',
      'api': 'https://office-a.example/api/v1',
    };
    final retained = retainExantasV2SuppressionAfterLookupFailure(
      marker,
      DateTime.utc(2026, 10, 10, 12),
    );
    expect(retained['workflow_contract_version'], 2);
    expect(retained['workflow_classification'], 'bound');
    expect(retained['state'], 'v2_bound');
    expect(retained['work_item_id'], 'work-id');
    expect(retained['remote_session_id'], 'session-id');
    expect(retained['last_context_checked_at'], '2026-10-10T12:00:00.000Z');
  });
  test('a pending-identity marker holds an old queue even if v2 later goes away',
      () {
    final oldQueue = <String, dynamic>{
      'id': 'v1-row',
      'owner': 'office-a',
      'api': 'https://office-a.example/api/v1',
      'local_session': 'peer:local-session',
      'state': 'queued',
      'workflow_contract_version': 1,
      'note': 'Retain the original report',
    };
    final marker = <String, dynamic>{
      'id': 'v2-marker',
      'owner': 'office-a',
      'api': 'https://office-a.example/api/v1',
      'local_session': 'peer:local-session',
      'workflow_contract_version': 2,
      'workflow_classification': 'pendingIdentity',
    };
    expect(matchesExantasV2SuppressionMarker(oldQueue, marker), isTrue);
    final held = quarantineLegacyExantasReportFromMarker(oldQueue, marker)!;
    expect(held['workflow_contract_version'], 1);
    expect(held['state'], 'review');
    expect(held['note'], 'Retain the original report');
    expect(canPromptExantasReport(held['state']), isFalse);
    expect(
      quarantineLegacyExantasReportFromMarker(
        oldQueue,
        {...marker, 'owner': 'office-b'},
      ),
      isNull,
    );
  });
  test(
      'legacy offline queue uses v1 only when v2 is explicitly unavailable',
      () {
    final unassigned = ExantasWorkContext(
      classification: ExantasWorkContextClassification.unassigned,
      workItemId: null,
      workRevision: null,
      remoteSessionId: null,
      suppressLegacy: true,
    );
    final pending = ExantasWorkContext(
      classification: ExantasWorkContextClassification.pendingIdentity,
      workItemId: null,
      workRevision: null,
      remoteSessionId: null,
      suppressLegacy: true,
    );
    expect(maySubmitLegacyExantasReport(null), isTrue);
    expect(maySubmitLegacyExantasReport(unassigned), isFalse);
    expect(maySubmitLegacyExantasReport(pending), isFalse);
    expect(maySubmitLegacyExantasReport(ExantasWorkContext(
      classification: ExantasWorkContextClassification.excluded,
      workItemId: null,
      workRevision: null,
      remoteSessionId: null,
      suppressLegacy: true,
    )), isFalse);
    // A network/HTTP error is not represented by null; it throws before this
    // compatibility decision and leaves the encrypted queue row in place.
    var decoded = false;
    expect(
        decodeExantasOptional404<Map<String, dynamic>>(
          404,
          () {
            decoded = true;
            return <String, dynamic>{};
          },
        ),
        isNull);
    expect(decoded, isFalse);
    expect(
      () => decodeExantasOptional404<Map<String, dynamic>>(
        503,
        () => throw StateError('Office API unavailable'),
      ),
      throwsStateError,
    );
  });
  test('outbox rows are fenced to current account across A-B-logout-A', () {
    final row = <String, dynamic>{
      'owner': 'office-a',
      'api': 'https://office-a.example/api/v1',
      'workflow_contract_version': 2,
      'workflow_classification': 'pending_identity',
    };
    bool inScope({
      required bool loggedIn,
      required String owner,
      required String api,
    }) =>
        belongsToExantasOfficeScope(
          row,
          loggedIn: loggedIn,
          officeUserId: owner,
          apiBase: api,
        );

    expect(
      inScope(
        loggedIn: true,
        owner: 'office-a',
        api: 'https://office-a.example/api/v1',
      ),
      isTrue,
    );
    expect(
      inScope(
        loggedIn: true,
        owner: 'office-b',
        api: 'https://office-b.example/api/v1',
      ),
      isFalse,
    );
    expect(
      inScope(
        loggedIn: false,
        owner: '',
        api: 'https://office-a.example/api/v1',
      ),
      isFalse,
    );
    expect(
      inScope(
        loggedIn: true,
        owner: 'office-a',
        api: 'https://office-a.example/api/v1',
      ),
      isTrue,
    );
  });
  test('retry cannot regress an acknowledged report', () {
    final merged = mergeExantasReportUpdate({'state': 'synced', 'note': 'Done'},
        {'state': 'queued', 'error': 'timeout'});
    expect(merged['state'], 'synced');
    expect(merged.containsKey('error'), isFalse);
  });
  group('buildExantasSessionReportCommand', () {
    test('builds a completed report command', () {
      expect(
        buildExantasSessionReportCommand(
          ExantasSessionOutcome.completed,
          '  Ο έλεγχος ολοκληρώθηκε.  ',
        ),
        '~ Ο έλεγχος ολοκληρώθηκε.',
      );
    });

    test('builds a follow-up report command', () {
      expect(
        buildExantasSessionReportCommand(
          ExantasSessionOutcome.followUp,
          'Χρειάζεται ανταλλακτικό.',
        ),
        '# Χρειάζεται ανταλλακτικό.',
      );
    });

    test('builds a no-record command without a note', () {
      expect(
        buildExantasSessionReportCommand(
          ExantasSessionOutcome.noRecord,
          '',
        ),
        '-',
      );
    });

    test('rejects completed reports without a note', () {
      expect(
        () => buildExantasSessionReportCommand(
          ExantasSessionOutcome.completed,
          '   ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects follow-up reports without a note', () {
      expect(
        () => buildExantasSessionReportCommand(
          ExantasSessionOutcome.followUp,
          '',
        ),
        throwsArgumentError,
      );
    });
  });
}
