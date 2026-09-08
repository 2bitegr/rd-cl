import 'package:flutter_hbb/models/exantas_session_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local lifecycle key does not depend on the delayed native session id', () {
    const flutterSession = '25ff0f78-6f95-4be5-99fd-7c3a006d05ea';
    expect(buildExantasLocalSessionKey('86355592', flutterSession),
        '86355592:$flutterSession');
    expect(resolveExantasRustDeskSessionId('0', '18446744073709551615'),
        '18446744073709551615');
    expect(resolveExantasRustDeskSessionId('123', '0'), '123');
  });
  test('close prompts an already discovered disconnect but never a saved report', () {
    expect(canPromptExantasReport('active'), isTrue);
    expect(canPromptExantasReport('draft'), isTrue);
    expect(canPromptExantasReport('queued'), isFalse);
    expect(canPromptExantasReport('synced'), isFalse);
    expect(canPromptExantasReport('review'), isFalse);
  });
  test('only explicit acknowledgement confirms the submitted report', () {
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, 'final'), isTrue);
    expect(confirmsExantasReport(ExantasSessionOutcome.followUp, 'pending'), isTrue);
    expect(confirmsExantasReport(ExantasSessionOutcome.noRecord, 'noop'), isTrue);
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, 'already_processed'), isFalse);
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, 'pending'), isFalse);
    expect(confirmsExantasReport(ExantasSessionOutcome.completed, null), isFalse);
  });
  test('matches exact session, peer and Office owner without numeric rounding', () {
    final local = <String, dynamic>{'rustdesk_session_id': '18446744073709551615',
      'peer_id': '123', 'from_peer': '321', 'owner': 'owner-a'};
    final remote = <String, dynamic>{'rustdesk_session_id': '18446744073709551615',
      'peer_id': '123', 'from_peer': '321', 'technician_admin_id': 'owner-a'};
    expect(matchesExantasSession(local, remote), isTrue);
    expect(matchesExantasSession(local, {...remote, 'peer_id': '456'}), isFalse);
    expect(matchesExantasSession(local, {...remote, 'from_peer': '654'}), isFalse);
    expect(matchesExantasSession(local, {...remote, 'technician_admin_id': 'owner-b'}), isFalse);
    expect(matchesExantasSession(local, {...remote, 'rustdesk_session_id': '18446744073709551614'}), isFalse);
    expect(matchesExantasSession({...local, 'rustdesk_session_id': '0'},
        {...remote, 'rustdesk_session_id': '0'}), isFalse);
  });
  test('network refresh preserves a concurrently saved report', () {
    final merged = mergeExantasReportUpdate(
      {'state': 'queued', 'note': 'Saved offline', 'outcome': 'followUp'},
      {'state': 'draft', 'remote_id': 'remote-id'});
    expect(merged['state'], 'queued');
    expect(merged['note'], 'Saved offline');
    expect(merged['remote_id'], 'remote-id');
  });
  test('retry cannot regress an acknowledged report', () {
    final merged = mergeExantasReportUpdate(
      {'state': 'synced', 'note': 'Done'}, {'state': 'queued', 'error': 'timeout'});
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
