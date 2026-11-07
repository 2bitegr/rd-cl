import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_connect.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_connect_sheet.dart';

Map<String, dynamic> ctx({bool edit = true, String state = 'draft', String peer = 'pc1', bool can = true, String customer = 'c1'}) => {
      'item': {'id': 'w1', 'revision': '7', 'support_state': state, 'customer_id': customer},
      'permissions': {'can_edit': edit},
      'devices': [{'peer_id': peer, 'can_connect': can}],
    };

void main() {
  group('evaluateWorkConnect', () {
    ConnectCheck run(Map<String, dynamic> c, {String? customer}) => evaluateWorkConnect(c,
        peer: 'pc1', owner: 'u', api: 'a', expectedWorkId: 'w1', expectedCustomerId: customer);
    test('ok binds the fresh revision with owner/api/peer', () {
      final r = run(ctx(), customer: 'c1');
      expect(r.ok, true);
      expect(r.selection, {'peer_id': 'pc1', 'work_item_id': 'w1', 'revision': '7', 'owner': 'u', 'api': 'a'});
    });
    test('failures give a Greek reason and no selection', () {
      for (final c in [ctx(edit: false), ctx(state: 'finalized'), ctx(peer: 'other'), ctx(can: false)]) {
        final r = run(c);
        expect(r.ok, false);
        expect(r.reason, isNotEmpty);
      }
      expect(run(ctx(customer: 'c2'), customer: 'c1').ok, false);
      expect(evaluateWorkConnect(ctx(), peer: 'pc1', owner: 'u', api: 'a', expectedWorkId: 'zzz').ok, false);
    });
  });
  test('suggestions only for editable open work listing the peer as connectable', () {
    final ids = suggestWorkIds('pc1', [ctx(), ctx(edit: false), ctx(state: 'finalized'), ctx(can: false), ctx(peer: 'x')]);
    expect(ids, ['w1']);
  });
  test('single flight ignores a second call while busy', () async {
    final f = ExantasSingleFlight();
    var n = 0;
    final first = f.run(() async { n++; await Future<void>.delayed(const Duration(milliseconds: 10)); return 1; });
    final second = await f.run(() async { n++; return 2; });
    expect(second, isNull);
    expect(await first, 1);
    expect(n, 1);
    expect(await f.run(() async => 3), 3);
  });

  Future<void> pump(WidgetTester tester, void Function(ExantasConnectChoice?) done,
      {List<ExantasWorkOption> suggestions = const []}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: ExantasTheme.light(), home: Builder(
        builder: (c) => Scaffold(body: TextButton(onPressed: () async {
          done(await showExantasConnectSheet(c, peerId: '987654321',
              loadSuggestions: () async => suggestions,
              openWorks: const [ExantasWorkOption(id: 'w2', title: 'Άλλη', customerName: 'Πελ')]));
        }, child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet offers two explicit actions; suggestion is never auto-selected', (tester) async {
    var calls = 0;
    ExantasConnectChoice? choice;
    await pump(tester, (c) { calls++; choice = c; },
        suggestions: const [ExantasWorkOption(id: 'w1', title: 'Εργασία', customerName: 'Πελάτης')]);
    expect(find.text('Σύνδεση στο 987654321'), findsOneWidget);
    expect(find.text('Σύνδεση χωρίς εργασία'), findsOneWidget);
    expect(find.text('Επιλογή εργασίας'), findsOneWidget);
    expect(find.byKey(const ValueKey('connect-suggest-w1')), findsOneWidget);
    expect(find.text('Πρόταση'), findsOneWidget);
    expect(calls, 0); // nothing chosen until a tap
    await tester.tap(find.byKey(const ValueKey('connect-suggest-w1')));
    await tester.pumpAndSettle();
    expect(choice?.workId, 'w1');
  });
  testWidgets('dismissing the sheet connects nothing', (tester) async {
    ExantasConnectChoice? choice = const ExantasConnectChoice.withoutWork();
    await pump(tester, (c) => choice = c);
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(choice, isNull);
  });
  testWidgets('without work returns workId null once even on double tap', (tester) async {
    var calls = 0;
    ExantasConnectChoice? choice;
    await pump(tester, (c) { calls++; choice = c; });
    final b = find.byKey(const ValueKey('connect-no-work'));
    await tester.tap(b);
    await tester.tap(b, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(choice, isNotNull);
    expect(choice!.workId, isNull);
  });
  testWidgets('Επιλογή εργασίας lists open work and requires a tap', (tester) async {
    ExantasConnectChoice? choice;
    await pump(tester, (c) => choice = c);
    await tester.tap(find.byKey(const ValueKey('connect-pick-work')));
    await tester.pumpAndSettle();
    expect(choice, isNull);
    await tester.tap(find.byKey(const ValueKey('connect-work-w2')));
    await tester.pumpAndSettle();
    expect(choice?.workId, 'w2');
  });
}
