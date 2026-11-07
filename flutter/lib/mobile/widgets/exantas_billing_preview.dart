import 'package:flutter/material.dart';
import '../../models/exantas_office_work.dart' show formatAthens, formatDurationSeconds;
import '../ui/ex_card.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_theme.dart';

/// Minor units (e.g. "3333") as euros without any floating point or pricing.
String? formatMinor(dynamic minor) {
  if (minor == null) return null;
  final v = BigInt.tryParse('$minor');
  if (v == null) return null;
  final abs = v.abs(), cents = abs % BigInt.from(100);
  return '${v.isNegative ? '-' : ''}${abs ~/ BigInt.from(100)},${cents.toString().padLeft(2, '0')} €';
}

const _warningText = {
  'automatic_time_not_verified': 'Ο χρόνος δεν έχει επαληθευτεί από τον πάροχο.',
  'session_end_unconfirmed': 'Η λήξη συνεδρίας δεν έχει επιβεβαιωθεί.',
  'session_operator_unconfirmed': 'Ο τεχνικός της συνεδρίας δεν έχει επιβεβαιωθεί.',
  'session_time_in_future': 'Ο χρόνος συνεδρίας βρίσκεται στο μέλλον.',
  'declared_time_in_future': 'Ο δηλωμένος χρόνος βρίσκεται στο μέλλον.',
  'declaration_interval_required': 'Απαιτείται διάστημα για τη δήλωση χρόνου.',
  'policy_not_configured': 'Δεν έχει οριστεί πολιτική χρέωσης.',
  'policy_version_crossing_requires_review': 'Η εργασία καλύπτει περισσότερες εκδόσεις πολιτικής.',
  'eur_account_not_initialized': 'Ο λογαριασμός EUR του πελάτη δεν έχει ενεργοποιηθεί.',
  'eur_basis_not_confirmed': 'Η βάση λογαριασμού EUR δεν έχει επιβεβαιωθεί.',
  'legal_identity_changed': 'Άλλαξαν τα νομικά στοιχεία του πελάτη.',
  'cross_work_time_overlap': 'Ο χρόνος επικαλύπτεται με άλλη εργασία.',
  'remote_work_evidence_required': 'Απαιτούνται στοιχεία απομακρυσμένης εργασίας.',
};

/// Full-screen review of the Office preview. Every figure comes from the
/// preview/context Office returned; absent fields are not shown and nothing is
/// computed. Pops `true` only after the explicit checkbox and «Ολοκλήρωση».
class ExantasBillingPreviewPage extends StatefulWidget {
  const ExantasBillingPreviewPage(
      {super.key, required this.reviewed, this.title = 'Προεπισκόπηση Office'});
  final Map<String, dynamic> reviewed;
  final String title;
  @override
  State<ExantasBillingPreviewPage> createState() => _PreviewState();
}

class _PreviewState extends State<ExantasBillingPreviewPage> {
  bool confirmed = false, done = false;

  Map<String, dynamic> get preview =>
      Map<String, dynamic>.from(widget.reviewed['preview'] as Map);
  Map<String, dynamic> get context_ => widget.reviewed['context'] is Map
      ? Map<String, dynamic>.from(widget.reviewed['context'] as Map)
      : <String, dynamic>{};

  Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: Text(k)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]));

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final p = preview;
    final can = p['can_finalize'] == true;
    final mode = p['billing_mode'];
    final sessions = (context_['sessions'] as List? ?? []).whereType<Map>().toList();
    final warnings = (p['warnings'] as List? ?? []).map((w) => '$w').toList();
    final summary = p['work_time_summary'] is Map ? p['work_time_summary'] as Map : const {};
    final rows = <Widget>[
      if (p['connection_seconds'] != null)
        kv('Πραγματικός χρόνος σύνδεσης', formatDurationSeconds(num.tryParse('${p['connection_seconds']}') ?? 0)),
      if (summary['elapsed_seconds'] != null)
        kv('Επαληθευμένος χρόνος παρόχου', formatDurationSeconds(num.tryParse('${summary['elapsed_seconds']}') ?? 0)),
      if (summary['technician_work_seconds'] != null && summary['technician_count'] != null && summary['technician_count'] > 1)
        kv('Χρόνος τεχνικών', formatDurationSeconds(num.tryParse('${summary['technician_work_seconds']}') ?? 0)),
      if (p['declared_minutes'] != null) kv('Δηλωμένος χρόνος', '${p['declared_minutes']} λ'),
      if (p['billable_minutes'] != null) kv('Χρεώσιμος χρόνος', '${p['billable_minutes']} λ'),
    ];
    final money = <Widget>[
      if (mode != 'ignore' && mode != 'free') ...[
        kv('Καθαρό', formatMinor(p['net_minor']) ?? 'Εκκρεμεί υπολογισμός Office'),
        kv('ΦΠΑ', formatMinor(p['vat_minor']) ?? 'Εκκρεμεί υπολογισμός Office'),
        kv('Σύνολο', formatMinor(p['gross_minor']) ?? 'Εκκρεμεί υπολογισμός Office'),
      ] else
        Text(mode == 'free' ? 'Χωρίς χρέωση.' : 'Εξαίρεση: δεν δημιουργείται χρέωση.'),
    ];
    return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              ExCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (context_['customer_name'] != null) Text('${context_['customer_name']}', style: text.titleMedium),
                if (context_['title'] != null) Text('${context_['title']}', style: text.bodyMedium),
                if (p['contact_name'] != null) Text('Επαφή: ${p['contact_name']}', style: text.bodySmall),
                if (p['body'] != null && '${p['body']}'.isNotEmpty) ...[
                  const SizedBox(height: ExantasTokens.space2),
                  Text('${p['body']}', style: text.bodySmall),
                ],
              ])),
              const SizedBox(height: ExantasTokens.space3),
              ExCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Συνδεδεμένες συνεδρίες (${sessions.length})', style: text.titleSmall),
                for (final s in sessions)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text([
                        '${s['peer_id'] ?? ''}',
                        formatAthens(DateTime.tryParse('${s['started_at'] ?? ''}')),
                        if (s['technician_name'] != null) '${s['technician_name']}',
                      ].join(' · '), style: text.bodySmall)),
                if (sessions.length > 1)
                  Padding(
                      padding: const EdgeInsets.only(top: ExantasTokens.space2),
                      child: Text('Η εργασία έχει ${sessions.length} συνεδρίες. Ολοκληρώνεται ολόκληρη η εργασία, όχι μόνο η τελευταία.',
                          key: const ValueKey('preview-multi-session'), style: text.bodySmall?.copyWith(color: t.warning))),
              ])),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: ExantasTokens.space3),
                ExCard(child: Column(children: rows)),
              ],
              const SizedBox(height: ExantasTokens.space3),
              ExCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: money)),
              if (p['billing_explanation'] is List && (p['billing_explanation'] as List).isNotEmpty) ...[
                const SizedBox(height: ExantasTokens.space3),
                ExCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final line in (p['billing_explanation'] as List)) Text('$line', style: text.bodySmall),
                ])),
              ],
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: ExantasTokens.space3),
                ExCard(
                    key: const ValueKey('preview-warnings'),
                    color: t.warningSoft,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const ExStatusPill('Προειδοποιήσεις', status: ExStatus.warning),
                  for (final w in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_warningText[w] ?? w)),
                ])),
              ],
              if (!can) ...[
                const SizedBox(height: ExantasTokens.space3),
                Text('Απαιτείται έλεγχος στο Office. Η ολοκλήρωση δεν είναι διαθέσιμη από το κινητό.',
                    key: const ValueKey('preview-blocked'), style: TextStyle(color: t.danger)),
              ],
              const SizedBox(height: ExantasTokens.space3),
              Text('Δεν αποστέλλεται email.', style: text.bodySmall),
              CheckboxListTile(
                  key: const ValueKey('preview-confirm-check'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: confirmed,
                  onChanged: can ? (v) => setState(() => confirmed = v == true) : null,
                  title: const Text('Επιβεβαιώνω την ολοκλήρωση ολόκληρης της εργασίας')),
              FilledButton(
                  key: const ValueKey('preview-finalize'),
                  onPressed: can && confirmed && !done
                      ? () {
                          if (done) return;
                          setState(() => done = true);
                          Navigator.pop(context, true);
                        }
                      : null,
                  child: const Text('Ολοκλήρωση')),
              TextButton(
                  key: const ValueKey('preview-cancel'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Άκυρο')),
            ])));
  }
}
