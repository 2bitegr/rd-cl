import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/exantas_identity.dart';

/// The maintenance card is absent until Office has verified the local sign-in.
class ExantasIdentitySettings extends StatefulWidget {
  const ExantasIdentitySettings(
      {super.key,
      required this.actions,
      required this.unlocked,
      required this.available,
      required this.cardBuilder,
      this.hasPendingReports});
  final ExantasIdentityActions actions;
  final bool unlocked;
  final bool available;
  final Widget Function(Widget) cardBuilder;
  final Future<bool> Function()? hasPendingReports;
  @override
  State<ExantasIdentitySettings> createState() =>
      _ExantasIdentitySettingsState();
}

class _ExantasIdentitySettingsState extends State<ExantasIdentitySettings> {
  ExantasIdentityAccess? _access;
  Timer? _timer;
  bool _checking = false;
  bool _busy = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _refresh(verify: true);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _ticks++;
      _refresh(verify: _access == null || _ticks % 10 == 0);
    });
  }

  Future<void> _refresh({required bool verify}) async {
    if (_checking || _busy || !widget.available) return;
    _checking = true;
    try {
      final previous = _access;
      if (previous != null &&
          !await widget.actions.identitySessionMatches(previous)) {
        if (mounted) setState(() => _access = null);
        verify = true;
      }
      if (verify) {
        final access = await widget.actions.authorizeIdentityReset();
        if (mounted) setState(() => _access = access);
      }
    } catch (_) {
      if (mounted) setState(() => _access = null);
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final access = _access;
    if (access == null || _busy || !widget.unlocked) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Δημιουργία νέου RustDesk ID'),
              content: Text(
                  'Θα αλλάξει το ID αυτού του υπολογιστή: ${access.currentId}.\n\n'
                  'Θα αποθηκευτεί αντίγραφο επαναφοράς και θα χρειαστεί νέα σύνδεση στο Office. '
                  'Το ιστορικό και οι αντιστοιχίσεις πελατών διατηρούνται.\n\n'
                  'Κλείστε πρώτα όλες τις απομακρυσμένες συνδέσεις.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Ακύρωση')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Δημιουργία νέου ID')),
              ],
            ));
    if (confirm != true || !mounted || !widget.unlocked) return;
    setState(() => _busy = true);
    ExantasIdentityResult result;
    var reportsChecked = false;
    try {
      if (await widget.hasPendingReports?.call() == true) {
        result = const ExantasIdentityResult(
            success: false, code: 'pending_reports', officeSignedOut: false);
      } else {
        reportsChecked = true;
        result = await widget.actions.regenerateIdentity(access);
      }
    } catch (_) {
      result = ExantasIdentityResult(
          success: false,
          code: reportsChecked
              ? 'result_unconfirmed'
              : 'local_report_check_failed',
          officeSignedOut: reportsChecked);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _access = null;
    });
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(
                  result.success ? 'Νέο RustDesk ID' : 'Έλεγχος αλλαγής ID'),
              content: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (result.newId.isNotEmpty)
                      SelectableText(result.newId,
                          style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text(result.message),
                    if (result.backupPath.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                          'Αντίγραφο επαναφοράς (περιέχει ιδιωτικά κλειδιά):'),
                      SelectableText(result.backupPath),
                    ],
                    if (result.officeSignedOut && !result.success) ...[
                      const SizedBox(height: 12),
                      const Text('Χρειάζεται νέα σύνδεση τεχνικού στο Office.'),
                    ],
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Κλείσιμο'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (!widget.available || access == null) return const SizedBox.shrink();
    return widget.cardBuilder(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ID αυτού του υπολογιστή'),
      const SizedBox(height: 4),
      SelectableText(access.currentId,
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
          'Η αλλαγή αφορά αυτόν τον υπολογιστή. Το ιστορικό στο Office διατηρείται. Θα χρειαστεί νέα σύνδεση τεχνικού.'),
      const SizedBox(height: 12),
      FilledButton(
          onPressed: !widget.unlocked || _busy ? null : _generate,
          child: Text(_busy ? 'Δημιουργία…' : 'Δημιουργία νέου ID')),
      if (!widget.unlocked)
        const Text('Ξεκλειδώστε πρώτα τις ρυθμίσεις ασφαλείας.'),
    ]));
  }
}
