import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/exantas_identity_settings.dart';
import 'package:flutter_hbb/models/exantas_identity.dart';

class FakeIdentityActions implements ExantasIdentityActions {
  bool signedIn = false;
  bool accepted = true;
  int resets = 0;
  final access = const ExantasIdentityAccess(
      apiBase: 'https://office.invalid/api/v1',
      officeUserId: 'synthetic-technician',
      companionToken: 'synthetic-token',
      currentId: '1234567');
  @override
  Future<ExantasIdentityAccess?> authorizeIdentityReset() async =>
      signedIn && accepted ? access : null;
  @override
  Future<bool> identitySessionMatches(ExantasIdentityAccess access) async =>
      signedIn;
  @override
  Future<ExantasIdentityResult> regenerateIdentity(
      ExantasIdentityAccess access) async {
    resets++;
    signedIn = false;
    return const ExantasIdentityResult(
        success: true,
        code: 'id_generated',
        officeSignedOut: true,
        newId: '1456789012',
        backupPath: r'C:\synthetic\identity-backup.toml');
  }
}

Future<void> showSettings(WidgetTester tester, FakeIdentityActions actions,
    {bool unlocked = true,
    bool available = true,
    bool pendingReports = false,
    bool reportCheckFails = false}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 540,
                  child: ExantasIdentitySettings(
                      actions: actions,
                      unlocked: unlocked,
                      available: available,
                      hasPendingReports: () async {
                        if (reportCheckFails)
                          throw StateError('synthetic read failure');
                        return pendingReports;
                      },
                      cardBuilder: (child) => Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: child))))))));
  await tester.pumpAndSettle();
}

Future<void> closeSettings(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets(
      'guest and rejected Office sign-in have no ID maintenance control',
      (tester) async {
    final actions = FakeIdentityActions();
    await showSettings(tester, actions);
    expect(find.text('Δημιουργία νέου ID'), findsNothing);
    actions.signedIn = true;
    actions.accepted = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Δημιουργία νέου ID'), findsNothing);
    expect(actions.resets, 0);
    await closeSettings(tester);
  });
  testWidgets('verified staff sees current ID and local-target explanation',
      (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions);
    expect(find.text('1234567'), findsOneWidget);
    expect(find.text('Δημιουργία νέου ID'), findsOneWidget);
    expect(find.textContaining('αυτόν τον υπολογιστή'), findsOneWidget);
    actions.signedIn = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Δημιουργία νέου ID'), findsNothing);
    await closeSettings(tester);
  });
  testWidgets('locked security and unsupported platform cannot submit',
      (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions, unlocked: false);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Δημιουργία νέου ID'));
    expect(button.onPressed, isNull);
    expect(actions.resets, 0);
    await closeSettings(tester);
    await showSettings(tester, actions, available: false);
    expect(find.text('Δημιουργία νέου ID'), findsNothing);
    await closeSettings(tester);
  });
  testWidgets('cancelling confirmation never changes the ID', (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions);
    await tester.tap(find.text('Δημιουργία νέου ID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1234567.'), findsOneWidget);
    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();
    expect(actions.resets, 0);
    expect(find.text('1234567'), findsOneWidget);
    await closeSettings(tester);
  });
  testWidgets('unfinished local reports prevent any reset or logout',
      (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions, pendingReports: true);
    await tester.tap(find.text('Δημιουργία νέου ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Δημιουργία νέου ID')));
    await tester.pumpAndSettle();
    expect(actions.resets, 0);
    expect(actions.signedIn, isTrue);
    expect(find.textContaining('εκκρεμείς τοπικές αναφορές'), findsOneWidget);
    await closeSettings(tester);
  });
  testWidgets('unreadable report state cannot dispatch a native reset',
      (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions, reportCheckFails: true);
    await tester.tap(find.text('Δημιουργία νέου ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Δημιουργία νέου ID')));
    await tester.pumpAndSettle();
    expect(actions.resets, 0);
    expect(actions.signedIn, isTrue);
    expect(find.textContaining('Το ID δεν άλλαξε.'), findsOneWidget);
    await closeSettings(tester);
  });
  testWidgets('explicit confirmation submits once then requires fresh sign-in',
      (tester) async {
    final actions = FakeIdentityActions()..signedIn = true;
    await showSettings(tester, actions);
    await tester.tap(find.text('Δημιουργία νέου ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Δημιουργία νέου ID')));
    await tester.pumpAndSettle();
    expect(actions.resets, 1);
    expect(find.text('1456789012'), findsOneWidget);
    expect(find.textContaining('ιστορικό'), findsOneWidget);
    await tester.tap(find.text('Κλείσιμο'));
    await tester.pumpAndSettle();
    expect(find.text('Δημιουργία νέου ID'), findsNothing);
    await closeSettings(tester);
  });
}
