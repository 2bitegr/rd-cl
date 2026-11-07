// Kept dependency-free so Office read models can reuse it without pulling in the companion service.
/// No client duration or price is promoted to Office evidence.
bool androidSessionVerified(Map<String, dynamic> session) {
  final start = DateTime.tryParse('${session['started_at'] ?? ''}');
  final end = DateTime.tryParse('${session['ended_at'] ?? ''}');
  final seconds = num.tryParse('${session['duration_seconds'] ?? ''}');
  return session['timing_quality'] == 'verified' && start != null && end != null &&
      end.isAfter(start) && seconds != null && seconds.isFinite && seconds > 0;
}
