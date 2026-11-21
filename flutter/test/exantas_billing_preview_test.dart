import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_billing_preview.dart';

Map<String, dynamic> reviewed({bool can = true, int sessions = 1, Map<String, dynamic>? extra}) => {
      'preview': {
        'billing_mode': 'automatic', 'can_finalize': can, 'revision': '3', 'preview_hash': 'h',
        'connection_seconds': 1500, 'declared_minutes': 30, 'billable_minutes': 30,
        'net_minor': '3333', 'vat_minor': '800', 'gross_minor': '4133',
        'warnings': can ? [] : ['policy_not_configured'],
        'work_time_summary': {'elapsed_seconds': 1620, 'technician_work_seconds': 1620, 'technician_count': 1},
        'billing_explanation': ['Η χρέωση υπολογίστηκε από το Office.'],
        ...?extra,
      },
      'context': {'customer_name': 'Πελάτης Α', 'title': 'Εργασία Β', 'sessions': [
        for (var i = 0; i < sessions; i++) {'id': 's$i', 'peer_id': '12345', 'started_at': '2026-10-30T10:00:00Z'}]},
    };

Future<bool?> show(WidgetTester tester, Map<String, dynamic> r) async {
  bool? result;
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ExantasTheme.light(), home: Builder(
      builder: (c) => Scaffold(body: TextButton(onPressed: () async {
        result = await Navigator.of(c).push<bool>(MaterialPageRoute(builder: (_) => ExantasBillingPreviewPage(reviewed: r)));
      }, child: const Text('go'))))));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('renders only server fields; formats minor units without arithmetic', (tester) async {
    await show(tester, reviewed());
    expect(find.text('Πελάτης Α'), findsOneWidget);
    expect(find.text('33,33 €'), findsOneWidget);
    expect(find.text('8,00 €'), findsOneWidget);
    expect(find.text('41,33 €'), findsOneWidget);
    expect(find.text('30 λ'), findsNWidgets(2)); // declared + billable
    expect(find.text('Πραγματικός χρόνος σύνδεσης'), findsOneWidget);
    expect(find.text('Επαληθευμένος χρόνος παρόχου'), findsOneWidget);
  });
  testWidgets('absent fields are not shown and null amounts are not invented', (tester) async {
    final r = reviewed();
    (r['preview'] as Map)..remove('declared_minutes')..remove('billable_minutes')..remove('work_time_summary')
      ..['net_minor'] = null..['vat_minor'] = null..['gross_minor'] = null;
    await show(tester, r);
    expect(find.text('Δηλωμένος χρόνος'), findsNothing);
    expect(find.text('Χρεώσιμος χρόνος'), findsNothing);
    expect(find.text('Επαληθευμένος χρόνος παρόχου'), findsNothing);
    expect(find.text('Εκκρεμεί υπολογισμός Office'), findsNWidgets(3));
  });
  testWidgets('Ολοκλήρωση needs the explicit checkbox', (tester) async {
    await show(tester, reviewed());
    final btn = find.byKey(const ValueKey('preview-finalize'));
    await tester.ensureVisible(btn);
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('preview-confirm-check')));
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.byType(ExantasBillingPreviewPage), findsNothing);
  });
  testWidgets('can_finalize=false disables checkbox and button, shows warning', (tester) async {
    await show(tester, reviewed(can: false));
    final check = find.byKey(const ValueKey('preview-confirm-check'));
    await tester.ensureVisible(check);
    expect(tester.widget<CheckboxListTile>(check).onChanged, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('preview-finalize'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('preview-blocked')), findsOneWidget);
    expect(find.text('Δεν έχει οριστεί πολιτική χρέωσης.'), findsOneWidget);
  });
  testWidgets('multiple sessions warn that the whole work finalizes', (tester) async {
    await show(tester, reviewed(sessions: 3));
    expect(find.byKey(const ValueKey('preview-multi-session')), findsOneWidget);
    expect(find.textContaining('3 συνεδρίες'), findsWidgets);
  });
}
