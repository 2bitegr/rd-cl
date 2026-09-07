import 'package:flutter_hbb/models/exantas_session_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
