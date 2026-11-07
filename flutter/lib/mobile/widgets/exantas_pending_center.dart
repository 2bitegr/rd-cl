import 'package:flutter/material.dart';
import '../../models/exantas_office_work.dart' show formatAthens, formatDurationSeconds;
import '../../models/exantas_pending.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_theme.dart';

ExStatus pendingStatus(PendingKind k) => switch (k) {
      PendingKind.decision => ExStatus.info,
      PendingKind.priorRequest => ExStatus.warning,
      PendingKind.officeReview => ExStatus.danger,
      _ => ExStatus.neutral,
    };

/// Pending center list. Presentation of classified journal rows only; the
/// controller owns every action.
class ExantasPendingList extends StatelessWidget {
  const ExantasPendingList(
      {super.key,
      required this.items,
      required this.now,
      required this.busy,
      required this.onAction,
      required this.onAbandon});
  final List<PendingItem> items;
  final DateTime now;
  final bool busy;
  final void Function(PendingItem) onAction;
  final void Function(PendingItem) onAbandon;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const ExCard(
          padding: EdgeInsets.zero,
          child: ExEmptyState(
              icon: Icons.task_alt_outlined,
              title: 'Δεν υπάρχουν εκκρεμείς αποφάσεις συνεδριών.'));
    }
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final item in items)
        Padding(
            padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
            child: ExCard(
                key: ValueKey('pending-${item.row['event_id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            item.customerName ?? (item.isCreation ? 'Νέα εργασία' : 'Χωρίς επιβεβαιωμένη αντιστοίχιση'),
                            style: text.titleSmall)),
                    ExStatusPill(item.label, status: pendingStatus(item.kind)),
                  ]),
                  if (item.workTitle != null) Text(item.workTitle!, style: text.bodyMedium),
                  const SizedBox(height: ExantasTokens.space1),
                  Text(item.isCreation ? 'Πελάτης ${item.row['customer_id']}' : 'RustDesk ${item.peerId}',
                      style: text.bodySmall?.copyWith(color: t.textSecondary)),
                  Text(
                      [
                        formatPendingAge(pendingSince(item.row), now),
                        if (pendingAuthoritativeEnd(item.row) != null)
                          'Λήξη (πάροχος) ${formatAthens(pendingAuthoritativeEnd(item.row))}'
                              '${item.row['provider_duration_seconds'] != null ? ' · ${formatDurationSeconds(num.tryParse('${item.row['provider_duration_seconds']}') ?? 0)}' : ''}',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: text.bodySmall?.copyWith(color: t.textSecondary)),
                  const SizedBox(height: ExantasTokens.space2),
                  Wrap(spacing: ExantasTokens.space2, children: [
                    FilledButton.tonal(
                        key: ValueKey('pending-action-${item.row['event_id']}'),
                        onPressed: busy ? null : () => onAction(item),
                        child: Text(pendingActionLabel(item.action))),
                    if (item.kind == PendingKind.priorRequest && pendingCanAbandon(item.row, now))
                      TextButton(
                          key: ValueKey('pending-abandon-${item.row['event_id']}'),
                          onPressed: busy ? null : () => onAbandon(item),
                          child: Text('Ακύρωση εκκρεμούς αιτήματος', style: TextStyle(color: t.danger))),
                  ]),
                ]))),
    ]);
  }
}
