import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exantas_field_visit.dart';
import '../../models/exantas_financial_ledger.dart' show exantasAbandonEligible;
import '../ui/ex_card.dart';
import '../ui/ex_confirm_dialog.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'exantas_field_visit_attendance.dart';
import 'exantas_field_visit_flow.dart';

/// Read-only adapter: what a visit still waits for, in Greek, plus the one next
/// action. The Pending center list itself is not modified; this section sits at
/// the top of the same Εκκρεμή tab.
({String label, ExStatus status}) fvPendingState(FieldVisit v) {
  final rejected = v.ops.where((o) => o.state == 'rejected').toList();
  if (rejected.isNotEmpty) {
    final r = rejected.first.rejected ?? const {};
    return (label: FvStrings.rejection('${r['code']}', '${r['message']}'), status: ExStatus.danger);
  }
  final op = v.closeOp;
  if (op != null && op.sent && op.state == 'unknown') return (label: FvStrings.pendingCloseUnresolved, status: ExStatus.warning);
  return (label: FvStrings.pendingWaiting(v.ops.length), status: ExStatus.neutral);
}

/// Visits with unsynced work for the Εκκρεμή tab.
class FvUnsyncedList extends StatelessWidget {
  const FvUnsyncedList({super.key, required this.env});
  final FvEnv env;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: env.sync,
      builder: (context, _) {
        final items = env.sync.unsynced;
        if (items.isEmpty) return const SizedBox.shrink();
        final t = context.ex;
        final text = Theme.of(context).textTheme;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: ExantasTokens.space2), child: Semantics(header: true, child: Text(FvStrings.pendingTitle, style: text.titleMedium))),
          for (final v in items)
            Padding(
                padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
                child: ExCard(
                    key: ValueKey('fv-pending-${v.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.customerName, style: text.titleSmall),
                      Text(v.jobTypeLabel, style: text.bodyMedium),
                      const SizedBox(height: ExantasTokens.space1),
                      Builder(builder: (_) {
                        final s = fvPendingState(v);
                        return ExStatusPill(s.label, status: s.status);
                      }),
                      const SizedBox(height: ExantasTokens.space2),
                      Wrap(spacing: ExantasTokens.space2, children: [
                        FilledButton.tonal(
                            key: ValueKey('fv-pending-open-${v.id}'),
                            onPressed: () => openFvVisit(context, env, v.id),
                            child: const Text(FvStrings.openVisit)),
                        FilledButton.tonal(
                            key: ValueKey('fv-pending-sync-${v.id}'),
                            onPressed: () => unawaited(env.sync.sync(force: true).catchError((_) {})),
                            child: const Text(FvStrings.syncNow)),
                        if (v.closeOp != null && v.closeOp!.sent && exantasAbandonEligible(v.closeOp!.marks, env.now()))
                          TextButton(
                              key: ValueKey('fv-pending-abandon-${v.id}'),
                              onPressed: () async {
                                final ok = await showExConfirmDialog(context,
                                    title: FvStrings.abandonTitle, message: FvStrings.abandonMessage, confirmLabel: FvStrings.abandonConfirm, destructive: true);
                                if (ok) await env.sync.abandonClose(v.id).catchError((Object _) => false);
                              },
                              child: Text(FvStrings.abandonConfirm, style: TextStyle(color: t.danger))),
                        for (final o in v.ops.where((o) => o.state == 'rejected'))
                          TextButton(
                              key: ValueKey('fv-pending-dismiss-${o.key}'),
                              onPressed: () => env.sync.dismissRejected(v.id, o.key),
                              child: const Text(FvStrings.dismiss)),
                      ]),
                    ]))),
        ]);
      });
}
