import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/ex_card.dart';
import 'package:flutter_hbb/mobile/ui/ex_segmented.dart';
import 'package:flutter_hbb/mobile/ui/ex_session_toolbar.dart';
import 'package:flutter_hbb/mobile/ui/ex_status_pill.dart';
import 'package:flutter_hbb/mobile/ui/ex_list_row.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double scale, Widget child) => MaterialApp(
    theme: ExantasTheme.light(),
    builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!),
    home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('ExSessionContext.fromWorkContext', () {
    test('customer and device label', () {
      expect(
          ExSessionContext.fromWorkContext({
            'item': {'customer_name': 'Alpha ΕΠΕ'},
            'devices': [
              {'peer_id': '123', 'label': 'Γραφείο'},
              {'peer_id': '999', 'label': 'Άλλο'}
            ]
          }, '123'),
          'Alpha ΕΠΕ · Γραφείο');
    });
    test('falls back to customer.company_name and peer id', () {
      expect(
          ExSessionContext.fromWorkContext({
            'item': {},
            'customer': {'company_name': 'Beta'},
            'devices': [
              {'peer_id': '123'}
            ]
          }, '123'),
          'Beta · 123');
    });
    test('no customer: device only', () {
      expect(ExSessionContext.fromWorkContext({'item': {}}, '55'), '55');
    });
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('new Exantas widgets do not overflow at textScaler $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
          scale,
          Column(children: [
            ExCard(
                child: Row(children: [
              const Expanded(
                  child: Text('Πολύ μεγάλο όνομα πελάτη εταιρείας ΕΠΕ')),
              const ExStatusPill('Εκκρεμεί απόφαση',
                  status: ExStatus.warning),
            ])),
            const ExListRow(
                title: 'Υπολογιστής γραφείου λογιστηρίου',
                subtitle: 'RustDesk 123 456 789',
                icon: Icons.computer),
            ExSegmented<int>(segments: const [
              ExSegment(0, 'Σήμερα'),
              ExSegment(1, 'Ανοιχτές'),
              ExSegment(2, 'Πελάτες'),
              ExSegment(3, 'Εκκρεμή (12)'),
            ], selected: 0, onChanged: (_) {}),
            const ExDisconnectContent(peer: '123 456 789'),
          ])));
      final ex = tester.takeException();
      expect(ex, isNull, reason: '$ex');
    });
  }

  testWidgets('disconnect sheet never stacks; ExFixedTextScale pins 1.0',
      (tester) async {
    late BuildContext ctx;
    double? scale;
    await tester.pumpWidget(MaterialApp(
        theme: ExantasTheme.light(),
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(1.3)),
            child: w!),
        home: Builder(builder: (c) {
          ctx = c;
          return ExFixedTextScale(child: Builder(builder: (c2) {
            scale = MediaQuery.textScalerOf(c2).scale(10);
            return const SizedBox();
          }));
        })));
    expect(scale, 10);
    final first = showExDisconnectSheet(ctx, 'A');
    await tester.pumpAndSettle();
    final second = await showExDisconnectSheet(ctx, 'A');
    expect(second, false);
    await tester.pumpAndSettle();
    expect(find.byType(ExDisconnectContent), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ex-disconnect-confirm')));
    await tester.pumpAndSettle();
    expect(await first, true);
  });
}
