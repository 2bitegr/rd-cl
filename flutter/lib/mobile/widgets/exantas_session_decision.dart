import 'package:flutter/material.dart';
import '../ui/ex_sheet.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_theme.dart';

/// Non-blocking notice shown after a session ends. The row is already saved as
/// «Αργότερα»; dismissing the notice changes nothing.
SnackBar exantasSessionSavedSnackBar({required VoidCallback onDecide}) =>
    SnackBar(
        key: const ValueKey('session-saved-snackbar'),
        duration: const Duration(seconds: 10),
        content: const Text('Η συνεδρία αποθηκεύτηκε στα Εκκρεμή'),
        action: SnackBarAction(label: 'Απόφαση τώρα', onPressed: onDecide));

const _tiles = <(String, String, String, IconData)>[
  ('automatic', 'Κανονική χρέωση', 'Προεπισκόπηση χρέωσης από το Office', Icons.receipt_long_outlined),
  ('free', 'Χωρίς χρέωση', 'Ολοκλήρωση χωρίς χρέωση', Icons.volunteer_activism_outlined),
  ('later', 'Αργότερα', 'Η συνεδρία μένει στα Εκκρεμή', Icons.schedule_outlined),
  ('ignore', 'Εξαίρεση', 'Δεν αφορά χρέωση ή εργασία', Icons.block_outlined),
];

/// Returns 'automatic' | 'free' | 'later' | 'ignore', or null when closed
/// without a decision (no call may follow a null).
Future<String?> showExantasDecisionSheet(BuildContext context,
        {required String peerId, required TextEditingController note}) =>
    showExSheet<String>(
        context: context,
        builder: (_) => ExantasSessionDecisionSheet(peerId: peerId, note: note));

/// Closing or accepting the default returns no financial instruction.
class ExantasSessionDecisionSheet extends StatefulWidget {
  const ExantasSessionDecisionSheet(
      {super.key, required this.peerId, required this.note});
  final String peerId;
  final TextEditingController note;
  @override
  State<ExantasSessionDecisionSheet> createState() => _DecisionState();
}

class _DecisionState extends State<ExantasSessionDecisionSheet> {
  String selected = 'later';
  bool done = false;

  void finish(String? value) {
    if (done) return; // duplicate tap guard
    done = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ολοκλήρωση συνεδρίας', style: text.titleLarge),
          const SizedBox(height: ExantasTokens.space1),
          Text('RustDesk ${widget.peerId}', style: text.bodyMedium),
          const SizedBox(height: ExantasTokens.space1),
          Text('Η λήξη σύνδεσης δεν ολοκληρώνει αυτόματα την εργασία.',
              style: text.bodySmall?.copyWith(color: t.textSecondary)),
          const SizedBox(height: ExantasTokens.space3),
          for (final (value, label, hint, icon) in _tiles)
            Padding(
                padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
                child: Material(
                    color: selected == value ? t.accentSoft : t.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ExantasTokens.radiusMd),
                        side: BorderSide(
                            color: selected == value ? t.accent : t.border,
                            width: selected == value ? 2 : 1)),
                    child: InkWell(
                        key: ValueKey('decision-tile-$value'),
                        customBorder: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(ExantasTokens.radiusMd)),
                        onTap: () => setState(() => selected = value),
                        child: Padding(
                            padding: const EdgeInsets.all(ExantasTokens.space3),
                            child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 56),
                                child: Row(children: [
                                  Icon(icon, color: selected == value ? t.accent : t.textSecondary),
                                  const SizedBox(width: ExantasTokens.space3),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                        Text(label, style: text.titleSmall),
                                        Text(hint, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                                      ])),
                                  if (value == 'later')
                                    const ExStatusPill('Προεπιλογή', status: ExStatus.neutral),
                                  if (selected == value)
                                    Padding(
                                        padding: const EdgeInsets.only(left: ExantasTokens.space2),
                                        child: Icon(Icons.check_circle, color: t.accent)),
                                ])))))),
          const SizedBox(height: ExantasTokens.space1),
          TextField(
              key: const ValueKey('decision-note'),
              controller: widget.note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Περιγραφή εργασίας')),
          const SizedBox(height: ExantasTokens.space3),
          FilledButton(
              key: const ValueKey('decision-save'),
              onPressed: () => finish(selected),
              child: const Text('Αποθήκευση')),
          TextButton(
              key: const ValueKey('decision-close'),
              onPressed: () => finish(null),
              child: const Text('Κλείσιμο χωρίς απόφαση')),
        ]);
  }
}
