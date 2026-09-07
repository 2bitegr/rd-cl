import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/exantas_report_outbox.dart';

class ExantasSessionsPage extends StatefulWidget {
  const ExantasSessionsPage({super.key});
  @override
  State<ExantasSessionsPage> createState() => _ExantasSessionsPageState();
}

class _ExantasSessionsPageState extends State<ExantasSessionsPage> {
  final _outbox = ExantasReportOutbox.instance;
  List<Map<String, dynamic>> _rows = [];
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh({bool sync = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (sync) await _outbox.sync();
      final rows = await _outbox.rows();
      if (mounted) setState(() { _rows = rows; _error = _outbox.syncError; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Δεν ήταν δυνατή η ανάγνωση των τοπικών αναφορών.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  String _state(Map<String, dynamic> row) {
    if (row['error'] != null) return row['error'];
    switch (row['state']) {
      case 'active': return 'Σε εξέλιξη / αναμονή επιβεβαίωσης λήξης';
      case 'draft': return 'Εκκρεμεί αναφορά';
      case 'queued': return 'Αποθηκεύτηκε τοπικά — αναμονή συγχρονισμού';
      case 'synced': return 'Συγχρονίστηκε';
      default: return 'Άγνωστη κατάσταση';
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Συνεδρίες υποστήριξης', style: TextStyle(fontSize: 22)),
      const SizedBox(height: 12),
      const Text('Συνεδρίες που καταγράφηκαν από αυτό το Companion για τον συνδεδεμένο τεχνικό.'),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: _busy ? null : () => _refresh(sync: true),
        child: const Text('Ανανέωση και συγχρονισμός')),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: _rows.isEmpty
        ? const Center(child: Text('Δεν υπάρχουν τοπικές συνεδρίες για αυτόν τον λογαριασμό.'))
        : SingleChildScrollView(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Έναρξη / διάρκεια')),
            DataColumn(label: Text('Πελάτης / υπολογιστής')),
            DataColumn(label: Text('Συνεδρία στο Office')),
            DataColumn(label: Text('Αναφορά')),
            DataColumn(label: Text('Ενέργεια')),
          ], rows: _rows.take(100).map((row) => DataRow(cells: [
            DataCell(Text('${DateTime.tryParse(row['started_at'] ?? '')?.toLocal().toString().split('.').first ?? '-'}\n${row['duration_seconds'] ?? 0} δευτερόλεπτα')),
            DataCell(Text('${row['customer_name'] ?? 'Αναμονή αντιστοίχισης πελάτη'}\n${row['peer_name'] ?? ''} (${row['peer_id']})')),
            DataCell(Text(row['remote_id'] == null ? 'Αναμονή συγχρονισμού' : 'Συγχρονίστηκε')),
            DataCell(SizedBox(width: 220, child: Text(_state(row)))),
            DataCell(row['state'] == 'draft'
              ? TextButton(onPressed: () async {
                  await _outbox.openReport?.call(row);
                  await _refresh();
                }, child: const Text('Καταγραφή αναφοράς'))
              : TextButton(onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Αποθηκευμένη αναφορά'),
                    content: SelectableText(row['note'] ?? 'Δεν έχει αποθηκευτεί σχόλιο.'),
                    actions: [TextButton(onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Κλείσιμο'))],
                  )), child: const Text('Προβολή'))),
          ])).toList()),
        ))),
    ]),
  );
}
