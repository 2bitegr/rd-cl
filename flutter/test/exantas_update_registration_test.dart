import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_update_registration.dart';

class FixtureProcess implements Process {
  FixtureProcess({int? result = 0}) {
    input.stream.listen(bytes.addAll);
    if (result != null) done.complete(result);
  }
  final input = StreamController<List<int>>();
  final bytes = <int>[];
  final done = Completer<int>();
  late final IOSink _stdin = IOSink(input.sink);
  int killed = 0;
  @override IOSink get stdin => _stdin;
  @override Stream<List<int>> get stdout => const Stream.empty();
  @override Stream<List<int>> get stderr => const Stream.empty();
  @override Future<int> get exitCode => done.future;
  @override int get pid => 1;
  @override bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed++; if (!done.isCompleted) done.complete(1); return true;
  }
}

void main() {
  const request = {'device_id':'11111111-1111-4111-8111-111111111111','peer_id':'1234567890','device_token':'rdev_synthetic_only'};
  test('ineligible/portable/technician context never starts a process', () async {
    expect(await registerRdclUpdater(eligible:false,executable:'fixture.exe',request:request,
      start:(_, __) async => throw StateError('must not start')), false);
  });
  test('one bootstrap sends the credential through stdin and drains both pipes', () async {
    final process = FixtureProcess();
    var starts = 0;
    final result = await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:request,
      start:(exe, args) async { starts++; expect(exe,'fixture.exe'); expect(args,['--office-update-register']); return process; });
    expect(result,true); expect(starts,1); expect(jsonDecode(utf8.decode(process.bytes)),request); expect(process.killed,0);
  });
  test('rejected registration cannot report success', () async {
    expect(await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:request,
      start:(_, __) async => FixtureProcess(result:1)),false);
  });
  test('timeout kills only the owned bootstrap process and does not retry', () async {
    final process = FixtureProcess(result:null);
    var starts=0;
    expect(await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:request,
      timeout:const Duration(milliseconds:20),start:(_, __) async {starts++;return process;}),false);
    expect(starts,1);expect(process.killed,1);
  });
  test('a process arriving after timeout is killed before receiving credentials', () async {
    final pending=Completer<Process>();final process=FixtureProcess();
    expect(await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:request,
      timeout:const Duration(milliseconds:20),start:(_, __)=>pending.future),false);
    pending.complete(process);await Future<void>.delayed(Duration.zero);
    expect(process.killed,1);expect(process.bytes,isEmpty);await process.input.close();
  });
  test('oversized requests are rejected before process creation', () async {
    expect(await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:{'device_token':'x'*5000},
      start:(_, __) async => throw StateError('must not start')),false);
  });
  test('a process creation failure is isolated from normal customer work', () async {
    expect(await registerRdclUpdater(eligible:true,executable:'fixture.exe',request:request,
      start:(_, __) async => throw const ProcessException('fixture.exe',[], 'synthetic failure')),false);
  });
}
