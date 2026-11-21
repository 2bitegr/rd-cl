import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_close_sheet.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_field_visit_attendance.dart';
import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_hbb/models/exantas_field_visit_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exantas_field_visit_fakes.dart';

void main() {
  group('rate parsing and validation (0 < x <= 1000,00, comma decimal)', () {
    test('converts typed euros to integer minor units', () {
      expect(fvParseAfterHoursRate('60'), 6000);
      expect(fvParseAfterHoursRate('60,5'), 6050);
      expect(fvParseAfterHoursRate('60,05'), 6005);
      expect(fvParseAfterHoursRate(' 0,01 '), 1);
      expect(fvParseAfterHoursRate('1000,00'), 100000);
      expect(fvParseAfterHoursRate('1000'), 100000);
    });
    test('rejects zero, over the cap, dot decimals and junk', () {
      for (final bad in ['', '0', '0,00', '1000,01', '1001', '60.5', '60,555', '-5', 'abc', '1.000,00', '12345']) {
        expect(fvParseAfterHoursRate(bad), isNull, reason: bad);
      }
    });
    test('issue ids distinguish required from invalid', () {
      expect(fvAfterHoursRateIssue(''), 'after_hours_rate_required');
      expect(fvAfterHoursRateIssue('0'), 'invalid_after_hours_rate');
      expect(fvAfterHoursRateIssue('60,00'), isNull);
    });
    test('close blockers only apply when the switch is on', () {
      final v = FieldVisit(id: '11111111-1111-4111-8111-111111111111', owner: 'o', api: 'a', selfUserId: 'u')
        ..leadUserId = 'u'
        ..afterHoursRateText = '0';
      expect(fvCloseBlockers(v, discountLimitBps: 0), isNot(contains('invalid_after_hours_rate')));
      v.afterHoursApply = true;
      expect(fvCloseBlockers(v, discountLimitBps: 0), contains('invalid_after_hours_rate'));
      v.afterHoursRateText = '';
      expect(fvCloseBlockers(v, discountLimitBps: 0), contains('after_hours_rate_required'));
      v.afterHoursRateText = '60,00';
      expect(fvCloseBlockers(v, discountLimitBps: 0).where((b) => b.contains('after_hours')), isEmpty);
    });
  });

  group('DTO parsing', () {
    test('config reads the default rate (string or number, top level or settings), null when absent', () {
      expect(FvConfig.fromJson({'default_after_hours_rate_minor_per_hour': '6000'}).defaultAfterHoursRateMinor, 6000);
      expect(FvConfig.fromJson({'default_after_hours_rate_minor_per_hour': 4500}).defaultAfterHoursRateMinor, 4500);
      expect(FvConfig.fromJson({'settings': {'default_after_hours_rate_minor_per_hour': '5000'}}).defaultAfterHoursRateMinor, 5000);
      expect(FvConfig.fromJson({'default_after_hours_rate_minor_per_hour': null}).defaultAfterHoursRateMinor, isNull);
      expect(FvConfig.fromJson({'my_discount_limit_bps': 100}).defaultAfterHoursRateMinor, isNull);
      final c = FvConfig(defaultAfterHoursRateMinor: 6000);
      expect(FvConfig.fromJson(c.toJson()).defaultAfterHoursRateMinor, 6000);
      expect(c.toJson().containsKey('surcharge_bps'), isFalse);
    });
    test('ChargeDto after-hours fields; legacy surcharge_bps is ignored', () {
      final ah = FvChargeAfterHours.fromCharge({
        'after_hours_minutes': 50,
        'after_hours_apply': true,
        'after_hours_rate_minor_per_hour': '6000',
        'surcharge_minor': '-120',
        'surcharge_bps': 2500,
      })!;
      expect((ah.minutes, ah.apply, ah.rateMinorPerHour, ah.surchargeMinor), (50, true, 6000, -120));
      final none = FvChargeAfterHours.fromCharge({'net_minor': '1'})!;
      expect((none.minutes, none.apply, none.rateMinorPerHour, none.surchargeMinor), (0, false, null, null));
    });
  });

  group('close payload and offline persistence', () {
    late MemoryStore store;
    late FakeOffice office;
    late DateTime clock;
    var ids = 0;

    ExantasFieldVisitSync make() => ExantasFieldVisitSync(
        store: store,
        api: office.api,
        scope: () async => fvScopeA,
        now: () => clock,
        newId: () {
          ids += 1;
          return '${ids.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
        });

    setUp(() {
      store = MemoryStore();
      office = FakeOffice();
      clock = DateTime.utc(2026, 11, 21, 9, 30);
      ids = 0;
      fvAttendanceEcho.clear();
      fvContentEcho.clear();
    });

    Future<(ExantasFieldVisitSync, FieldVisit)> ready({bool apply = false, String rate = ''}) async {
      final sync = make();
      await sync.load();
      final v = await sync.startVisit(customerId: 'c-1', customerName: 'Κ. Αλεξίου', jobType: jobType());
      await sync.arrive(v.id, fix: FvFix(37.9, 23.7, 8, clock));
      await sync.updateLocal(v.id, (x) {
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
        x.noSignature = true;
        x.afterHoursApply = apply;
        x.afterHoursRateText = rate;
        x.afterHoursMinutes = 50;
      });
      office.onPost = (p, b) async {
        final id = RegExp(r'field-visits/([0-9a-f-]{36})/').firstMatch(p)?.group(1) ?? 'x';
        if (p.endsWith('/close')) throw const SocketException('offline');
        if (p.endsWith('/attendance')) fvAttendanceEcho[id] = Map<String, dynamic>.from(b);
        if (p.endsWith('/save')) fvContentEcho[id] = Map<String, dynamic>.from(b);
        return {'status': 'ok', 'applied': true, 'visit': visitDto(id), 'warnings': []};
      };
      return (sync, v);
    }

    test('apply:false by default is sent explicitly', () async {
      final (sync, v) = await ready();
      await sync.closeVisit(v.id);
      expect(office.posts('/close').single.body!['after_hours'], {'apply': false});
    });

    test('apply:true sends the integer minor string', () async {
      final (sync, v) = await ready(apply: true, rate: '60,50');
      await sync.closeVisit(v.id);
      expect(office.posts('/close').single.body!['after_hours'], {'apply': true, 'rate_minor_per_hour': '6050'});
    });

    test('an invalid or missing rate blocks the close and nothing is queued', () async {
      for (final (rate, id) in [('', 'after_hours_rate_required'), ('1000,01', 'invalid_after_hours_rate'), ('0', 'invalid_after_hours_rate')]) {
        final (sync, v) = await ready(apply: true, rate: rate);
        await expectLater(sync.closeVisit(v.id), throwsA(predicate((e) => '$e'.contains(id))));
        expect(sync.visit(v.id)!.closeOp, isNull);
      }
    });

    test('input survives a restart and the frozen close body keeps it for replay', () async {
      final (sync, v) = await ready(apply: true, rate: '60,00');
      var reloaded = make();
      await reloaded.load();
      expect(reloaded.visit(v.id)!.afterHoursApply, isTrue);
      expect(reloaded.visit(v.id)!.afterHoursRateText, '60,00');
      expect(reloaded.visit(v.id)!.afterHoursMinutes, 50);

      await sync.closeVisit(v.id);
      final sent = office.posts('/close').single.body!;
      reloaded = make();
      await reloaded.load();
      final op = reloaded.visit(v.id)!.closeOp!;
      expect(op.body['after_hours'], {'apply': true, 'rate_minor_per_hour': '6000'});
      // Editing the local input afterwards can never change the frozen body.
      expect(op.body['after_hours'], sent['after_hours']);
    });
  });

  group('widget', () {
    Widget host(Widget child, double scale) => MaterialApp(
        theme: ExantasTheme.light(),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: child);

    Future<(ExantasFieldVisitSync, FvEnv, FieldVisit, FakeOffice)> rig({int? defaultRate = 6000, int minutes = 50}) async {
      final office = FakeOffice();
      final clock = DateTime.utc(2026, 11, 21, 9, 30);
      var n = 0;
      final sync = ExantasFieldVisitSync(
          store: MemoryStore(),
          api: office.api,
          scope: () async => fvScopeA,
          now: () => clock,
          newId: () => '${(++n).toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000');
      sync.config = FvConfig(jobTypes: [jobType()], defaultAfterHoursRateMinor: defaultRate);
      final env = FvEnv(
          sync: sync, now: () => clock, locate: () async => null, pickPhoto: () async => null, scanBarcode: (_) async => null);
      await sync.load();
      final v = await sync.startVisit(customerId: 'c-1', customerName: 'Κ. Αλεξίου', jobType: jobType());
      await sync.arrive(v.id, fix: FvFix(37.9, 23.7, 8, clock));
      await sync.updateLocal(v.id, (x) {
        x.outcome = FvOutcome.done;
        x.chargeSource = FvChargeSource.prepaid;
        x.afterHoursMinutes = minutes;
      });
      return (sync, env, v, office);
    }

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('hidden without after-hours minutes', (tester) async {
      phone(tester);
      final (_, env, v, _) = await rig(minutes: 0);
      await tester.pumpWidget(host(FvSummaryPage(env: env, visitId: v.id), 1.3));
      await tester.pump();
      expect(find.byKey(const ValueKey('fv-after-hours')), findsNothing);
    });

    testWidgets('text scale 1.3: off by default, switch prefills the default rate, comma input validates', (tester) async {
      phone(tester);
      final (sync, env, v, _) = await rig();
      await tester.pumpWidget(host(FvSummaryPage(env: env, visitId: v.id), 1.3));
      await tester.pump();
      expect(find.text('Χρέωση εκτός ωραρίου'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('fv-after-hours'))).value, isFalse);
      expect(find.byKey(const ValueKey('fv-after-hours-rate')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('fv-after-hours')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fv-after-hours')));
      await tester.pump();
      await tester.pump();
      expect(sync.visit(v.id)!.afterHoursApply, isTrue);
      expect(find.widgetWithText(TextField, '60,00'), findsOneWidget);
      expect(sync.visit(v.id)!.afterHoursRateText, '60,00');
      expect(find.text('Τιμή ανά ώρα (€)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // dots and letters are filtered; invalid value shows the Greek message
      await tester.enterText(find.byKey(const ValueKey('fv-after-hours-rate')), '1.0a00,01');
      await tester.pump();
      expect(sync.visit(v.id)!.afterHoursRateText, '1000,01');
      expect(find.text('Γράψε τιμή μεγαλύτερη από 0 έως 1.000,00 €, π.χ. 60,00.'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(const ValueKey('fv-after-hours-rate')), '45,5');
      await tester.pump();
      expect(fvAfterHoursPayload(sync.visit(v.id)!), {'apply': true, 'rate_minor_per_hour': '4550'});
      expect(find.text('Γράψε τιμή μεγαλύτερη από 0 έως 1.000,00 €, π.χ. 60,00.'), findsNothing);
    });

    testWidgets('no default configured: field starts empty', (tester) async {
      phone(tester);
      final (sync, env, v, _) = await rig(defaultRate: null);
      await tester.pumpWidget(host(FvSummaryPage(env: env, visitId: v.id), 1.3));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('fv-after-hours')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fv-after-hours')));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('fv-after-hours-rate'))).controller!.text, '');
      expect(sync.visit(v.id)!.afterHoursRateText, '');
    });

    testWidgets('server preview line and negative surcharge render at 1.3', (tester) async {
      phone(tester);
      final (sync, env, v, office) = await rig();
      office.onPost = (p, b) async => p.endsWith('/charge-preview')
          ? {
              'status': 'ok',
              'charge': {
                'subtotal_minor': '7000', 'discount_minor': '700', 'discount_bps': 1000, 'net_minor': '6300',
                'after_hours_minutes': 50, 'after_hours_apply': true, 'after_hours_rate_minor_per_hour': '6000', 'surcharge_minor': '-333',
              }
            }
          : {'status': 'ok', 'applied': true, 'visit': visitDto(v.id)};
      await sync.sync(force: true);
      await sync.updateLocal(v.id, (x) {
        x.afterHoursApply = true;
        x.afterHoursRateText = '60,00';
      });
      await tester.pumpWidget(host(FvSummaryPage(env: env, visitId: v.id), 1.3));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fv-preview')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Εκτός ωραρίου: 50 λεπτά × 60,00 €/ώρα'), findsOneWidget);
      expect(find.byKey(const ValueKey('fv-preview-surcharge')), findsOneWidget);
      expect(office.posts('charge-preview').last.body!['after_hours'], {'apply': true, 'rate_minor_per_hour': '6000'});
      expect(tester.takeException(), isNull);
    });
  });
}
