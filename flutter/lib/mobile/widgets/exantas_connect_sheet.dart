import 'dart:async';
import 'package:flutter/material.dart';
import '../ui/ex_list_row.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_theme.dart';

/// What the technician explicitly chose. `workId == null` is «χωρίς εργασία».
class ExantasConnectChoice {
  const ExantasConnectChoice.withoutWork() : workId = null;
  const ExantasConnectChoice.work(String id) : workId = id;
  final String? workId;
}

class ExantasWorkOption {
  const ExantasWorkOption({required this.id, required this.title, required this.customerName});
  final String id, title, customerName;
}

/// Closing the sheet returns null: nothing is connected and nothing is reused
/// from a previous selection.
Future<ExantasConnectChoice?> showExantasConnectSheet(BuildContext context,
        {required String peerId,
        required Future<List<ExantasWorkOption>> Function() loadSuggestions,
        required List<ExantasWorkOption> openWorks}) =>
    showModalBottomSheet<ExantasConnectChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ExantasConnectSheet(peerId: peerId, loadSuggestions: loadSuggestions, openWorks: openWorks));

class ExantasConnectSheet extends StatefulWidget {
  const ExantasConnectSheet(
      {super.key, required this.peerId, required this.loadSuggestions, required this.openWorks});
  final String peerId;
  final Future<List<ExantasWorkOption>> Function() loadSuggestions;
  final List<ExantasWorkOption> openWorks;
  @override
  State<ExantasConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<ExantasConnectSheet> {
  bool picking = false, done = false;
  List<ExantasWorkOption> suggestions = const [];
  bool loadingSuggestions = true;

  @override
  void initState() {
    super.initState();
    unawaited(widget.loadSuggestions().then((v) {
      if (mounted) setState(() { suggestions = v; loadingSuggestions = false; });
    }).catchError((Object _) {
      if (mounted) setState(() => loadingSuggestions = false);
    }));
  }

  void choose(ExantasConnectChoice c) {
    if (done) return; // duplicate tap guard
    done = true;
    Navigator.pop(context, c);
  }

  Widget workRow(ExantasWorkOption w, {bool suggested = false}) => ExListRow(
      key: ValueKey('${suggested ? 'connect-suggest' : 'connect-work'}-${w.id}'),
      icon: Icons.work_outline,
      title: w.title,
      subtitle: w.customerName,
      trailing: suggested ? const ExStatusPill('Πρόταση', status: ExStatus.info) : null,
      onTap: () => choose(ExantasConnectChoice.work(w.id)));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = context.ex;
    final others = widget.openWorks.where((w) => !suggestions.any((s) => s.id == w.id)).toList();
    return SafeArea(
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(ExantasTokens.gutter, ExantasTokens.space4, ExantasTokens.gutter,
                ExantasTokens.gutter + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Σύνδεση στο ${widget.peerId}', style: text.titleLarge),
              const SizedBox(height: ExantasTokens.space3),
              if (!picking) ...[
                if (loadingSuggestions)
                  const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2))
                else if (suggestions.isNotEmpty) ...[
                  Text('Πρόταση: ο υπολογιστής ανήκει σε πελάτη με ανοιχτή εργασία σου. Πάτα για να τη χρησιμοποιήσεις.',
                      style: text.bodySmall?.copyWith(color: t.textSecondary)),
                  for (final s in suggestions) workRow(s, suggested: true),
                  const SizedBox(height: ExantasTokens.space2),
                ],
                FilledButton(
                    key: const ValueKey('connect-no-work'),
                    onPressed: () => choose(const ExantasConnectChoice.withoutWork()),
                    child: const Text('Σύνδεση χωρίς εργασία')),
                const SizedBox(height: ExantasTokens.space2),
                OutlinedButton(
                    key: const ValueKey('connect-pick-work'),
                    onPressed: () => setState(() => picking = true),
                    child: const Text('Επιλογή εργασίας')),
              ] else ...[
                Text('Επίλεξε εργασία', style: text.titleSmall),
                if (suggestions.isEmpty && others.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('Δεν έχεις ανοιχτές εργασίες.')),
                for (final s in suggestions) workRow(s, suggested: true),
                for (final w in others) workRow(w),
                TextButton(
                    key: const ValueKey('connect-back'),
                    onPressed: () => setState(() => picking = false),
                    child: const Text('Πίσω')),
              ],
            ])));
  }
}
