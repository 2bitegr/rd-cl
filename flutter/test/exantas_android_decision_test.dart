import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_session_decision.dart';
void main() {
  for (final action in ['Συνέχεια', 'Κλείσιμο', 'Χωρίς χρέωση', 'Κανονική χρέωση', 'Εξαίρεση']) {
    testWidgets('Greek mobile decision: $action retains explicit intent', (tester) async {
      tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final note = TextEditingController(); addTearDown(note.dispose);
      String? result = 'not-closed';
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async { result = await showDialog<String>(context: context,
          builder: (_) => ExantasSessionDecisionDialog(peerId: '123456789', note: note)); }, child: const Text('open'))))));
      await tester.tap(find.text('open')); await tester.pumpAndSettle();
      for (final label in ['Κανονική χρέωση', 'Χωρίς χρέωση', 'Αργότερα', 'Εξαίρεση']) { expect(find.text(label), findsOneWidget); }
      expect(tester.widget<RadioListTile<String>>(find.byType(RadioListTile<String>).first).groupValue, 'later');
      if (!['Συνέχεια', 'Κλείσιμο'].contains(action)) { await tester.tap(find.text(action)); await tester.pump(); }
      await tester.tap(find.text(action == 'Κλείσιμο' ? action : 'Συνέχεια')); await tester.pumpAndSettle();
      expect(result, {'Συνέχεια':'later', 'Κλείσιμο':null, 'Χωρίς χρέωση':'free', 'Κανονική χρέωση':'automatic', 'Εξαίρεση':'ignore'}[action]);
      expect(tester.takeException(), isNull);
    });
  }
}
