import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/ex_app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime clock;
  late bool enabled;
  late List<ExAuthResult> results;
  late int prompts;
  late ExAppLockController c;

  setUp(() {
    clock = DateTime(2026, 1, 1, 12);
    enabled = true;
    results = [ExAuthResult.success];
    prompts = 0;
    c = ExAppLockController(
        isEnabled: () => enabled,
        now: () => clock,
        authenticate: () async {
          prompts++;
          return results.length > 1 ? results.removeAt(0) : results.first;
        });
  });

  test('disabled by default: never locks, never prompts', () async {
    enabled = false;
    final d = ExAppLockController(
        isEnabled: () => enabled,
        authenticate: () async {
          prompts++;
          return ExAuthResult.success;
        });
    expect(d.locked.value, false);
    await d.start();
    d.didChangeAppLifecycleState(AppLifecycleState.paused);
    d.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(prompts, 0);
    expect(d.locked.value, false);
  });

  test('cold start locks until success', () async {
    expect(c.locked.value, true);
    await c.start();
    expect(prompts, 1);
    expect(c.locked.value, false);
  });

  test('failure keeps the lock and retry can succeed', () async {
    results = [ExAuthResult.failed, ExAuthResult.success];
    await c.start();
    expect(c.locked.value, true);
    expect(c.lastFailure.value, ExAuthResult.failed);
    await c.unlock();
    expect(c.locked.value, false);
    expect(c.lastFailure.value, isNull);
  });

  test('exception fails closed; unavailable device opens', () async {
    final e = ExAppLockController(
        isEnabled: () => true, authenticate: () async => throw StateError('x'));
    await e.start();
    expect(e.locked.value, true);
    final u = ExAppLockController(
        isEnabled: () => true,
        authenticate: () async => ExAuthResult.unavailable);
    await u.start();
    expect(u.locked.value, false);
  });

  test('resume after under 5 min does not lock; at 5 min does', () async {
    await c.start();
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock = clock.add(const Duration(minutes: 4, seconds: 59));
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(c.locked.value, false);
    expect(prompts, 1);

    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock = clock.add(const Duration(minutes: 5));
    results = [ExAuthResult.failed];
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 2);
    expect(c.locked.value, true);
  });

  test('hidden then paused keeps the first background timestamp', () async {
    await c.start();
    c.didChangeAppLifecycleState(AppLifecycleState.hidden);
    clock = clock.add(const Duration(minutes: 3));
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock = clock.add(const Duration(minutes: 3));
    results = [ExAuthResult.failed];
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(c.locked.value, true);
  });

  test('Back is consumed only while locked', () async {
    expect(await c.didPopRoute(), true);
    await c.start();
    expect(await c.didPopRoute(), false);
  });

  testWidgets('gate covers child, retry unlocks, child stays mounted',
      (tester) async {
    results = [ExAuthResult.failed, ExAuthResult.success];
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
        home: ExAppLockGate(
            controller: c,
            child: Builder(builder: (_) {
              builds++;
              return const Text('secret');
            }))));
    await tester.pump();
    expect(find.byKey(const ValueKey('ex-lock-screen')), findsOneWidget);
    expect(find.text('Η εφαρμογή είναι κλειδωμένη'), findsOneWidget);
    expect(find.text('Η επαλήθευση δεν ολοκληρώθηκε. Δοκίμασε ξανά.'),
        findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('ex-lock-retry'))).height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey('ex-lock-retry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ex-lock-screen')), findsNothing);
    expect(find.text('secret'), findsOneWidget);
    expect(builds, greaterThan(0));
  });
}
