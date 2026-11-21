import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exantas_field_visit_fakes.dart';

DateTime t(String hhmm, {int day = 21}) {
  final p = hhmm.split(':');
  return DateTime.utc(2026, 11, day, int.parse(p[0]), int.parse(p[1]));
}

void main() {
  group('minute math (display only)', () {
    test('subtracts pauses and floors to whole minutes', () {
      final a = DateTime.utc(2026, 11, 21, 9, 31, 59);
      final d = DateTime.utc(2026, 11, 21, 11, 1, 5);
      // 09:31 -> 11:01 = 90 min, pause 10 min.
      expect(fvWorkedMinutes(a, d, [FvPause(t('10:00'), t('10:10'))], d), 80);
    });
    test('pauses are unioned, clipped to the span, open pause ends at departure', () {
      final pauses = [
        FvPause(t('09:00'), t('09:20')), // partly before arrival 09:10
        FvPause(t('09:15'), t('09:30')), // overlaps previous
        FvPause(t('10:30')), // open pause up to departure 11:00
      ];
      expect(fvWorkedMinutes(t('09:10'), t('11:00'), pauses, t('12:00')), 60);
    });
    test('open attendance runs to now; no arrival or negative span is zero', () {
      expect(fvWorkedMinutes(t('09:00'), null, [], t('09:34')), 34);
      expect(fvWorkedMinutes(null, null, [], t('09:34')), 0);
      expect(fvWorkedMinutes(t('10:00'), t('09:00'), [], t('12:00')), 0);
      expect(fvWorkedMinutes(t('09:00'), t('09:00'), [], t('12:00')), 0);
    });
    test('technicians are summed, never unioned', () {
      final v = FieldVisit(id: '11111111-1111-4111-8111-111111111111', owner: 'o', api: 'a', selfUserId: 'u1', participants: [
        FvParticipant(userId: 'u1', displayName: 'A', attendance: FvAttendance(arrivalAt: t('09:00'), departureAt: t('10:30'))),
        FvParticipant(userId: 'u2', displayName: 'B', attendance: FvAttendance(arrivalAt: t('09:30'), departureAt: t('10:30'))),
      ]);
      expect(v.totalWorkedMinutes(t('12:00')), 150);
    });
    test('formatting helpers', () {
      expect(fvFormatMinutes(45), "45'");
      expect(fvFormatMinutes(120), '2 ώρ.');
      expect(fvFormatMinutes(152), "2 ώρ. 32'");
      expect(fvFormatClock(34), '00:34');
    });
    test('euro input to minor units is input parsing only', () {
      expect(fvParseEuroToMinor('50'), 5000);
      expect(fvParseEuroToMinor('50,5'), 5050);
      expect(fvParseEuroToMinor('12.34 €'), 1234);
      expect(fvParseEuroToMinor('abc'), isNull);
      expect(fvParseEuroToMinor('1,234'), isNull);
    });
  });

  group('attendance validation', () {
    final now = t('10:00');
    test('valid spans', () {
      expect(fvValidateAttendance(FvAttendance(), now), isNull);
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00'), departureAt: t('09:30'), pauses: [FvPause(t('09:10'), t('09:15'))]), now), isNull);
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00'), pauses: [FvPause(t('09:10'))]), now), isNull);
    });
    test('future time beyond 5 minutes', () {
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('10:06')), now), 'time_in_future');
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('10:04')), now), isNull);
    });
    test('departure rules', () {
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00'), departureAt: t('09:00')), now), 'departure_before_arrival');
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00', day: 19), departureAt: t('09:30')), now), 'span_too_long');
      expect(fvValidateAttendance(FvAttendance(departureAt: t('09:30')), now), 'arrival_required');
    });
    test('pause rules', () {
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00'), departureAt: t('09:30'), pauses: [FvPause(t('09:10'))]), now), 'open_pause_invalid');
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:00'), pauses: [FvPause(t('09:10'), t('09:20')), FvPause(t('09:15'), t('09:25'))]), now), 'pause_overlap');
      expect(fvValidateAttendance(FvAttendance(arrivalAt: t('09:10'), pauses: [FvPause(t('09:00'), t('09:20'))]), now), 'pause_outside');
    });
  });

  group('DTO parsing and JSON round trip', () {
    test('local document survives encode/decode with every field', () {
      final v = FieldVisit(
          id: '22222222-2222-4222-8222-222222222222',
          owner: fvOwner,
          api: fvApi,
          selfUserId: fvOwner,
          customerId: 'c-1',
          customerName: 'Πελάτης',
          jobTypeId: 'jt',
          leadUserId: fvOwner,
          participants: [FvParticipant(userId: fvOwner, displayName: 'Εσύ', role: 'lead', isSelf: true, attendance: FvAttendance(arrivalAt: t('09:00'), lat: 37.97, lng: 23.72, accuracyM: 8, fixAt: t('09:00'), pauses: [FvPause(t('09:10'), t('09:20'))], clientRev: 3))],
          checklist: [FvChecklistItem(itemId: 'i', label: 'Backup', checked: true, note: 'ok')],
          equipmentLines: [FvEquipmentLine(equipmentId: 'e', action: 'installed')],
          defectiveUnits: [FvDefective(id: 'd', description: 'UPS')],
          equipment: [FvEquipment(id: 'e', kind: 'Εκτυπωτής', barcode: '123')],
          outcome: FvOutcome.newVisit,
          chargeSource: FvChargeSource.invoice,
          discountBps: 500,
          showPrices: true,
          signerName: 'Κ. Αλεξίου',
          signaturePngBase64: 'iVBOR',
          payments: [FvPayment(id: 'p', method: 'cash', amountMinor: 5000, receivedAt: t('11:00'))],
          followUpStart: t('12:00', day: 25));
      final back = FieldVisit.decode(v.encode())!;
      expect(back.encode(), v.encode());
      expect(back.myAttendance.pauses.single.end, t('09:20'));
      expect(back.outcome, FvOutcome.newVisit);
      expect(back.payments.single.amountMinor, 5000);
    });
    test('decode rejects foreign / corrupt payloads', () {
      expect(FieldVisit.decode('not json'), isNull);
      expect(FieldVisit.decode('{"visit_id":"x","owner":"o","api":"a"}'), isNull);
      expect(FieldVisit.decode('[1]'), isNull);
    });
    test('server DTO parsing: others only expose arrival time (GPS redaction agnostic)', () {
      final dto = visitDto('33333333-3333-4333-8333-333333333333', participants: [
        {'user_id': fvOwner, 'display_name': 'Εσύ', 'role': 'lead', 'is_self': true, 'arrival': {'at': '2026-11-21T07:31:00Z', 'lat': 1.5, 'lng': 2.5, 'accuracy_m': 9.0, 'fix_at': '2026-11-21T07:31:00Z'}, 'departure_at': null, 'pauses': []},
        {'user_id': 'u2', 'display_name': 'Ν. Πέτρου', 'role': 'member', 'arrival': {'at': '2026-11-21T07:28:00Z'}, 'departure_at': null, 'pauses': [], 'minutes': {'worked': 12}},
      ]);
      final v = FieldVisit.fromServer(dto, owner: fvOwner, api: fvApi, selfUserId: fvOwner);
      expect(v.participants.length, 2);
      expect(v.self!.attendance.lat, 1.5);
      final other = v.participants.last;
      expect(other.attendance.arrivalAt, DateTime.utc(2026, 11, 21, 7, 28));
      expect(other.attendance.lat, isNull);
      expect(other.serverWorkedMinutes, 12);
      expect(v.isLead, isTrue);
    });
    test('applyServer keeps local own attendance and content only when told', () {
      final id = '44444444-4444-4444-8444-444444444444';
      final v = FieldVisit.fromServer(visitDto(id), owner: fvOwner, api: fvApi, selfUserId: fvOwner);
      v.self!.attendance.arrivalAt = t('09:00');
      v.workSummary = 'τοπικό';
      v.applyServer(visitDto(id, status: 'awaiting_participants', extra: {'work_summary': 'server'}), keepLocalContent: true, keepLocalAttendance: true);
      expect(v.status, 'awaiting_participants');
      expect(v.localStatus, FvLocalStatus.awaiting);
      expect(v.workSummary, 'τοπικό');
      expect(v.self!.attendance.arrivalAt, t('09:00'));
      v.applyServer(visitDto(id, extra: {'work_summary': 'server'}), keepLocalContent: false, keepLocalAttendance: false);
      expect(v.workSummary, 'server');
      expect(v.self!.attendance.arrivalAt, isNull);
    });
    test('config parse and phrase filtering', () {
      final c = FvConfig.fromJson({
        'job_types': [
          {'id': 'a', 'code': 'breakdown', 'label_el': 'Βλάβη', 'checklist': [{'id': 'c1', 'label_el': 'Έλεγχος'}]}
        ],
        'phrases': [
          {'id': 'p1', 'text_el': 'Γενική', 'job_type_id': null},
          {'id': 'p2', 'text_el': 'Άλλη', 'job_type_id': 'b'}
        ],
        'eligible_staff': [{'id': 'u', 'display_name': 'Ν', 'color': '#fff'}],
        'my_discount_limit_bps': 1500,
        'config_revision': '7'
      });
      expect(c.jobType('a')!.checklist.single.label, 'Έλεγχος');
      expect([for (final p in c.phrasesFor('a')) p.id], ['p1']);
      expect(c.myDiscountLimitBps, 1500);
    });
  });

  group('close readiness', () {
    FieldVisit ready() => FieldVisit(
        id: '55555555-5555-4555-8555-555555555555',
        owner: fvOwner,
        api: fvApi,
        selfUserId: fvOwner,
        leadUserId: fvOwner,
        jobTypeId: 'jt',
        participants: [FvParticipant(userId: fvOwner, displayName: 'Εσύ', role: 'lead', isSelf: true, attendance: FvAttendance(arrivalAt: t('09:00')))],
        outcome: FvOutcome.done,
        chargeSource: FvChargeSource.prepaid,
        noSignature: true);
    test('ready visit has no blockers', () => expect(fvCloseBlockers(ready(), discountLimitBps: 0), isEmpty));
    test('each requirement is reported', () {
      final v = ready()
        ..outcome = null
        ..chargeSource = null
        ..noSignature = false;
      expect(fvCloseBlockers(v, discountLimitBps: 0), containsAll(['outcome_required', 'charge_source_required', 'signature_required']));
    });
    test('discount boundary: equal to limit ok, one above blocked', () {
      final v = ready()..discountBps = 1500;
      expect(fvCloseBlockers(v, discountLimitBps: 1500), isEmpty);
      v.discountBps = 1501;
      expect(fvCloseBlockers(v, discountLimitBps: 1500), contains('discount_exceeds_limit'));
    });
    test('signature needs a signer name; arrival is required; open pause blocks', () {
      final v = ready()
        ..noSignature = false
        ..signaturePngBase64 = 'abc';
      expect(fvCloseBlockers(v, discountLimitBps: 0), contains('signer_required'));
      v.signerName = 'Κ';
      expect(fvCloseBlockers(v, discountLimitBps: 0), isEmpty);
      v.self!.attendance.pauses = [FvPause(t('09:10'))];
      expect(fvCloseBlockers(v, discountLimitBps: 0), contains('open_pause'));
      v.self!.attendance
        ..pauses = []
        ..arrivalAt = null;
      expect(fvCloseBlockers(v, discountLimitBps: 0), contains('close_requires_arrival'));
    });
  });
}
