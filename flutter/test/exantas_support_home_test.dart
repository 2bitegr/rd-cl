import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_hbb/mobile/widgets/exantas_support_home_sections.dart';

ThemeData themed(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ExantasTheme.dark()
      : ExantasTheme.light();
  final font = Platform.environment['EXANTAS_UI_FONT'];
  return font == null
      ? base
      : base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'ExantasUiTest'));
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['EXANTAS_UI_FONT'];
    if (font != null) {
      final loader = FontLoader('ExantasUiTest')
        ..addFont(
            File(font).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      final icons = Platform.environment['EXANTAS_MATERIAL_ICONS'];
      if (icons != null) {
        final iconLoader = FontLoader('MaterialIcons')
          ..addFont(
              File(icons).readAsBytes().then((b) => ByteData.sublistView(b)));
        await iconLoader.load();
      }
    }
  });
  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(430, 932)
  ]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
          'mobile support sections and recent reconnect at ${size.width} $brightness',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? connected;
        var copied = false;
        var account = false;
        var openedPending = false;
        String? searched;
        final search = TextEditingController();
        addTearDown(search.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: themed(brightness),
                home: MediaQuery(
                    data: MediaQueryData(
                        size: size,
                        textScaler:
                            TextScaler.linear(size.width == 320 ? 1.3 : 1)),
                    child: Scaffold(
                        appBar: AppBar(
                            centerTitle: true,
                            title: const Text('Exantas Support')),
                        body: ExantasSupportHome(
                            account: ExantasAccountSummary(
                                name: 'Τεχνικός υποστήριξης δοκιμής',
                                nativeRecoveryRequired: false,
                                sourceId: '123456789',
                                onAccount: () {
                                  account = true;
                                },
                                onCopyId: () {
                                  copied = true;
                                }),
                            signedIn: true,
                            nativeRecoveryRequired: false,
                            busy: false,
                            controller: controller,
                            devices: const [
                              ExantasRecentDevice(
                                  id: '987654321',
                                  label: 'Υπολογιστής γραφείου · Δοκιμή',
                                  platform: 'Windows',
                                  online: true)
                            ],
                            searchController: search,
                            pendingCount: 2,
                            onConnect: (id) {
                              connected = id;
                            },
                            onSearchCustomers: (v) {
                              searched = v;
                            },
                            onOpenPending: () {
                              openedPending = true;
                            },
                            onRefresh: () {},
                            onConfirmNative: () {}))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Το ID μου: 123456789'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('support-native-retry')), findsNothing);
        expect(find.text('Συνδεδεμένος στο Office'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('support-copy-id')));
        expect(copied, true);
        expect(account, false);
        await tester.enterText(
            find.byKey(const ValueKey('support-connect-field')), '555666777');
        await tester.ensureVisible(
            find.byKey(const ValueKey('support-connect-button')));
        await tester.tap(find.byKey(const ValueKey('support-connect-button')));
        expect(connected, '555666777');
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('recent-987654321')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('recent-987654321')));
        expect(connected, '987654321');
        await tester.enterText(
            find.byKey(const ValueKey('support-home-search')), 'Alpha');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        expect(searched, 'Alpha');
        await tester
            .ensureVisible(find.byKey(const ValueKey('support-pending-card')));
        await tester.tap(find.byKey(const ValueKey('support-pending-card')));
        expect(openedPending, true);
        expect(find.text('Εκκρεμή (2)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final out = Platform.environment['EXANTAS_UI_OUTPUT'];
        if (out != null && size.width == 390) {
          final scroll =
              tester.state<ScrollableState>(find.byType(Scrollable).first);
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(out).create(recursive: true);
            await File('$out/support-home-390-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  testWidgets(
      'busy state and signed-out state cannot reconnect from recent history',
      (tester) async {
    var calls = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Widget home(bool signedIn) => MaterialApp(
        home: Scaffold(
            body: ExantasSupportHome(
                account: const Text('Office'),
                signedIn: signedIn,
                nativeRecoveryRequired: false,
                busy: true,
                controller: controller,
                devices: const [
                  ExantasRecentDevice(
                      id: '123456789',
                      label: 'PC',
                      platform: 'Linux',
                      online: false)
                ],
                searchController: TextEditingController(),
                pendingCount: 0,
                onConnect: (_) {
                  calls++;
                },
                onSearchCustomers: (_) {},
                onOpenPending: () {},
                onRefresh: () {},
                onConfirmNative: () {})));
    await tester.pumpWidget(home(true));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('support-connect-button')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('recent-123456789')))
            .onTap,
        isNull);
    expect(calls, 0);
    await tester.pumpWidget(home(false));
    expect(find.byKey(const ValueKey('support-connect-field')), findsNothing);
    expect(find.byKey(const ValueKey('recent-123456789')), findsNothing);
  });
  testWidgets(
      'only unconfirmed issuance shows a manual retry and never auto-retries',
      (tester) async {
    var retries = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Widget home(bool recovering, bool busy) => MaterialApp(
        home: Scaffold(
            body: ExantasSupportHome(
                account: const Text('Office'),
                signedIn: true,
                nativeRecoveryRequired: recovering,
                busy: busy,
                controller: controller,
                devices: const [],
                searchController: TextEditingController(),
                pendingCount: 0,
                onConnect: (_) {},
                onSearchCustomers: (_) {},
                onOpenPending: () {},
                onRefresh: () {},
                onConfirmNative: () {
                  retries++;
                })));
    await tester.pumpWidget(home(false, false));
    expect(find.byKey(const ValueKey('support-native-retry')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('support-connect-button')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(home(true, false));
    await tester.pump(const Duration(seconds: 10));
    expect(retries, 0);
    await tester.tap(find.byKey(const ValueKey('support-native-retry')));
    expect(retries, 1);
    await tester.pumpWidget(home(true, true));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('support-native-retry')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('work view switches Πελάτες and Εκκρεμή; signed-out is gated',
      (tester) async {
    var section = ExantasWorkSection.customers;
    Widget work(bool signedIn) => MaterialApp(
        theme: ExantasTheme.light(),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (ctx, set) => ExantasWorkView(
                    signedIn: signedIn,
                    busy: false,
                    section: section,
                    onSection: (v) => set(() => section = v),
                    customerPanel: const Text('Πάνελ πελατών'),
                    pendingPanel: const Text('Πάνελ αποφάσεων'),
                    pendingCount: 2,
                    onRefresh: () {}))));
    await tester.pumpWidget(work(true));
    expect(find.text('Πάνελ πελατών'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-tab-pending')));
    await tester.pumpAndSettle();
    expect(find.text('Πάνελ αποφάσεων'), findsOneWidget);
    expect(find.text('Πάνελ πελατών'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('support-tab-customers')));
    await tester.pumpAndSettle();
    expect(find.text('Πάνελ πελατών'), findsOneWidget);
    await tester.pumpWidget(work(false));
    expect(find.byKey(const ValueKey('support-tab-pending')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
