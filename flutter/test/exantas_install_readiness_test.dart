import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/install_readiness.dart';
import 'package:flutter_hbb/models/exantas_install_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> evidence({String service = 'service_running', String office = 'ready'}) => {
  'schema': 1, 'checked_at': DateTime.now().toUtc().toIso8601String(),
  'installed_version': '3.2.11', 'repair_fingerprint': 'a' * 64,
  'repair_target': r'C:\Program Files\Exantas Support\Exantas Support.exe',
  'checks': [for (final code in ['windows_x64', 'exe_installation', 'minimum_space', 'restart_clear',
    'installation_protected', service, 'service_automatic', 'runtime_idle', 'runtime_identity', 'runtime_installation'])
    {'code': code, 'status': code == 'service_stopped' ? 'blocked' : 'ok',
      'action': code == 'service_stopped' ? 'start_service' : null}],
  'office': {'schema': 1, 'state': office, 'checked_at': DateTime.now().toUtc().toIso8601String(), 'reasons': office == 'ready' ? <String>[] : ['pilot_pending'], 'target_version': '3.2.11'},
};

void main() {
  test('ready requires all local proofs, live Office confirmation and versions', () {
    expect(InstallReadinessReport.decode(jsonEncode(evidence())).ready, isTrue);
    for (final code in ['windows_x64', 'exe_installation', 'minimum_space', 'restart_clear',
      'installation_protected', 'service_running', 'service_automatic', 'runtime_idle', 'runtime_identity', 'runtime_installation']) {
      final report = evidence();
      (report['checks'] as List).removeWhere((c) => c['code'] == code);
      expect(InstallReadinessReport.decode(jsonEncode(report)).ready, isFalse, reason: code);
    }
    expect(InstallReadinessReport.decode(jsonEncode(evidence(office: 'waiting'))).ready, isFalse);
    final noOffice = evidence()..remove('office');
    expect(InstallReadinessReport.decode(jsonEncode(noOffice)).ready, isFalse);
    final noVersion = evidence()..remove('installed_version');
    expect(InstallReadinessReport.decode(jsonEncode(noVersion)).ready, isFalse);
    final clock = evidence();
    (clock['office'] as Map)['checked_at'] = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    expect(InstallReadinessReport.decode(jsonEncode(clock)).officeReasons, contains('clock_unconfirmed'));
  });
  test('partial, stale, future, malformed and unknown-schema diagnostics fail closed', () {
    for (final raw in [[], {}, {...evidence(), 'schema': 2}, {...evidence(), 'checks': []},
      {...evidence(), 'checked_at': DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String()},
      {...evidence(), 'checked_at': DateTime.now().add(const Duration(minutes: 3)).toIso8601String()},
      {...evidence(), 'checks': [{'code': 'service_running', 'status': 'invented'}]}]) {
      expect(() => InstallReadinessReport.decode(jsonEncode(raw)), throwsFormatException);
    }
  });
  test('pending reboot, missing installation and MSI are distinct from ready', () {
    for (final status in ['blocked', 'pending', 'unsupported', 'unknown']) {
      final raw = evidence();
      (raw['checks'] as List).add({'code': 'pending_file_operations', 'status': status});
      final report = InstallReadinessReport.decode(jsonEncode(raw));
      expect(report.ready, isFalse);
      expect(report.unsupported, status == 'unsupported');
    }
  });
  test('repair runner accepts only closed actions and exact confirmation fingerprints', () async {
    var calls = 0;
    final client = InstallReadinessClient(runner: (_) async { calls++; return '{"schema":1,"applied":true}'; });
    await expectLater(client.repair('delete_registry', 'a' * 64), throwsArgumentError);
    await expectLater(client.repair('start_service', 'bad'), throwsArgumentError);
    expect(calls, 0);
    await client.repair('start_service', 'a' * 64);
    expect(calls, 1);
    final refused = InstallReadinessClient(runner: (_) async => '{"schema":1,"applied":false}');
    await expectLater(refused.repair('automatic_service', 'a' * 64), throwsFormatException);
  });
  testWidgets('installer shows evidence and confirmation cancellation executes no repair', (tester) async {
    final calls = <List<String>>[];
    final client = InstallReadinessClient(runner: (args) async { calls.add(args); return jsonEncode(evidence(service: 'service_stopped')); });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstallReadinessPanel(target: r'C:\Program Files\Exantas Support', client: client)))));
    await tester.pumpAndSettle();
    expect(find.text('Υπάρχουν τοπικά εμπόδια'), findsOneWidget);
    await tester.ensureVisible(find.text('Εκκίνηση υπηρεσίας'));
    await tester.tap(find.text('Εκκίνηση υπηρεσίας')); await tester.pumpAndSettle();
    expect(find.textContaining('δικαιώματα διαχειριστή'), findsOneWidget);
    expect(calls.where((c) => c.first == '--office-install-repair'), isEmpty);
    await tester.tap(find.text('Ακύρωση')); await tester.pumpAndSettle();
    expect(calls.where((c) => c.first == '--office-install-repair'), isEmpty);
  });
  testWidgets('approved repair uses the displayed fingerprint and rechecks before success', (tester) async {
    var repaired = false;
    final calls = <List<String>>[];
    final client = InstallReadinessClient(runner: (args) async {
      calls.add(args);
      if (args.first == '--office-install-repair') { repaired = true; return '{"schema":1,"applied":true}'; }
      return jsonEncode(evidence(service: repaired ? 'service_running' : 'service_stopped'));
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstallReadinessPanel(target: r'C:\Program Files\Exantas Support', client: client)))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Εκκίνηση υπηρεσίας'));
    await tester.tap(find.text('Εκκίνηση υπηρεσίας')); await tester.pumpAndSettle();
    await tester.tap(find.text('Επιβεβαίωση')); await tester.pumpAndSettle();
    expect(calls.where((c) => c.first == '--office-install-repair').single,
        ['--office-install-repair', 'start_service', 'a' * 64]);
    expect(calls.last.first, '--office-install-readiness');
    expect(find.text('Έτοιμος για αυτόματες ενημερώσεις'), findsOneWidget);
  });
  testWidgets('late results for a previous installation path cannot replace current evidence', (tester) async {
    final old = Completer<String>();
    final client = InstallReadinessClient(runner: (args) => args.last == 'old' ? old.future : Future.value(jsonEncode(evidence(service: 'service_stopped'))));
    Widget app(String target) => MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstallReadinessPanel(key: const ValueKey('check'), target: target, client: client))));
    await tester.pumpWidget(app('old')); await tester.pump();
    await tester.pumpWidget(app('new')); await tester.pumpAndSettle();
    old.complete(jsonEncode(evidence())); await tester.pumpAndSettle();
    expect(find.text('Υπάρχουν τοπικά εμπόδια'), findsOneWidget);
    expect(find.text('Έτοιμος για αυτόματες ενημερώσεις'), findsNothing);
  });
}
