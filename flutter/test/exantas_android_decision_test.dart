import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_session_decision.dart';

Future<void> open(WidgetTester tester, TextEditingController note,
    void Function(String?) done) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: ExantasTheme.light(),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    done(await showExantasDecisionSheet(context,
                        peerId: '123456789', note: note));
                  },
                  child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const expected = {
    'decision-tile-automatic': 'automatic',
    'decision-tile-free': 'free',
    'decision-tile-later': 'later',
    'decision-tile-ignore': 'ignore',
  };
  testWidgets('default is Αργότερα (Προεπιλογή); Αποθήκευση returns later',
      (tester) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    String? result = 'not-closed';
    await open(tester, note, (v) => result = v);
    for (final label in ['Κανονική χρέωση', 'Χωρίς χρέωση', 'Αργότερα', 'Εξαίρεση']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Προεπιλογή'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('decision-save')));
    await tester.pumpAndSettle();
    expect(result, 'later');
    expect(tester.takeException(), isNull);
  });
  for (final e in expected.entries) {
    testWidgets('tile ${e.key} + Αποθήκευση returns ${e.value}', (tester) async {
      final note = TextEditingController();
      addTearDown(note.dispose);
      String? result = 'not-closed';
      await open(tester, note, (v) => result = v);
      await tester.tap(find.byKey(ValueKey(e.key)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('decision-save')));
      await tester.pumpAndSettle();
      expect(result, e.value);
    });
  }
  testWidgets('Κλείσιμο χωρίς απόφαση and swipe-dismiss return null (no call)',
      (tester) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    String? result = 'not-closed';
    await open(tester, note, (v) => result = v);
    await tester.tap(find.byKey(const ValueKey('decision-tile-free')));
    await tester.tap(find.byKey(const ValueKey('decision-close')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    result = 'not-closed';
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 20)); // barrier
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
  testWidgets('double tap on Αποθήκευση pops once', (tester) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    var calls = 0;
    await open(tester, note, (_) => calls++);
    final save = find.byKey(const ValueKey('decision-save'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('session-saved snackbar is non-blocking and offers Απόφαση τώρα',
      (tester) async {
    var decided = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(exantasSessionSavedSnackBar(onDecide: () => decided++)),
                    child: const Text('go'))))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Η συνεδρία αποθηκεύτηκε στα Εκκρεμή'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(decided, 0);
    await tester.tap(find.text('Απόφαση τώρα'));
    expect(decided, 1);
  });
}
