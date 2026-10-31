import 'package:flutter/material.dart';
import '../../models/exantas_device_enrollment.dart';

/// A customer needs a device code, never an Office staff login.
class ExantasDeviceEnrollment extends StatefulWidget {
  const ExantasDeviceEnrollment({super.key, required this.loadStatus,
    required this.preview, required this.enroll, required this.complete, this.initialCode, this.automatic = false});
  final String? initialCode;
  final bool automatic;
  final Future<ExantasDeviceEnrollmentStatus> Function() loadStatus;
  final Future<ExantasDeviceEnrollmentPreview> Function(String) preview;
  final Future<void> Function(ExantasDeviceEnrollmentPreview) enroll;
  final Future<void> Function() complete;
  @override
  State<ExantasDeviceEnrollment> createState() => _ExantasDeviceEnrollmentState();
}

class _ExantasDeviceEnrollmentState extends State<ExantasDeviceEnrollment> {
  final _code = TextEditingController();
  ExantasDeviceEnrollmentStatus? _status;
  ExantasDeviceEnrollmentPreview? _preview;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _code.text = widget.initialCode ?? '';
    _refresh().then((_) async {
      final status = _status;
      if (mounted && widget.automatic && status != null && status.enrolled && status.pending && !status.staffSignedIn) {
        await _run(widget.complete);
      } else if (mounted && widget.initialCode != null && status != null &&
          !status.enrolled && !status.staffSignedIn && !status.pending) {
        await _run(_previewAndActivate);
      }
    });
  }
  Future<void> _previewAndActivate() async {
    final preview = await widget.preview(_code.text);
    if (!mounted) return;
    setState(() => _preview = preview);
    if (widget.automatic) {
      if (!preview.automatic || preview.expectedPeerId == null) {
        throw const ExantasEnrollmentFailure('Η λήψη δεν υποστηρίζει αυτόματη ενεργοποίηση. Κάντε νέα λήψη από την επαφή στο Office.');
      }
      await widget.enroll(preview);
      if (mounted) { _code.clear(); setState(() => _preview = null); }
    }
  }
  @override
  void dispose() { _code.dispose(); super.dispose(); }
  Future<void> _refresh() async {
    try { final status = await widget.loadStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) { if (mounted) setState(() {
      _status = null;
      _error = 'Δεν ελέγχθηκε η υπάρχουσα σύνδεση. Δοκιμάστε ξανά.';
    }); }
  }
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); }
    catch (error) { if (mounted) setState(() {
      _error = error is ExantasEnrollmentFailure ? error.message : 'Η ενέργεια δεν ολοκληρώθηκε. Ελέγξτε τη σύνδεση και την κατάσταση παρακάτω.';
    }); }
    finally { await _refresh(); if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final status = _status;
    final blocked = status == null || status.staffSignedIn || status.enrolled || status.pending;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Σύνδεση υπολογιστή πελάτη', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(widget.automatic ? 'Αυτόματη ενεργοποίηση για τον πελάτη και τον υπολογιστή που επιλέχθηκαν στο Office.' : 'Για τον τεχνικό: ελέγξτε τον πελάτη πριν ολοκληρώσετε την εγκατάσταση. Δεν χρειάζεται σύνδεση με λογαριασμό Office.'),
      if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
      if (status?.enrolled == true) ...[
        const SizedBox(height: 12),
        Text('Πελάτης: ${status!.customerName}'),
        if (!status.pending) const Text('Ο υπολογιστής συνδέθηκε με την υποστήριξη.'),
      ],
      if (status?.pending == true) ...[
        const SizedBox(height: 12),
        Text(status!.enrolled
          ? 'Η σύνδεση καταχωρίστηκε. Εκκρεμεί η ολοκλήρωση των ρυθμίσεων πρόσβασης.'
          : 'Το αποτέλεσμα της σύνδεσης δεν επιβεβαιώθηκε. Επικοινωνήστε με την υποστήριξη· μην χρησιμοποιήσετε ξανά τον κωδικό.'),
        if (status.enrolled && !status.staffSignedIn)
          OutlinedButton(onPressed: _busy ? null : () => _run(widget.complete), child: const Text('Ολοκλήρωση ρυθμίσεων πρόσβασης')),
      ],
      if (status?.staffSignedIn == true)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Υπάρχει συνδεδεμένος τεχνικός. Αποσυνδεθείτε από το Office πριν χρησιμοποιήσετε κωδικό πελάτη.')),
      if (!blocked) ...[
        if (widget.initialCode == null) TextField(controller: _code, enabled: !_busy, autocorrect: false,
          enableSuggestions: false, decoration: const InputDecoration(labelText: 'Κωδικός εγκατάστασης'),
          onChanged: (_) => setState(() { _preview = null; })),
        OutlinedButton(onPressed: _busy ? null : () => _run(_previewAndActivate), child: Text(widget.initialCode == null ? 'Έλεγχος πελάτη' : 'Επανέλεγχος πελάτη')),
        if (_preview != null) ...[
          const SizedBox(height: 12),
          Text('Πελάτης: ${_preview!.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(_preview!.unattended
            ? 'Η υποστήριξη θα επιτρέπεται και χωρίς την παρουσία σας.'
            : 'Η υποστήριξη θα απαιτεί την αποδοχή σας στον υπολογιστή.'),
          if (!widget.automatic) ElevatedButton(onPressed: _busy ? null : () => _run(() async {
            await widget.enroll(_preview!);
            if (mounted) { _code.clear(); setState(() { _preview = null; }); }
          }), child: const Text('Ολοκλήρωση σύνδεσης στον πελάτη')),
        ],
      ],
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, semanticsLabel: 'Σφάλμα: $_error')),
      if (status == null || status.pending || status.staffSignedIn)
        TextButton(onPressed: _busy ? null : () => _run(() async {}), child: const Text('Επανέλεγχος κατάστασης')),
    ]);
  }
}
