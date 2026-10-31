import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/exantas_account_settings.dart';

class FakeAccount {
  bool signedIn = false;
  bool legacy = false;
  bool ready = false;
  bool? recoveryRequired;
  bool failLoad = false;
  bool failLogout = false;
  bool failLegacy = false;
  bool failConfirm = false;
  bool partialLogin = false;
  int logins = 0;
  int confirmations = 0;
  Completer<void>? loginGate;
  String? email;

  Future<ExantasAccountStatus> load() async {
    if (failLoad) throw StateError('synthetic storage failure');
    return ExantasAccountStatus(signedIn: signedIn, name: 'Synthetic technician',
        role: 'technician', nativeReady: ready, legacySignedIn: legacy,
        nativeRecoveryRequired: recoveryRequired);
  }

  Future<void> login(String email, String password) async {
    logins++;
    this.email = email;
    if (loginGate != null) await loginGate!.future;
    signedIn = true;
    if (partialLogin) throw StateError('HTTP 502; native sign-in unconfirmed');
    ready = true;
  }

  Future<void> logout() async {
    if (failLogout) throw StateError('Office revocation not confirmed');
    signedIn = false;
    ready = false;
  }

  Future<void> confirm() async {
    confirmations++;
    if (failConfirm) throw StateError('native sign-in unconfirmed');
    if (recoveryRequired != null) recoveryRequired = false;
    ready = true;
  }

  Future<void> logoutLegacy() async {
    if (failLegacy) throw StateError('Legacy revocation not confirmed');
    legacy = false;
  }
}

Future<void> showAccount(WidgetTester tester, FakeAccount account) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: ExantasAccountSettings(loadStatus: account.load, login: account.login,
      logout: account.logout, confirmNative: account.confirm,
      logoutLegacy: account.logoutLegacy, nativeRequired: true),
  ))));
  await tester.pumpAndSettle();
}

Future<void> closeAccount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'synthetic@office.invalid');
  await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
}

void main() {
  testWidgets('one Office form; pending login prevents duplicate submissions', (tester) async {
    final account = FakeAccount()..loginGate = Completer<void>();
    await showAccount(tester, account);
    expect(find.text('Email Office'), findsOneWidget);
    await enterCredentials(tester);
    await tester.tap(find.text('Σύνδεση'));
    await tester.pump();
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(account.logins, 1);
    account.loginGate!.complete();
    await tester.pumpAndSettle();
    expect(account.email, 'synthetic@office.invalid');
    expect(find.text('Synthetic technician'), findsOneWidget);
    expect(find.text('RustDesk: έτοιμο για σύνδεση'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await closeAccount(tester);
  });

  testWidgets('empty credentials never reach the login service', (tester) async {
    final account = FakeAccount();
    await showAccount(tester, account);
    await tester.tap(find.text('Σύνδεση'));
    await tester.pumpAndSettle();
    expect(account.logins, 0);
    expect(find.textContaining('Συμπληρώστε email'), findsOneWidget);
    await closeAccount(tester);
  });

  testWidgets('partial login shows paired identity and explicit confirmation without retry', (tester) async {
    final account = FakeAccount()..partialLogin = true;
    await showAccount(tester, account);
    await enterCredentials(tester);
    await tester.tap(find.text('Σύνδεση'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic technician'), findsOneWidget);
    expect(find.textContaining('HTTP 502'), findsOneWidget);
    expect(find.text('Επιβεβαίωση σύνδεσης'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(account.logins, 1);
    expect(account.confirmations, 0);
    account.failConfirm = true;
    await tester.tap(find.text('Επιβεβαίωση σύνδεσης'));
    await tester.pumpAndSettle();
    expect(account.confirmations, 1);
    expect(find.text('RustDesk: έτοιμο για σύνδεση'), findsNothing);
    await closeAccount(tester);
  });

  testWidgets('unconfirmed Office logout retains identity and failure message', (tester) async {
    final account = FakeAccount()..signedIn = true..ready = true..failLogout = true;
    await showAccount(tester, account);
    await tester.tap(find.text('Αποσύνδεση από το Office'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic technician'), findsOneWidget);
    expect(find.text('Office revocation not confirmed'), findsOneWidget);
    account.failLogout = false;
    await tester.tap(find.text('Αποσύνδεση από το Office'));
    await tester.pumpAndSettle();
    expect(find.text('Email Office'), findsOneWidget);
    await closeAccount(tester);
  });

  testWidgets('legacy identity blocks Office form until confirmed logout', (tester) async {
    final account = FakeAccount()..legacy = true..failLegacy = true;
    await showAccount(tester, account);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Αποσύνδεση παλιού λογαριασμού RustDesk'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Legacy revocation not confirmed'), findsOneWidget);
    account.failLegacy = false;
    await tester.tap(find.text('Αποσύνδεση παλιού λογαριασμού RustDesk'));
    await tester.pumpAndSettle();
    expect(find.text('Email Office'), findsOneWidget);
    expect(account.logins, 0);
    await closeAccount(tester);
  });

  testWidgets('unknown local identity fails closed; explicit refresh recovers', (tester) async {
    final account = FakeAccount()..failLoad = true;
    await showAccount(tester, account);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Επανάληψη ελέγχου'), findsOneWidget);
    account.failLoad = false;
    await tester.tap(find.text('Επανάληψη ελέγχου'));
    await tester.pumpAndSettle();
    expect(find.text('Email Office'), findsOneWidget);
    await closeAccount(tester);
  });
  testWidgets('Android lease expiry keeps Office identity without a second sign-in or retry button', (tester) async {
    final account = FakeAccount()..signedIn = true..ready = true..recoveryRequired = false;
    await showAccount(tester, account);
    account.ready = false; // Simulate the short native lease expiring.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic technician'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Επιβεβαίωση σύνδεσης'), findsNothing);
    expect(find.text('Επανάληψη σύνδεσης RustDesk'), findsNothing);
    expect(find.textContaining('αυτόματη ανανέωση'), findsOneWidget);
    expect(account.logins, 0);
    expect(account.confirmations, 0);
    await closeAccount(tester);
  });
  testWidgets('Android unconfirmed issuance exposes one explicit retry and clears it on success', (tester) async {
    final account = FakeAccount()..signedIn = true..recoveryRequired = true;
    await showAccount(tester, account);
    await tester.pump(const Duration(seconds: 6));
    expect(account.confirmations, 0);
    await tester.tap(find.text('Επανάληψη σύνδεσης RustDesk'));
    await tester.pumpAndSettle();
    expect(account.confirmations, 1);
    expect(find.text('Επανάληψη σύνδεσης RustDesk'), findsNothing);
    expect(find.text('RustDesk: έτοιμο για σύνδεση'), findsOneWidget);
    await closeAccount(tester);
  });

}
