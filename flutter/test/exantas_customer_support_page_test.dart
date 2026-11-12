import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:flutter_hbb/desktop/pages/exantas_customer_support_page.dart';
import 'package:flutter_hbb/models/exantas_customer_ticket.dart';
import 'exantas_customer_ticket_test.dart' as fixture;

class UiTransport extends fixture.FakeTransport {
  bool closed = false;
  final publicReplies = <String, String>{};
  Map<String, dynamic> ticket() => {
        'id': fixture.ticketId,
        'reference': 'T-SYNTHETIC',
        'subject': 'Synthetic customer problem',
        'details': 'Synthetic problem description',
        'category': 'problem',
        'priority': 'normal',
        'status': closed ? 'resolved' : 'open',
        'revision': '1',
        'customer_name': 'Synthetic company',
        'created_at': '2026-11-12T10:00:00Z',
      };
  @override
  Future<Map<String, dynamic>> request(
      ExantasTicketIdentity identity, String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    if (method == 'GET' && path == '') {
      return {
        'status': 'ok',
        'items': created == null ? [] : [ticket()],
        'next_cursor': null
      };
    }
    if (method == 'GET' && path == '/${fixture.ticketId}') {
      return {
        'status': 'ok',
        'ticket': ticket(),
        'events': [
          {
            'id': 'event-1',
            'actor': 'customer',
            'type': 'created',
            'body': 'Synthetic problem description',
            'created_at': '2026-11-12T10:00:00Z'
          },
          ...publicReplies.values.map((text) => {
                'id': text,
                'actor': 'customer',
                'type': 'reply',
                'body': text,
                'created_at': '2026-11-12T10:01:00Z'
              })
        ],
        'events_next_cursor': null,
        'files': [],
        'reports': []
      };
    }
    final response =
        await super.request(identity, method, path, body: body, query: query);
    if (path.endsWith('/messages')) {
      publicReplies[body!['request_key']] = body['body'];
    }
    return response;
  }
}

Future<void> mount(
    WidgetTester tester, fixture.MemoryStore store, UiTransport transport,
    {Future<List<String>> Function()? pick,
    Future<String?> Function()? capture,
    Future<void> Function(String)? preview,
    Listenable? identityChanges,
    Future<ExantasTicketIdentity> Function()? current}) async {
  final client = fixture.client(store, transport, current: current);
  await tester.pumpWidget(MaterialApp(
      home: ExantasCustomerSupportPage(
          client: client,
          identityChanges: identityChanges,
          pickFiles: pick ?? (() async => []),
          captureScreenshot: capture ?? (() async => null),
          previewLocal: preview ?? ((_) async {}),
          openMedia: (_) async {})));
  await tester.pumpAndSettle();
}

Future<void> newForm(WidgetTester tester) async {
  await tester.tap(find.text('Νέο αίτημα'));
  await tester.pumpAndSettle();
  final subject = find.widgetWithText(TextFormField, 'Θέμα αιτήματος');
  await tester.ensureVisible(subject);
  await tester.enterText(subject, 'Synthetic issue');
  final description =
      find.widgetWithText(TextFormField, 'Περιγραφή προβλήματος');
  await tester.ensureVisible(description);
  await tester.enterText(description, 'Synthetic details for support');
}

Future<void> press(WidgetTester tester, String text) async {
  final button = find.text(text);
  await tester.ensureVisible(button);
  await tester.runAsync(() async {
    await tester.tap(button);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory media;
  late File screenshot, video;
  setUpAll(() async {
    media =
        await Directory.systemTemp.createTemp('office-ticket-widget-media-');
    screenshot = await File('${media.path}/screen.png')
        .writeAsBytes(image.encodePng(image.Image(width: 2, height: 2)));
    video = await File('${media.path}/problem.mp4').writeAsBytes([1, 2, 3]);
  });
  tearDownAll(() => media.delete(recursive: true));
  testWidgets(
      'customer submits without staff login; one click opens the form and one receipt closes the draft',
      (tester) async {
    final store = fixture.MemoryStore(), transport = UiTransport();
    await mount(tester, store, transport);
    expect(find.text('Email Office'), findsNothing);
    expect(find.text('Κωδικός Office'), findsNothing);
    await newForm(tester);
    await press(tester, 'Υποβολή αιτήματος');
    expect(transport.creates.length, 1);
    expect(transport.creates.single.containsKey('customer_id'), false);
    expect(transport.creates.single['expected_scope'],
        {'customer_id': fixture.customer, 'branch_id': null});
    expect(find.text('T-SYNTHETIC'), findsOneWidget);
    expect(store.value!['draft'], isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'lost ACK keeps the form frozen and offers exact create readback without another ticket',
      (tester) async {
    final store = fixture.MemoryStore(),
        transport = UiTransport()..lostCreate = true;
    await mount(tester, store, transport);
    await newForm(tester);
    await press(tester, 'Υποβολή αιτήματος');
    expect(find.text('Έλεγχος υποβολής'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Θέμα αιτήματος'))
            .enabled,
        false);
    await press(tester, 'Έλεγχος υποβολής');
    expect(transport.creates.length, 1);
    expect(find.text('T-SYNTHETIC'), findsOneWidget);
    expect(store.value!['draft'], isNull);
  });
  testWidgets(
      'explicit local draft survives page restart without network submission',
      (tester) async {
    final store = fixture.MemoryStore(), transport = UiTransport();
    await mount(tester, store, transport);
    await newForm(tester);
    await press(tester, 'Αποθήκευση τοπικού προχείρου');
    expect(transport.creates, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, store, transport);
    expect(find.text('Synthetic issue'), findsOneWidget);
    expect(find.text('Synthetic details for support'), findsOneWidget);
    expect(transport.creates, isEmpty);
  });
  testWidgets(
      'screenshot is never captured automatically and cancellation performs no capture or send',
      (tester) async {
    var captures = 0;
    final store = fixture.MemoryStore(), transport = UiTransport();
    await mount(tester, store, transport, capture: () async {
      captures++;
      return null;
    });
    expect(captures, 0);
    await newForm(tester);
    await press(tester, 'Νέο screenshot');
    expect(find.text('Screenshot κύριας οθόνης'), findsOneWidget);
    await press(tester, 'Άκυρο');
    expect(captures, 0);
    expect(transport.creates, isEmpty);
  });
  testWidgets(
      'confirmed screenshot has local preview and removal never deletes the original',
      (tester) async {
    final file = screenshot;
    var captures = 0;
    final store = fixture.MemoryStore(), transport = UiTransport();
    await mount(tester, store, transport, capture: () async {
      captures++;
      return file.path;
    });
    await newForm(tester);
    await press(tester, 'Νέο screenshot');
    await press(tester, 'Λήψη screenshot');
    expect(captures, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(transport.uploads, 0);
    expect(transport.creates, isEmpty);
    await press(tester, 'Αφαίρεση από το πρόχειρο');
    expect(await tester.runAsync(file.exists), true);
    expect(store.value!['draft']['files'], isEmpty);
  });
  testWidgets(
      'video selection offers explicit local-player preview without upload',
      (tester) async {
    final file = video;
    final previews = <String>[], transport = UiTransport();
    await mount(tester, fixture.MemoryStore(), transport,
        pick: () async => [file.path],
        preview: (path) async => previews.add(path));
    await newForm(tester);
    await press(tester, 'Επιλογή εικόνων ή βίντεο');
    await press(tester, 'Προεπισκόπηση στον τοπικό player');
    expect(previews, [file.path]);
    expect(transport.uploads, 0);
    expect(transport.creates, isEmpty);
    expect(await tester.runAsync(file.exists), true);
  });
  testWidgets(
      'reply ACK loss survives restart and pending-card retry reuses one immutable message key',
      (tester) async {
    final store = fixture.MemoryStore(),
        transport = UiTransport()
          ..created = {'id': fixture.ticketId}
          ..lostReply = true;
    await mount(tester, store, transport);
    await press(tester, 'Synthetic customer problem');
    final reply = find.widgetWithText(TextField, 'Νέα απάντηση');
    await tester.ensureVisible(reply);
    await tester.enterText(reply, 'Customer reply');
    await press(tester, 'Αποστολή απάντησης');
    expect(store.value!['reply']['body'], 'Customer reply');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, store, transport);
    await press(tester, 'Συνέχεια εκκρεμούς απάντησης');
    expect(store.value!['reply'], isNull);
    expect(transport.replies.length, 2);
    expect(transport.replies[0], transport.replies[1]);
  });
  testWidgets(
      'closed ticket keeps its public history without reply or attachment controls',
      (tester) async {
    final transport = UiTransport()
      ..created = {'id': fixture.ticketId}
      ..closed = true;
    await mount(tester, fixture.MemoryStore(), transport);
    await press(tester, 'Synthetic customer problem');
    expect(find.text('Το αίτημα έκλεισε. Το ιστορικό παραμένει διαθέσιμο.'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Νέα απάντηση'), findsNothing);
    expect(find.text('Επιλογή εικόνων ή βίντεο'), findsNothing);
  });
  testWidgets(
      'account change hides old customer history and preserves protected state',
      (tester) async {
    var active = fixture.identity();
    final changes = ValueNotifier<int>(0);
    final store = fixture.MemoryStore(),
        transport = UiTransport()..created = {'id': fixture.ticketId};
    await mount(tester, store, transport,
        identityChanges: changes, current: () async => active);
    await press(tester, 'Synthetic customer problem');
    expect(find.text('Synthetic problem description'), findsWidgets);
    final saved = store.value;
    active = fixture.identity('another-synthetic-credential');
    changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('Synthetic customer problem'), findsNothing);
    expect(find.text('Synthetic problem description'), findsNothing);
    expect(store.value, saved);
    expect(transport.creates, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    changes.dispose();
  });
  testWidgets(
      'explicitly stopping pending uploads keeps submitted ticket and local originals',
      (tester) async {
    final store = fixture.MemoryStore(), transport = UiTransport();
    await tester.runAsync(() async {
      final c = fixture.client(store, transport);
      await c.refreshCapabilities();
      await c
          .saveDraft(fixture.input, [await inspectTicketFile(screenshot.path)]);
      await c.submit();
      await c.dispose();
    });
    await mount(tester, store, transport);
    await press(tester, 'Διακοπή εκκρεμών μεταφορτώσεων');
    await press(tester, 'Διακοπή μεταφορτώσεων');
    expect(store.value!['draft'], isNull);
    expect(transport.creates.length, 1);
    expect(await tester.runAsync(screenshot.exists), true);
    expect(find.text('Synthetic customer problem'), findsWidgets);
  });
  testWidgets('narrow window keeps create controls usable without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, fixture.MemoryStore(), UiTransport());
    await newForm(tester);
    await tester.ensureVisible(find.text('Υποβολή αιτήματος'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
