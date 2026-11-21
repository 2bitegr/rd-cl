import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_work_screens.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';
import 'package:flutter_hbb/models/exantas_office_work.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dayRow(String id, String state, {String title = 'Έλεγχος εκτυπωτή'}) => {
      'item': {
        'id': id,
        'title': title,
        'status': 'in_progress',
        'customer_id': 'c1',
        'support_state': state,
        'revision': '3'
      },
      'customer_name': 'Alpha ΕΠΕ',
      'branch_name': 'Κεντρικό',
      'updated_at': '2026-07-01T10:05:00Z',
      'own_minutes': 15,
      'launches': [],
    };

Map<String, dynamic> session(String id, {bool verified = true, String start = '2026-10-30T10:00:00Z', String end = '2026-10-30T10:12:30Z'}) => {
      'id': id,
      'peer_id': '123456789',
      'started_at': start,
      'ended_at': end,
      'duration_seconds': 750,
      'timing_quality': verified ? 'verified' : 'estimated',
      'technician_name': 'Μαρία Τεχνικός'
    };

Map<String, dynamic> context({List<Map<String, dynamic>>? sessions, bool canEdit = true}) => {
      'status': 'ok',
      'item': {
        'id': 'w1',
        'title': 'Δίκτυο γραφείου',
        'status': 'in_progress',
        'customer_id': 'c1',
        'customer_name': 'Alpha ΕΠΕ',
        'branch_name': 'Κεντρικό',
        'support_state': 'draft',
        'revision': '4'
      },
      'devices': [
        {'id': 'd1', 'peer_id': '123456789', 'label': 'Ταμείο', 'can_connect': true},
        {'id': 'd2', 'peer_id': '987654321', 'label': 'Αρχείο', 'can_connect': false},
      ],
      'activities': {
        'sessions': sessions ?? [],
        'calls': [
          {'id': 'k1', 'direction': 'inbound', 'caller_number': '2101234567', 'observed_at': '2026-10-30T09:50:00Z'}
        ]
      },
      'permissions': {'can_edit': canEdit},
    };

Widget host(Widget child) => MaterialApp(theme: ExantasTheme.light(), home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  test('Athens wall clock follows EET/EEST', () {
    expect(formatAthens(DateTime.utc(2026, 7, 1, 10, 5)), '01/07/2026 13:05');
    expect(formatAthens(DateTime.utc(2026, 10, 30, 10, 0)), '30/10/2026 12:00');
    expect(formatAthens(DateTime.utc(2026, 10, 24, 22, 30)), '25/10/2026 01:30');
    expect(formatAthens(null), '—');
  });

  test('my-day and my-open-work rows become work cards; pagination follows next_page', () async {
    final paths = <String>[];
    final office = ExantasOfficeWork((path) async {
      paths.add(path);
      if (path.endsWith('/my-day')) {
        return {'items': [dayRow('w1', 'draft'), dayRow('w2', 'review'), {'item': 'bad'}], 'truncated': true};
      }
      final page = path.endsWith('page=2');
      return {'items': [dayRow(page ? 'w4' : 'w3', 'draft')], 'next_page': page ? null : 2};
    });
    await office.loadToday();
    expect(office.today.items.map((c) => c.id), ['w1', 'w2']);
    expect(office.today.items.first.customerName, 'Alpha ΕΠΕ');
    expect(office.today.items.first.branchName, 'Κεντρικό');
    expect(office.today.truncated, isTrue);
    await office.loadOpen();
    await office.loadOpen(more: true);
    expect(office.open.items.map((c) => c.id), ['w3', 'w4']);
    expect(office.open.nextPage, isNull);
    expect(paths, ['/support-workflow/my-day', '/support-workflow/my-open-work?page=1', '/support-workflow/my-open-work?page=2']);
  });

  testWidgets('work card shows title, customer, branch, state, pending, update time, next action', (tester) async {
    final card = OfficeWorkCard.fromDayRow(dayRow('w1', 'review'))!;
    String? opened;
    await tester.pumpWidget(host(OfficeWorkFeedPanel(
        feed: OfficeFeed(state: OfficeLoad.ready, items: [card]),
        pendingWorkIds: const {'w1'},
        onOpen: (c) => opened = c.id,
        onRetry: () {},
        emptyTitle: ExWork.noToday)));
    expect(find.byKey(const ValueKey('work-card-w1')), findsOneWidget);
    expect(find.text('Έλεγχος εκτυπωτή'), findsOneWidget);
    expect(find.text('Alpha ΕΠΕ · Κεντρικό'), findsOneWidget);
    expect(find.text('Προς έλεγχο'), findsOneWidget);
    expect(find.text(ExWork.pendingDecision), findsOneWidget);
    expect(find.text('Ενημερώθηκε 01/07/2026 13:05'), findsOneWidget);
    expect(find.text('Έλεγχος και ολοκλήρωση'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('work-card-w1')));
    expect(opened, 'w1');
  });

  testWidgets('empty, loading, error and offline states', (tester) async {
    Future<void> show(OfficeFeed<OfficeWorkCard> feed) => tester.pumpWidget(host(OfficeWorkFeedPanel(
        feed: feed, pendingWorkIds: const {}, onOpen: (_) {}, onRetry: () {}, emptyTitle: ExWork.noToday)));
    await show(const OfficeFeed(state: OfficeLoad.ready));
    expect(find.text(ExWork.noToday), findsOneWidget);
    await show(const OfficeFeed(state: OfficeLoad.loading));
    expect(find.byKey(const ValueKey('office-feed-loading')), findsOneWidget);
    await show(const OfficeFeed(state: OfficeLoad.error, error: 'Σφάλμα Office', offline: true));
    expect(find.text('Σφάλμα Office'), findsOneWidget);
    expect(find.text('Χωρίς σύνδεση στο διαδίκτυο'), findsOneWidget);
    expect(find.byKey(const ValueKey('office-feed-retry')), findsOneWidget);
  });

  test('stale customer search and reset discard late responses', () async {
    final pending = <String, Completer<Map<String, dynamic>>>{};
    final office = ExantasOfficeWork((path) {
      final c = Completer<Map<String, dynamic>>();
      pending[Uri.decodeQueryComponent(path.split('search=').last)] = c;
      return c.future;
    });
    final slow = office.searchCustomers('al');
    final fast = office.searchCustomers('alpha');
    pending['alpha']!.complete({'items': [{'id': 'new', 'company_name': 'Alpha'}]});
    await fast;
    pending['al']!.complete({'items': [{'id': 'old', 'company_name': 'Al old'}]});
    await slow;
    expect(office.customers.items.single['id'], 'new');
    expect(office.customerQuery, 'alpha');

    final late = office.searchCustomers('beta');
    office.reset(); // account switch or logout
    pending['beta']!.complete({'items': [{'id': 'other-account'}]});
    await late;
    expect(office.customers.items, isEmpty);
    expect(office.customers.state, OfficeLoad.idle);
  });

  test('detail load discarded after identity change', () async {
    final c = Completer<Map<String, dynamic>>();
    final office = ExantasOfficeWork((_) => c.future);
    final f = office.loadDetail('w1');
    office.reset();
    c.complete(context());
    expect(await f, isNull);
  });

  test('403 work_participant_required becomes a clear Greek message', () {
    final body = jsonEncode({'status': 'work_participant_required', 'message': 'Join the authorized work item before changing it.'});
    expect(
        () => decodeExantasOfficeResponse(403, body, androidSupport: true),
        throwsA(predicate((e) => e.toString().contains('Δεν συμμετέχετε σε αυτή την εργασία'))));
    expect(describeOfficeError(Exception('Δεν συμμετέχετε')), 'Δεν συμμετέχετε');
  });

  testWidgets('detail page shows 403 message without crashing and offers retry', (tester) async {
    final office = ExantasOfficeWork((_) async => throw Exception('Δεν συμμετέχετε σε αυτή την εργασία.'));
    await tester.pumpWidget(MaterialApp(
        theme: ExantasTheme.light(),
        home: OfficeWorkDetailPage(
            card: OfficeWorkCard.fromDayRow(dayRow('w1', 'draft'))!,
            office: office,
            onConnect: (_, __) async {})));
    await tester.pumpAndSettle();
    expect(find.text('Δεν συμμετέχετε σε αυτή την εργασία.'), findsOneWidget);
    expect(find.byKey(const ValueKey('work-detail-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('timeline: verified vs unverified, multiple sessions separate', () {
    final d = WorkDetail.parse(context(sessions: [
      session('s2', verified: false, start: '2026-10-30T11:00:00Z', end: '2026-10-30T11:05:00Z'),
      session('s1'),
    ]));
    expect(d.timeline.map((e) => e.id), ['k1', 's1', 's2']);
    expect(d.timeline[1].verified, isTrue);
    expect(d.timeline[1].durationSeconds, 750);
    expect(d.timeline[2].verified, isFalse);
    expect(d.timeline[2].durationSeconds, isNull);
    expect(d.timeline[1].computer, 'Ταμείο (123456789)');
    expect(d.canEdit, isTrue);
  });

  testWidgets('timeline widget: separate cards, duration only when verified', (tester) async {
    final d = WorkDetail.parse(context(sessions: [
      session('s1'),
      session('s2', verified: false, start: '2026-10-30T11:00:00Z', end: '2026-10-30T11:05:00Z'),
    ]));
    await tester.pumpWidget(host(WorkTimeline(d.timeline)));
    expect(find.byKey(const ValueKey('timeline-session-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-session-s2')), findsOneWidget);
    expect(find.text('30/10/2026'), findsNWidgets(3));
    expect(find.text('12:00 – 12:12'), findsOneWidget);
    expect(find.text('Διάρκεια 12 λ 30 δ'), findsOneWidget);
    expect(find.text(ExWork.unverified), findsOneWidget);
    expect(find.text('Τεχνικός: Μαρία Τεχνικός'), findsNWidgets(2));
    expect(find.text('Εισερχόμενη κλήση · 2101234567'), findsOneWidget);
  });

  testWidgets('detail page: sections and connect only for connectable device', (tester) async {
    final office = ExantasOfficeWork((_) async => context(sessions: [session('s1')]));
    String? connected;
    await tester.pumpWidget(MaterialApp(
        theme: ExantasTheme.light(),
        home: OfficeWorkDetailPage(
            card: OfficeWorkCard.fromDayRow(dayRow('w1', 'draft'))!,
            office: office,
            onConnect: (w, d) async => connected = '${w.id}:${d.peerId}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('work-tab-computers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('work-device-d2')));
    await tester.pump();
    expect(connected, isNull);
    expect(find.textContaining(ExWork.cannotConnect), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('work-device-d1')));
    await tester.pumpAndSettle();
    expect(connected, 'w1:123456789');
    await tester.tap(find.byKey(const ValueKey('work-tab-timeline')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-session-s1')), findsOneWidget);
  });

  testWidgets('customer search is debounced', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    await tester.pumpWidget(host(OfficeCustomersPanel(
        controller: controller,
        feed: const OfficeFeed(state: OfficeLoad.ready, items: [
          {'id': 'c1', 'company_name': 'Alpha ΕΠΕ', 'afm': '123456789'}
        ]),
        onSearch: queries.add,
        onOpen: (_) {})));
    expect(find.text('Alpha ΕΠΕ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, ['al']);
  });

  test('customer detail loads devices and open work for that customer', () async {
    final paths = <String>[];
    final office = ExantasOfficeWork((path) async {
      paths.add(path);
      if (path.contains('/devices')) {
        return {'items': [{'id': 'cd1', 'peer_id': '111', 'label': 'PC'}]};
      }
      return {'items': [
        {'id': 'w1', 'title': 'A', 'support_state': 'draft', 'customer_id': 'c1', 'customer_name': 'Alpha'},
        {'id': 'w2', 'title': 'B', 'support_state': 'finalized', 'customer_id': 'c1'},
      ]};
    });
    final d = await office.loadCustomer('c1');
    expect(d!.devices.single['peer_id'], '111');
    expect(d.works.map((w) => w.id), ['w1']);
    expect(paths, ['/rustdesk-reports/customers/c1/devices', '/support-workflow/items?customer_id=c1']);
  });

  test('is_participant: absent keeps true, false marks read-only', () {
    OfficeWorkCard c(Map<String, dynamic> extra) =>
        OfficeWorkCard.fromFlat({'id': 'w1', 'title': 'T', ...extra})!;
    expect(c({}).isParticipant, isTrue);
    expect(c({'is_participant': true}).isParticipant, isTrue);
    expect(c({'is_participant': false}).isParticipant, isFalse);
  });

  testWidgets('non-participant tile is muted, labelled and not tappable',
      (tester) async {
    var taps = 0;
    final card = OfficeWorkCard.fromFlat(
        {'id': 'w2', 'title': 'Ξένη', 'is_participant': false})!;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [ExantasTokens.light]),
        home: Scaffold(
            body: OfficeWorkCardTile(card: card, onTap: () => taps++))));
    expect(find.text('Άλλου τεχνικού'), findsOneWidget);
    expect(find.text('Ζήτα από τον υπεύθυνο να σε προσθέσει στην εργασία'),
        findsOneWidget);
    await tester.tap(find.text('Ξένη'));
    expect(taps, 0);
  });
}
