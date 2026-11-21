import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_support_home_sections.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_attendance.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_close_sheet.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_pending.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_screens.dart';
import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_hbb/models/exantas_field_visit_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exantas_field_visit_fakes.dart';

class Rig {
  Rig({int limitBps = 1500}) {
    sync = ExantasFieldVisitSync(
        store: MemoryStore(),
        api: office.api,
        scope: () async => fvScopeA,
        now: () => clock,
        newId: () {
          ids += 1;
          return '${ids.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
        });
    sync.config = FvConfig(jobTypes: [jobType()], myDiscountLimitBps: limitBps);
    env = FvEnv(
        sync: sync,
        now: () => clock,
        locate: () async => fix,
        pickPhoto: () async => null,
        scanBarcode: (_) async => null);
  }
  final office = FakeOffice();
  DateTime clock = DateTime.utc(2026, 11, 21, 9, 30);
  int ids = 0;
  late final ExantasFieldVisitSync sync;
  late final FvEnv env;
  FvFix? fix = FvFix(37.97, 23.72, 8, DateTime.utc(2026, 11, 21, 9, 30));

  Future<FieldVisit> visit({bool arrive = true}) async {
    await sync.load();
    final v = await sync.startVisit(customerId: 'c-1', customerName: 'Κ. Αλεξίου Λογιστική', jobType: jobType());
    if (arrive) await sync.arrive(v.id, fix: fix);
    return v;
  }
}

Widget host(Widget child, {double scale = 1.0}) => MaterialApp(
    theme: ExantasTheme.light(),
    builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
    home: child);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  for (final scale in [1.3, 2.0]) {
    group('text scale $scale', () {
      testWidgets('attendance panel: arrive, pause, depart do not overflow', (tester) async {
        phone(tester);
        final rig = Rig();
        final v = await rig.visit(arrive: false);
        await tester.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: FvAttendancePanel(env: rig.env, visitId: v.id))), scale: scale));
        expect(find.byKey(const ValueKey('fv-arrive')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('fv-arrive')));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const ValueKey('fv-pause')), findsOneWidget);
        expect(find.byKey(const ValueKey('fv-depart')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('summary (close sheet) lays out without overflow', (tester) async {
        phone(tester);
        final rig = Rig();
        final v = await rig.visit();
        await rig.sync.updateLocal(v.id, (x) {
          x.outcome = FvOutcome.newVisit;
          x.chargeSource = FvChargeSource.prepaid;
          x.discountBps = 500;
        });
        await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id), scale: scale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('fv-to-signature')), findsOneWidget);
      });

      testWidgets('signature page lays out without overflow', (tester) async {
        phone(tester);
        final rig = Rig();
        final v = await rig.visit();
        await tester.pumpWidget(host(FvSignaturePage(env: rig.env, visitId: v.id), scale: scale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('fv-no-signature')), findsOneWidget);
      });

      testWidgets('closed page with unresolved close and payment form', (tester) async {
        phone(tester);
        final rig = Rig();
        final v = await rig.visit();
        await rig.sync.updateLocal(v.id, (x) {
          x.outcome = FvOutcome.done;
          x.chargeSource = FvChargeSource.invoice;
          x.noSignature = true;
        });
        rig.office.onPost = (p, b) async => throw rejection(503, 'x');
        await rig.sync.closeVisit(v.id).catchError((_) {});
        await tester.pumpWidget(host(FvClosedPage(env: rig.env, visitId: v.id), scale: scale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('fv-payment-card')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const ValueKey('fv-payment-card')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('attendance', () {
    testWidgets('GPS failure still records arrival and shows the flag', (tester) async {
      phone(tester);
      final rig = Rig()..fix = null;
      final v = await rig.visit(arrive: false);
      await tester.pumpWidget(host(Scaffold(body: FvAttendancePanel(env: rig.env, visitId: v.id))));
      await tester.tap(find.byKey(const ValueKey('fv-arrive')));
      await tester.pump();
      await tester.pump();
      final a = rig.sync.visit(v.id)!.myAttendance;
      expect(a.arrived, isTrue);
      expect(a.gpsMissing, isTrue);
      expect(find.text('Χωρίς GPS'), findsOneWidget);
    });

    testWidgets('GPS success stores the fix and shows no flag', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit(arrive: false);
      await tester.pumpWidget(host(Scaffold(body: FvAttendancePanel(env: rig.env, visitId: v.id))));
      await tester.tap(find.byKey(const ValueKey('fv-arrive')));
      await tester.pump();
      await tester.pump();
      final a = rig.sync.visit(v.id)!.myAttendance;
      expect(a.lat, 37.97);
      expect(a.gpsMissing, isFalse);
      expect(find.text('Χωρίς GPS'), findsNothing);
    });

    testWidgets('pause toggles to resume; depart ends the span and hides the controls', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(Scaffold(body: FvAttendancePanel(env: rig.env, visitId: v.id))));
      await tester.tap(find.byKey(const ValueKey('fv-pause')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Συνέχεια'), findsOneWidget);
      expect(rig.sync.visit(v.id)!.myAttendance.onPause, isTrue);
      rig.clock = rig.clock.add(const Duration(minutes: 5));
      await tester.tap(find.byKey(const ValueKey('fv-pause')));
      await tester.pump();
      await tester.pump();
      rig.clock = rig.clock.add(const Duration(minutes: 5));
      await tester.tap(find.byKey(const ValueKey('fv-depart')));
      await tester.pump();
      await tester.pump();
      expect(rig.sync.visit(v.id)!.myAttendance.departed, isTrue);
      expect(find.byKey(const ValueKey('fv-depart')), findsNothing);
    });

    testWidgets('invalid action shows a Greek error and changes nothing', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(Scaffold(body: FvAttendancePanel(env: rig.env, visitId: v.id))));
      rig.clock = rig.clock.add(const Duration(minutes: 1));
      // clock moved back before arrival => departure is not after arrival
      rig.clock = rig.clock.subtract(const Duration(minutes: 5));
      await tester.tap(find.byKey(const ValueKey('fv-depart')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('fv-attendance-error')), findsOneWidget);
      expect(rig.sync.visit(v.id)!.myAttendance.departed, isFalse);
    });
  });

  group('discount slider cap', () {
    testWidgets('slider tops out at the technician limit and label shows it', (tester) async {
      phone(tester);
      final rig = Rig(limitBps: 1500);
      final v = await rig.visit();
      await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id)));
      await tester.pump();
      final slider = tester.widget<Slider>(find.byKey(const ValueKey('fv-discount')));
      expect(slider.max, 15);
      expect(slider.divisions, 15);
      expect(slider.onChanged, isNotNull);
      expect(find.text('Έκπτωση 0% (όριο σου 15%)'), findsOneWidget);
      // dragging far past the end can never exceed the limit
      await tester.drag(find.byKey(const ValueKey('fv-discount')), const Offset(2000, 0));
      await tester.pump();
      await tester.pump();
      expect(rig.sync.visit(v.id)!.discountBps, lessThanOrEqualTo(1500));
      expect(rig.sync.visit(v.id)!.discountBps, 1500);
    });

    testWidgets('limit 0: slider disabled with explanation', (tester) async {
      phone(tester);
      final rig = Rig(limitBps: 0);
      final v = await rig.visit();
      await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id)));
      await tester.pump();
      expect(tester.widget<Slider>(find.byKey(const ValueKey('fv-discount'))).onChanged, isNull);
      expect(find.text('Δεν έχεις δικαίωμα έκπτωσης. Το όριο το ορίζει ο admin.'), findsOneWidget);
    });

    testWidgets('continue stays disabled until outcome and charge source are chosen', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id)));
      await tester.pump();
      FilledButton cont() => tester.widget<FilledButton>(find.byKey(const ValueKey('fv-to-signature')));
      expect(cont().onPressed, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('fv-source-invoice')));
      await tester.tap(find.byKey(const ValueKey('fv-source-invoice')));
      await tester.pump();
      await tester.pump();
      expect(cont().onPressed, isNull); // outcome still missing
      await tester.ensureVisible(find.byKey(const ValueKey('fv-outcome-done')));
      await tester.tap(find.byKey(const ValueKey('fv-outcome-done')));
      await tester.pump();
      await tester.pump();
      expect(cont().onPressed, isNotNull);
      expect(rig.sync.visit(v.id)!.chargeSource, FvChargeSource.invoice);
    });

    testWidgets('the app never computes money: no preview call is made offline, copy explains', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id)));
      await tester.pump();
      expect(find.text('Η χρέωση υπολογίζεται από το Office μόλις συγχρονίσει το δελτίο.'), findsOneWidget);
      expect(rig.office.posts('charge-preview'), isEmpty);
    });

    testWidgets('server preview is shown as sent (formatting only)', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      rig.office.onPost = (p, b) async => p.endsWith('/save') || p.endsWith('/attendance')
          ? {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)}
          : {'status': 'ok', 'charge': {'subtotal_minor': '10133', 'discount_minor': '1013', 'discount_bps': 1000, 'net_minor': '9120'}};
      await rig.sync.sync(force: true);
      await rig.sync.updateLocal(v.id, (x) => x.chargeSource = FvChargeSource.prepaid);
      await tester.pumpWidget(host(FvSummaryPage(env: rig.env, visitId: v.id)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fv-preview')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('fv-preview-net')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('fv-preview-net'))).data, '91,20 €');
    });
  });

  group('signature pad', () {
    testWidgets('close needs a real stroke AND a name; clear resets', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(FvSignaturePage(env: rig.env, visitId: v.id)));
      bool enabled() => tester.widget<FilledButton>(find.byKey(const ValueKey('fv-sign-close'))).onPressed != null;
      expect(enabled(), isFalse);
      await tester.enterText(find.byKey(const ValueKey('fv-signer')), 'Κατερίνα Αλεξίου');
      await tester.pump();
      expect(enabled(), isFalse); // name alone is not enough
      // a tap (dot) is not a signature
      await tester.tapAt(tester.getCenter(find.byType(FvSignaturePad)));
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.drag(find.byType(FvSignaturePad), const Offset(120, 30));
      await tester.pump();
      expect(enabled(), isTrue);
      await tester.tap(find.byKey(const ValueKey('fv-sign-clear')));
      await tester.pump();
      expect(enabled(), isFalse);
      // ink but no name
      await tester.drag(find.byType(FvSignaturePad), const Offset(120, 30));
      await tester.enterText(find.byKey(const ValueKey('fv-signer')), '   ');
      await tester.pump();
      expect(enabled(), isFalse);
    });

    testWidgets('PNG export is a white-background PNG under the size cap', (tester) async {
      final c = FvSignatureController()
        ..padSize = const Size(300, 120)
        ..start(const Offset(10, 10))
        ..extend(const Offset(150, 60))
        ..extend(const Offset(280, 20));
      expect(c.hasInk, isTrue);
      final bytes = (await tester.runAsync(() => c.toPng()))!;
      expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(bytes.length, lessThan(150 * 1024));
    });

    testWidgets('signing sends the PNG and signer name in the single close request', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await rig.sync.updateLocal(v.id, (x) {
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
      });
      rig.office.onPost = (p, b) async => p.endsWith('/close')
          ? {'status': 'ok', 'visit': visitDto(v.id, status: 'awaiting_participants'), 'warnings': [], 'finalized': false}
          : {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      await tester.pumpWidget(host(FvSignaturePage(env: rig.env, visitId: v.id)));
      await tester.enterText(find.byKey(const ValueKey('fv-signer')), 'Κατερίνα Αλεξίου');
      await tester.drag(find.byType(FvSignaturePad), const Offset(120, 30));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fv-sign-close')));
      // PNG encoding needs the real event loop; interleave it with fake-async pumps.
      for (var i = 0; i < 100 && rig.office.posts('/close').isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump();
      final err = find.byKey(const ValueKey('fv-close-error'));
      if (err.evaluate().isNotEmpty) fail('close failed: ${tester.widget<Text>(err).data}');
      final close = rig.office.posts('/close').single.body!;
      expect(close['signature']['signer_name'], 'Κατερίνα Αλεξίου');
      final png = base64Decode(close['signature']['png_base64'] as String);
      expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]);
      expect(rig.sync.visit(v.id)!.localStatus, FvLocalStatus.awaiting);
    });

    testWidgets('«Χωρίς υπογραφή» asks for confirmation then closes without an image', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await rig.sync.updateLocal(v.id, (x) {
        x.outcome = FvOutcome.pending;
        x.chargeSource = FvChargeSource.invoice;
      });
      rig.office.onPost = (p, b) async => p.endsWith('/close')
          ? {'status': 'ok', 'visit': visitDto(v.id, status: 'closed'), 'warnings': [], 'finalized': true}
          : {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      await tester.pumpWidget(host(FvSignaturePage(env: rig.env, visitId: v.id)));
      await tester.tap(find.byKey(const ValueKey('fv-no-signature')));
      await tester.pumpAndSettle();
      expect(find.text('Κλείσιμο χωρίς υπογραφή;'), findsOneWidget);
      expect(rig.office.posts('/close'), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Χωρίς υπογραφή'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(rig.office.posts('/close').single.body!['signature'], {'no_signature': true});
    });

    testWidgets('a rejected close shows the Greek reason and unlocks', (tester) async {
      phone(tester);
      final rig = Rig(limitBps: 1500);
      final v = await rig.visit();
      await rig.sync.updateLocal(v.id, (x) {
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
        x.noSignature = true;
      });
      rig.office.onPost = (p, b) async => p.endsWith('/close') ? throw rejection(422, 'discount_exceeds_limit') : {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      await rig.sync.closeVisit(v.id);
      expect(rig.sync.visit(v.id)!.contentLocked, isFalse);
      expect(rig.sync.visit(v.id)!.closeRejection!['code'], 'discount_exceeds_limit');
    });
  });

  group('lists', () {
    testWidgets('today panel shows visits with an unsynced badge and the new-visit action', (tester) async {
      phone(tester);
      final rig = Rig();
      await rig.visit();
      await tester.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: FvTodayPanel(env: rig.env)))));
      await tester.pump();
      expect(find.text('Κ. Αλεξίου Λογιστική'), findsOneWidget);
      expect(find.text('Δεν έχει συγχρονίσει'), findsOneWidget);
      expect(find.byKey(const ValueKey('fv-new-visit')), findsOneWidget);
    });

    testWidgets('pending section lists unsynced visits and offers sync', (tester) async {
      phone(tester);
      final rig = Rig();
      final v = await rig.visit();
      await tester.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: FvUnsyncedList(env: rig.env)))));
      await tester.pump();
      expect(find.byKey(ValueKey('fv-pending-${v.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('fv-pending-sync-${v.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('fv-pending-abandon-${v.id}')), findsNothing);
    });

    testWidgets('calendar lists the day appointment and books through the engine', (tester) async {
      phone(tester);
      final rig = Rig();
      await rig.sync.load();
      await rig.sync.createAppointment(
          customerId: 'c-1', customerName: 'Ιατρείο Νικολάου', jobType: jobType(), start: DateTime.utc(2026, 11, 21, 8), end: DateTime.utc(2026, 11, 21, 9));
      await tester.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: FvCalendarPanel(env: rig.env)))));
      await tester.pump();
      expect(find.text('Ιατρείο Νικολάου'), findsOneWidget);
      expect(find.text('Νοέμβριος 2026'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fv-week-next')));
      await tester.pump();
      expect(find.text('Ιατρείο Νικολάου'), findsNothing);
    });
  });

  group('work tab entry point', () {
    Widget view({Widget? calendar}) => host(Scaffold(
        body: ExantasWorkView(
            signedIn: true,
            busy: false,
            section: ExantasWorkSection.today,
            onSection: (_) {},
            customerPanel: const SizedBox.shrink(),
            pendingPanel: const SizedBox.shrink(),
            pendingCount: 0,
            calendarPanel: calendar,
            onRefresh: () {})));

    testWidgets('Ημερολόγιο segment only appears when the feature is on', (tester) async {
      phone(tester);
      await tester.pumpWidget(view());
      expect(find.byKey(const ValueKey('support-tab-calendar')), findsNothing);
      await tester.pumpWidget(view(calendar: const SizedBox()));
      expect(find.byKey(const ValueKey('support-tab-calendar')), findsOneWidget);
      expect(find.text('Ημερολόγιο'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
