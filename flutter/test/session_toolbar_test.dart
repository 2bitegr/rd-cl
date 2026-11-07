import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/ex_session_toolbar.dart';
import 'package:flutter_hbb/mobile/ui/exantas_strings.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: ExantasTheme.light(), home: Scaffold(body: child));

void main() {
  group('back guard', () {
    testWidgets('Back asks, Παραμονή does not disconnect', (tester) async {
      var closed = 0;
      await tester.pumpWidget(_app(ExSessionBackGuard(
          peer: 'PC-1', onDisconnect: () => closed++, child: const Text('s'))));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Αποσύνδεση από PC-1;'), findsOneWidget);
      expect(closed, 0);
      await tester.tap(find.text(ExStrings.stay));
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(find.text('Αποσύνδεση από PC-1;'), findsNothing);
      expect(find.text('s'), findsOneWidget);
    });

    testWidgets('Αποσύνδεση calls close callback', (tester) async {
      var closed = 0;
      await tester.pumpWidget(_app(ExSessionBackGuard(
          peer: 'PC-1', onDisconnect: () => closed++, child: const Text('s'))));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ex-disconnect-confirm')));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });
  });

  group('toolbar', () {
    final labels = [
      ExStrings.keyboard,
      ExStrings.mouseMode,
      ExStrings.screens,
      ExStrings.chat,
      ExStrings.more,
      ExStrings.disconnect,
      ExStrings.hideToolbar,
    ];
    for (final w in [320.0, 390.0]) {
      testWidgets('renders all actions with semantics at $w', (tester) async {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final taps = <String>[];
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_app(Align(
            alignment: Alignment.bottomCenter,
            child: ExSessionToolbar(actions: [
              for (final l in labels)
                ExSessionAction(
                    id: l,
                    label: l,
                    icon: Icons.circle_outlined,
                    danger: l == ExStrings.disconnect,
                    onPressed: () => taps.add(l)),
            ]))));
        expect(tester.takeException(), isNull);
        for (final l in labels) {
          expect(find.bySemanticsLabel(l), findsOneWidget, reason: l);
        }
        final btn = tester.getSize(
            find.byKey(ValueKey('ex-session-action-${labels.first}')));
        expect(btn.width >= 48 && btn.height >= 48, isTrue);
        await tester.tap(find.byKey(ValueKey('ex-session-action-${labels.first}')));
        expect(taps, [labels.first]);
        handle.dispose();
      });
    }
  });

  testWidgets('context chip hidden by default, shows when set', (tester) async {
    final n = ValueNotifier<String?>(null);
    await tester.pumpWidget(_app(ExSessionContextChip(listenable: n)));
    expect(find.byKey(const ValueKey('ex-session-chip')), findsNothing);
    n.value = ExSessionContext.format('Πελάτης', 'Υπολογιστής');
    await tester.pump();
    expect(find.text('Πελάτης · Υπολογιστής'), findsOneWidget);
  });
}
