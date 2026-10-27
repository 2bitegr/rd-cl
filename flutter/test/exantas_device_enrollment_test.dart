import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_device_enrollment.dart';
import 'package:flutter_hbb/desktop/widgets/exantas_device_enrollment.dart';

const code = 'EXA-000001-000002-000003';
const preview = ExantasDeviceEnrollmentPreview(code: code,
  enrollmentId: '11111111-1111-4111-8111-111111111111',
  customerId: '22222222-2222-4222-8222-222222222222',
  customerName: 'Synthetic customer', unattended: true);
class FakeDevice {
  bool enrolled = false, staff = false, pending = false, failPreview = false;
  bool unknownReply = false;
  int previews = 0, enrolls = 0, completions = 0;
  Future<ExantasDeviceEnrollmentStatus> load() async => ExantasDeviceEnrollmentStatus(
    enrolled: enrolled, staffSignedIn: staff, pending: pending,
    customerName: enrolled ? 'Synthetic customer' : '');
  Future<ExantasDeviceEnrollmentPreview> check(String raw) async {
    previews++;
    if (failPreview) throw const FormatException('synthetic unavailable');
    return preview;
  }
  Future<void> enroll(ExantasDeviceEnrollmentPreview value) async {
    expect(value.customerId, preview.customerId); enrolls++; pending = true;
    if (unknownReply) throw StateError('synthetic lost reply');
    enrolled = true; pending = false;
  }
  Future<void> complete() async { completions++; pending = false; }
}
Future<void> mount(WidgetTester tester, FakeDevice fake, {String? initialCode}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: ExantasDeviceEnrollment(initialCode: initialCode, loadStatus: fake.load, preview: fake.check,
      enroll: fake.enroll, complete: fake.complete),
  ))));
  await tester.pumpAndSettle();
}
Future<void> check(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.tap(find.text('Έλεγχος πελάτη')); await tester.pumpAndSettle();
}
void main() {
  test('installation URI accepts only the exact code namespace without origin/auth overrides', () {
    expect(enrollmentCodeFromLink(Uri.parse('exantas-support-enroll://install?code=$code')), code);
    for (final link in ['rustdesk://install?code=$code', 'exantas-support-enroll://other?code=$code',
      'exantas-support-enroll://install?code=bad', 'exantas-support-enroll://install?code=$code&code=$code',
      'exantas-support-enroll://install?code=$code&api=https://other.test', 'exantas-support-enroll://install/path?code=$code']) {
      expect(enrollmentCodeFromLink(Uri.parse(link)), isNull);
    }
  });
  testWidgets('browser link previews its customer without typing and never auto-enrolls', (tester) async {
    final fake=FakeDevice();await mount(tester,fake,initialCode:code);
    expect(find.byType(TextField),findsNothing);expect(fake.previews,1);expect(fake.enrolls,0);
    expect(find.text('Πελάτης: Synthetic customer'),findsOneWidget);
    final connect=find.text('Ολοκλήρωση σύνδεσης στον πελάτη');await tester.ensureVisible(connect);
    await tester.tap(connect);await tester.pumpAndSettle();expect(fake.enrolls,1);
  });

  test('preview validates exact customer identity and access contract', () {
    final data = {'status':'ok','contract_version':1,'installation':{
      'enrollment_id':preview.enrollmentId,'customer_id':preview.customerId,
      'customer_name':preview.customerName,'unattended_enabled':true}};
    expect(ExantasDeviceEnrollmentPreview.parse(' $code ', data).customerId, preview.customerId);
    expect(() => ExantasDeviceEnrollmentPreview.parse(code, {...data,'contract_version':2}), throwsFormatException);
    expect(() => ExantasDeviceEnrollmentPreview.parse('bad-code', data), throwsFormatException);
  });
  testWidgets('technician previews exact customer/access before the only enrollment', (tester) async {
    final fake = FakeDevice(); await mount(tester, fake);
    expect(find.text('Email Office'), findsNothing); expect(fake.enrolls,0);
    await check(tester); expect(find.text('Πελάτης: Synthetic customer'),findsOneWidget);
    final connect = find.widgetWithText(ElevatedButton,'Ολοκλήρωση σύνδεσης στον πελάτη');
    expect(tester.widget<ElevatedButton>(connect).onPressed,isNotNull); expect(fake.previews,1); expect(fake.enrolls,0);
    expect(find.byType(CheckboxListTile),findsNothing);
    await tester.ensureVisible(connect); await tester.tap(connect); await tester.pumpAndSettle();
    expect(fake.enrolls,1); expect(find.byType(TextField),findsNothing);
    expect(find.text('Ο υπολογιστής συνδέθηκε με την υποστήριξη.'),findsOneWidget);
  });
  testWidgets('staff and existing managed computers cannot be enrolled over another identity', (tester) async {
    final fake = FakeDevice()..staff=true; await mount(tester,fake);
    expect(find.byType(TextField),findsNothing);expect(fake.enrolls,0);
    fake.staff=false;fake.enrolled=true;await tester.pumpWidget(const SizedBox.shrink());await mount(tester,fake);
    expect(find.byType(TextField),findsNothing);expect(find.text('Πελάτης: Synthetic customer'),findsOneWidget);
  });
  testWidgets('unknown enrollment remains blocked across status recheck and remount', (tester) async {
    final fake = FakeDevice()..unknownReply=true;await mount(tester,fake);await check(tester);
    final connect=find.text('Ολοκλήρωση σύνδεσης στον πελάτη');await tester.ensureVisible(connect);await tester.tap(connect);await tester.pumpAndSettle();
    expect(fake.enrolls,1);expect(find.byType(TextField),findsNothing);
    await tester.tap(find.text('Επανέλεγχος κατάστασης'));await tester.pumpAndSettle();expect(fake.enrolls,1);
    await tester.pumpWidget(const SizedBox.shrink());await mount(tester,fake);expect(find.byType(TextField),findsNothing);expect(fake.enrolls,1);
  });
  testWidgets('credential setup resumes the existing grant without another enrollment', (tester) async {
    final fake=FakeDevice()..enrolled=true..pending=true;await mount(tester,fake);
    await tester.tap(find.text('Ολοκλήρωση ρυθμίσεων πρόσβασης'));await tester.pumpAndSettle();
    expect(fake.enrolls,0);expect(fake.completions,1);expect(find.text('Ο υπολογιστής συνδέθηκε με την υποστήριξη.'),findsOneWidget);
  });
}
