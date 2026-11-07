import 'exantas_financial_ledger.dart';

/// Classification of the existing local journal rows for the Pending center.
/// Pure: the journal is read, never changed; Office stays the authority.
enum PendingKind { identity, association, timing, decision, priorRequest, officeReview }

enum PendingAction { refresh, associate, decide, checkRequest, openOffice }

class PendingItem {
  const PendingItem(this.row, this.kind, this.action);
  final Map<String, dynamic> row;
  final PendingKind kind;
  final PendingAction action;

  String get peerId => '${row['peer_id'] ?? ''}';
  String get label => pendingLabel(kind);

  /// Customer/work are shown only after Office confirmed the binding.
  String? get customerName =>
      row['work_item_id'] == null ? null : _t(row['customer_name']);
  String? get workTitle =>
      row['work_item_id'] == null ? null : _t(row['work_title']);
  bool get isCreation => row['kind'] == 'work_creation';
}

String? _t(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

String pendingLabel(PendingKind kind) => switch (kind) {
      PendingKind.identity => 'Αναμονή ταυτότητας',
      PendingKind.association => 'Αναμονή αντιστοίχισης',
      PendingKind.timing => 'Αναμονή επαλήθευσης διάρκειας',
      PendingKind.decision => 'Χρειάζεται απόφαση',
      PendingKind.priorRequest => 'Έλεγχος προηγούμενου αιτήματος',
      PendingKind.officeReview => 'Απαιτείται έλεγχος Office',
    };

String pendingActionLabel(PendingAction a) => switch (a) {
      PendingAction.refresh => 'Ανανέωση',
      PendingAction.associate => 'Σύνδεση με εργασία',
      PendingAction.decide => 'Απόφαση',
      PendingAction.checkRequest => 'Έλεγχος αιτήματος',
      PendingAction.openOffice => 'Άνοιγμα στο Office',
    };

bool _noNative(dynamic id) {
  final s = id?.toString() ?? '';
  return s.isEmpty || s == '0';
}

/// Precedence: Office review > prior request > identity > association > timing
/// > decision. Rows lacking verified timing facts fall to [PendingKind.decision]
/// only when Office has not said otherwise; the preview itself still gates.
PendingKind classifyPending(Map<String, dynamic> row) {
  if (row['office_review'] != null || row['resolved_in_office_report'] != null) {
    return PendingKind.officeReview;
  }
  if (row['financial_operation'] != null || row['creation_pending'] == true) {
    return PendingKind.priorRequest;
  }
  if (_noNative(row['rustdesk_session_id'])) return PendingKind.identity;
  if (row['work_item_id'] == null) return PendingKind.association;
  if (row['ended_at'] == null || row['timing_verified'] == false) {
    return PendingKind.timing;
  }
  return PendingKind.decision;
}

PendingAction actionFor(PendingKind kind) => switch (kind) {
      PendingKind.identity => PendingAction.refresh,
      PendingKind.association => PendingAction.associate,
      PendingKind.timing => PendingAction.refresh,
      PendingKind.decision => PendingAction.decide,
      PendingKind.priorRequest => PendingAction.checkRequest,
      PendingKind.officeReview => PendingAction.openOffice,
    };

PendingItem classifyRow(Map<String, dynamic> row) {
  final kind = classifyPending(row);
  return PendingItem(row, kind, actionFor(kind));
}

/// Newest first by start time; ties keep input order.
List<PendingItem> classifyPendingRows(Iterable<Map<String, dynamic>> rows) {
  final items = rows.map(classifyRow).toList();
  DateTime? start(PendingItem i) =>
      DateTime.tryParse('${i.row['started_at'] ?? i.row['reserved_at'] ?? ''}');
  final indexed = items.asMap().entries.toList()
    ..sort((a, b) {
      final x = start(a.value), y = start(b.value);
      if (x == null || y == null) return a.key.compareTo(b.key);
      final c = y.compareTo(x);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

int pendingNeedingDecision(Iterable<PendingItem> items) =>
    items.where((i) => i.kind == PendingKind.decision).length;

/// "πριν 3 ημέρες" style age. Never negative.
String formatPendingAge(DateTime? since, DateTime now) {
  if (since == null) return '';
  final d = now.difference(since);
  if (d.inMinutes < 1) return 'μόλις τώρα';
  if (d.inMinutes < 60) {
    final n = d.inMinutes;
    return n == 1 ? 'πριν 1 λεπτό' : 'πριν $n λεπτά';
  }
  if (d.inHours < 24) {
    final n = d.inHours;
    return n == 1 ? 'πριν 1 ώρα' : 'πριν $n ώρες';
  }
  final n = d.inDays;
  return n == 1 ? 'πριν 1 ημέρα' : 'πριν $n ημέρες';
}

DateTime? pendingSince(Map<String, dynamic> row) => DateTime.tryParse(
    '${row['started_at'] ?? row['reserved_at'] ?? ''}');

/// Provider (Office-confirmed) end time, when the row remembers one.
DateTime? pendingAuthoritativeEnd(Map<String, dynamic> row) =>
    row['timing_verified'] == true
        ? DateTime.tryParse('${row['provider_ended_at'] ?? ''}')
        : null;

/// Abandon is offered only for a prior-request row whose marks prove the key was
/// never applied and whose reservation is at least two minutes old.
bool pendingCanAbandon(Map<String, dynamic> row, DateTime now) {
  final op = row['financial_operation'];
  if (op is Map) return exantasAbandonEligible(op, now);
  if (row['creation_pending'] == true) return exantasAbandonEligible(row, now);
  return false;
}

/// One-line Home summary, e.g. "2 χρειάζονται απόφαση · 1 έλεγχος αιτήματος".
String pendingSummary(List<PendingItem> items) {
  if (items.isEmpty) return '';
  int n(PendingKind k) => items.where((i) => i.kind == k).length;
  final parts = <String>[
    if (n(PendingKind.decision) > 0) '${n(PendingKind.decision)} χρειάζονται απόφαση',
    if (n(PendingKind.priorRequest) > 0) '${n(PendingKind.priorRequest)} έλεγχος αιτήματος',
    if (n(PendingKind.officeReview) > 0) '${n(PendingKind.officeReview)} έλεγχος Office',
    if (n(PendingKind.identity) + n(PendingKind.association) + n(PendingKind.timing) > 0)
      '${n(PendingKind.identity) + n(PendingKind.association) + n(PendingKind.timing)} σε αναμονή',
  ];
  return parts.join(' · ');
}
