import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../models/exantas_install_readiness.dart';

class InstallReadinessPanel extends StatefulWidget {
  const InstallReadinessPanel({super.key, required this.target,
    this.client, this.onReport, this.onBusy, this.autoRefresh = false});
  final String target;
  final InstallReadinessClient? client;
  final ValueChanged<InstallReadinessReport?>? onReport;
  final ValueChanged<bool>? onBusy;
  final bool autoRefresh;

  @override
  State<InstallReadinessPanel> createState() => _InstallReadinessPanelState();
}

class _InstallReadinessPanelState extends State<InstallReadinessPanel> {
  late final InstallReadinessClient _client = widget.client ?? InstallReadinessClient();
  InstallReadinessReport? _report;
  bool _busy = false;
  String? _message;
  int _generation = 0;
  Timer? _expiry;
  Timer? _refresh;
  final _started = DateTime.now();

  @override
  void initState() { super.initState(); unawaited(_check()); }

  @override
  void didUpdateWidget(covariant InstallReadinessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) unawaited(_check());
  }

  @override
  void dispose() { _generation++; _expiry?.cancel(); _refresh?.cancel(); super.dispose(); }

  Future<void> _check() async {
    final generation = ++_generation;
    _expiry?.cancel();
    _refresh?.cancel();
    setState(() { _busy = true; _report = null; });
    widget.onBusy?.call(true);
    widget.onReport?.call(null);
    try {
      final report = await _client.check(widget.target);
      if (!mounted || generation != _generation) return;
      setState(() { _report = report; _message = null; });
      widget.onReport?.call(report);
      _expiry = Timer(const Duration(seconds: 120), () {
        if (!mounted || generation != _generation) return;
        setState(() { _report = null; _message = 'Ο έλεγχος έληξε. Πατήστε επανέλεγχο για τρέχουσα κατάσταση.'; });
        widget.onReport?.call(null);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _message = 'Ο έλεγχος δεν επιβεβαιώθηκε. Επαναλάβετε τον έλεγχο.'; });
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; });
        widget.onBusy?.call(false);
        if (widget.autoRefresh && _report?.ready != true && DateTime.now().difference(_started).inSeconds < 120) {
          _refresh = Timer(const Duration(seconds: 5), () { if (mounted && !_busy) unawaited(_check()); });
        }
      }
    }
  }

  Future<void> _repair(InstallReadinessCheck check) async {
    final report = _report;
    if (_busy || report == null || check.action == null) return;
    _refresh?.cancel();
    final windows = check.action == 'windows_update';
    final description = windows
        ? 'Θα ανοίξουν οι ρυθμίσεις Windows Update. Δεν θα γίνει αυτόματη επανεκκίνηση ούτε διαγραφή εκκρεμοτήτων.'
        : check.action == 'start_service'
            ? 'Θα ζητηθούν δικαιώματα διαχειριστή για εκκίνηση μόνο της υφιστάμενης επαληθευμένης υπηρεσίας Exantas Support.\n${report.repairTarget ?? ''}'
            : 'Θα ζητηθούν δικαιώματα διαχειριστή για αυτόματη εκκίνηση μόνο της υφιστάμενης επαληθευμένης υπηρεσίας Exantas Support με τα Windows.\n${report.repairTarget ?? ''}';
    setState(() { _busy = true; });
    widget.onBusy?.call(true);
    final generation = _generation;
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Επιβεβαίωση ενέργειας'), content: Text(description), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ακύρωση')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Επιβεβαίωση')),
      ]));
    if (!mounted || generation != _generation) return;
    if (approved != true) { setState(() { _busy = false; }); widget.onBusy?.call(false); return; }
    var applied = false;
    try {
      if (windows) {
        applied = await launchUrlString('ms-settings:windowsupdate', mode: LaunchMode.externalApplication);
      } else {
        if (report.fingerprint == null) throw StateError('repair_unconfirmed');
        await _client.repair(check.action!, report.fingerprint!);
        applied = true;
      }
    } catch (_) { /* Never expose native errors, command lines or credentials. */ }
    if (!mounted || generation != _generation) return;
    await _check();
    if (!mounted) return;
    setState(() { _message = applied
        ? windows ? 'Άνοιξαν οι ρυθμίσεις. Μετά τις ενέργειές σας πατήστε επανέλεγχο.'
            : _report == null ? 'Η ενέργεια επιβεβαιώθηκε, αλλά ο επανέλεγχος δεν ολοκληρώθηκε. Πατήστε επανέλεγχο.'
            : 'Η ενέργεια επιβεβαιώθηκε και έγινε νέος έλεγχος.'
        : 'Η ενέργεια δεν επιβεβαιώθηκε ή ακυρώθηκε. Ελέγξτε τη νέα κατάσταση πριν την επαναλάβετε.'; });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    const stateNames = {'ok':'OK', 'blocked':'Απαιτείται ενέργεια', 'pending':'Αναμονή',
      'unsupported':'Δεν υποστηρίζεται', 'unknown':'Δεν επιβεβαιώθηκε'};
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Έλεγχος αυτόματων ενημερώσεων', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('Η εγκατάσταση και η ετοιμότητα μελλοντικών ενημερώσεων ελέγχονται ξεχωριστά. Η κατάσταση μπορεί να αλλάξει.'),
        if (_busy) const LinearProgressIndicator(),
        if (report != null) ...[
          Text(report.ready ? 'Έτοιμος για αυτόματες ενημερώσεις'
              : report.unsupported ? 'Η αυτόματη διαδικασία δεν υποστηρίζεται σε αυτή την εγκατάσταση'
              : report.hasLocalBlockers ? 'Υπάρχουν τοπικά εμπόδια' : 'Η πλήρης ετοιμότητα δεν έχει επιβεβαιωθεί'),
          for (final check in report.checks) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text('${stateNames[check.status]} · ${installReadinessLabels[check.code] ?? 'Απαιτείται έλεγχος από τεχνικό'}'),
              if (check.action != null && (check.action == 'windows_update' || report.fingerprint != null))
                TextButton(onPressed: _busy ? null : () => _repair(check), child: Text(
                  check.action == 'windows_update' ? 'Άνοιγμα Windows Update'
                  : check.action == 'start_service' ? 'Εκκίνηση υπηρεσίας' : 'Αυτόματη εκκίνηση υπηρεσίας')),
            ])),
          if (report.installedVersion != null) Text('Εγκατεστημένη έκδοση: ${report.installedVersion}'),
          if (report.targetVersion != null) Text('Διαθέσιμη υπογεγραμμένη έκδοση: ${report.targetVersion}'),
          for (final reason in report.officeReasons) Text(installReadinessLabels[reason] ?? 'Το Office δεν επιβεβαίωσε την ετοιμότητα'),
          Text('Έλεγχος (τοπική ώρα υπολογιστή): ${report.checkedAt.toLocal()}'),
        ],
        if (_message != null) Text(_message!, semanticsLabel: _message),
        TextButton(onPressed: _busy ? null : _check, child: const Text('Επανέλεγχος')),
      ],
    )));
  }
}

Future<void> showInstalledReadiness(BuildContext context, String target) => showDialog<void>(
  context: context, barrierDismissible: false, builder: (context) => AlertDialog(
    title: const Text('Η εγκατάσταση ολοκληρώθηκε — έλεγχος ενημερώσεων'),
    content: SizedBox(width: 620, child: SingleChildScrollView(child: InstallReadinessPanel(target: target, autoRefresh: true))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Κλείσιμο'))],
  ),
);
