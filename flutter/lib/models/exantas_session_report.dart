enum ExantasSessionOutcome {
  completed,
  followUp,
  noRecord,
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
