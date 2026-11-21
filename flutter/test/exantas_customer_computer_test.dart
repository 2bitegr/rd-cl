import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_device_display.dart';
import 'package:flutter_hbb/desktop/widgets/exantas_customer_computer.dart';

void main() {
  testWidgets(
      'customer company and computer remain separate and wrap in a narrow sidebar',
      (tester) async {
    const company =
        'ΔΟΚΙΜΑΣΤΙΚΗ ΕΤΑΙΡΕΙΑ ΕΣΤΙΑΣΗΣ ΚΑΙ ΔΙΑΧΕΙΡΙΣΗΣ ΚΑΤΑΣΤΗΜΑΤΩΝ ΑΕ';
    const computer = 'Κεντρικό ταμείο καταστήματος - POS-01';
    const computerDisplay = '$computer · 123456789';
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 145,
                child: ExantasCustomerComputer(
                    compact: true,
                    display: ExantasDeviceDisplay(
                        companyName: company,
                        computerName: computer,
                        peerId: '123456789'))))));
    expect(find.text('Πελάτης'), findsOneWidget);
    expect(find.text(company), findsOneWidget);
    expect(find.text('Υπολογιστής'), findsOneWidget);
    expect(find.text(computerDisplay), findsOneWidget);
    final first = tester.getRect(find.text(company)),
        second = tester.getRect(find.text(computerDisplay));
    expect(first.right, lessThanOrEqualTo(145));
    expect(first.height, greaterThan(20));
    expect(second.top, greaterThan(first.bottom));
    expect(second.right, lessThanOrEqualTo(145));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'unverified metadata and an unnamed computer have distinct honest states',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ExantasCustomerComputer(display: null)));
    expect(find.text('Στοιχεία πελάτη και υπολογιστή μη διαθέσιμα.'),
        findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
        home: ExantasCustomerComputer(
            display: ExantasDeviceDisplay(
                companyName: 'Synthetic Company', computerName: ''))));
    expect(find.text('Synthetic Company'), findsOneWidget);
    expect(find.text('Δεν έχει οριστεί όνομα υπολογιστή.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
