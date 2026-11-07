import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_pending.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_pending_center.dart';

Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
      'event_id': 'e1', 'peer_id': '123', 'rustdesk_session_id': '99', 'work_item_id': 'w',
      'ended_at': '2026-10-30T10:02:00Z', 'started_at': '2026-10-30T10:00:00Z', ...extra,
    };

void main() {
  test('classification and precedence', () {
    PendingKind k(Map<String, dynamic> r) => classifyPending(r);
    expect(k(row()), PendingKind.decision);
    expect(k(row({'rustdesk_session_id': '0'})), PendingKind.identity);
    expect(k(row({'rustdesk_session_id': null})), PendingKind.identity);
    expect((row()..remove('work_item_id')).isEmpty, false);
    expect(k(row()..remove('work_item_id')), PendingKind.association);
    expect(k(row({'ended_at': null})), PendingKind.timing);
    expect(k(row({'timing_verified': false})), PendingKind.timing);
    expect(k(row({'timing_verified': true})), PendingKind.decision);
    expect(k(row({'financial_operation': {'key': 'k'}})), PendingKind.priorRequest);
    expect(k({'kind': 'work_creation', 'creation_pending': true}), PendingKind.priorRequest);
    expect(k(row({'office_review': 'conflict'})), PendingKind.officeReview);
    expect(k(row({'resolved_in_office_report': 'r'})), PendingKind.officeReview);
    // precedence: Office review over prior request over identity
    expect(k(row({'office_review': 'finalized', 'financial_operation': {}, 'rustdesk_session_id': '0'})), PendingKind.officeReview);
    expect(k(row({'financial_operation': {}, 'rustdesk_session_id': '0'})), PendingKind.priorRequest);
  });
  test('one next action per kind and Greek labels', () {
    expect(classifyRow(row()).action, PendingAction.decide);
    expect(classifyRow(row({'financial_operation': {}})).action, PendingAction.checkRequest);
    expect(classifyRow(row()..remove('work_item_id')).action, PendingAction.associate);
    expect(classifyRow(row({'office_review': 'x'})).action, PendingAction.openOffice);
    expect(classifyRow(row()).label, 'Χρειάζεται απόφαση');
    expect(pendingLabel(PendingKind.timing), 'Αναμονή επαλήθευσης διάρκειας');
  });
  test('customer/work shown only when bound to Office work', () {
    expect(classifyRow(row({'customer_name': 'Α', 'work_title': 'Τ'})).customerName, 'Α');
    expect(classifyRow(row({'customer_name': 'Α'})..remove('work_item_id')).customerName, isNull);
  });
  test('age text', () {
    final now = DateTime.utc(2026, 11, 7, 12);
    expect(formatPendingAge(now.subtract(const Duration(days: 3)), now), 'πριν 3 ημέρες');
    expect(formatPendingAge(now.subtract(const Duration(days: 1)), now), 'πριν 1 ημέρα');
    expect(formatPendingAge(now.subtract(const Duration(hours: 5)), now), 'πριν 5 ώρες');
    expect(formatPendingAge(now.subtract(const Duration(minutes: 7)), now), 'πριν 7 λεπτά');
    expect(formatPendingAge(now, now), 'μόλις τώρα');
    expect(formatPendingAge(null, now), '');
  });
  test('authoritative time only when Office verified it', () {
    expect(pendingAuthoritativeEnd(row({'provider_ended_at': '2026-10-30T10:02:00Z'})), isNull);
    expect(pendingAuthoritativeEnd(row({'timing_verified': true, 'provider_ended_at': '2026-10-30T10:02:00Z'})), isNotNull);
  });
  test('sorted newest first; summary counts', () {
    final items = classifyPendingRows([
      row({'event_id': 'old', 'started_at': '2026-10-01T00:00:00Z'}),
      row({'event_id': 'new', 'started_at': '2026-10-30T00:00:00Z', 'financial_operation': {}}),
    ]);
    expect(items.first.row['event_id'], 'new');
    expect(pendingSummary(items), '1 χρειάζονται απόφαση · 1 έλεγχος αιτήματος');
    expect(pendingSummary([]), '');
  });
  test('abandon only offered for prior-request rows with proof and age', () {
    final now = DateTime.utc(2026, 11, 7, 12);
    String ago(int s) => now.subtract(Duration(seconds: s)).toIso8601String();
    Map<String, dynamic> op(Map<String, dynamic> m) => row({'financial_operation': {'key': 'k', ...m}});
    expect(pendingCanAbandon(op({'reserved_at': ago(600)}), now), false); // no proof
    expect(pendingCanAbandon(op({'reserved_at': ago(30), 'not_found_at': ago(5)}), now), false); // young
    expect(pendingCanAbandon(op({'reserved_at': ago(600), 'not_found_at': ago(5)}), now), true);
    expect(pendingCanAbandon(op({'reserved_at': ago(600), 'rejected': {'status': 409, 'code': 'stale_preview'}}), now), true);
    expect(pendingCanAbandon(op({'not_found_at': ago(30)}), now), false); // legacy: ages from first not_found
    expect(pendingCanAbandon(op({'not_found_at': ago(300)}), now), true);
    expect(pendingCanAbandon(row(), now), false);
    expect(pendingCanAbandon({'kind': 'work_creation', 'creation_pending': true, 'reserved_at': ago(600), 'not_found_at': ago(1)}, now), true);
    expect(pendingCanAbandon({'kind': 'work_creation', 'creation_pending': true, 'reserved_at': ago(10), 'not_found_at': ago(1)}, now), false);
  });

  testWidgets('pending list: shows fields, one action, abandon only when eligible', (tester) async {
    final now = DateTime.now().toUtc();
    final started = now.subtract(const Duration(days: 3)).toIso8601String();
    PendingItem? acted, abandoned;
    final items = classifyPendingRows([
      row({'event_id': 'a', 'started_at': started, 'customer_name': 'Πελάτης Α', 'work_title': 'Εργασία Α',
        'timing_verified': true, 'provider_ended_at': started, 'provider_duration_seconds': 120}),
      row({'event_id': 'b', 'financial_operation': {'key': 'k', 'reserved_at': started, 'not_found_at': started}}),
      row({'event_id': 'c', 'financial_operation': {'key': 'k2', 'reserved_at': now.toIso8601String()}}),
    ]);
    await tester.pumpWidget(MaterialApp(theme: ExantasTheme.light(), home: Scaffold(
        body: SingleChildScrollView(child: ExantasPendingList(items: items, now: now, busy: false,
            onAction: (i) => acted = i, onAbandon: (i) => abandoned = i)))));
    expect(find.text('Πελάτης Α'), findsOneWidget);
    expect(find.text('Χρειάζεται απόφαση'), findsOneWidget);
    expect(find.textContaining('πριν 3 ημέρες'), findsWidgets);
    expect(find.textContaining('Λήξη (πάροχος)'), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-abandon-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-abandon-c')), findsNothing);
    expect(find.byKey(const ValueKey('pending-abandon-a')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pending-action-a')));
    expect(acted?.row['event_id'], 'a');
    await tester.ensureVisible(find.byKey(const ValueKey('pending-abandon-b')));
    await tester.tap(find.byKey(const ValueKey('pending-abandon-b')));
    expect(abandoned?.row['event_id'], 'b');
  });
}
