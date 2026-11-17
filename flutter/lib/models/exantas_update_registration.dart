import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef UpdateProcessStarter = Future<Process> Function(String, List<String>);

/// The installed service independently verifies Office authority. Secrets travel
/// only through stdin, never command-line arguments, files or diagnostic output.
Future<bool> registerRdclUpdater({required bool eligible, required String executable,
  required Map<String, String> request, UpdateProcessStarter start = Process.start,
  Duration timeout = const Duration(seconds: 40)}) async {
  if (!eligible || executable.isEmpty) return false;
  final body = jsonEncode(request);
  if (utf8.encode(body).length > 4096) return false;
  Process? child;
  var expired = false;
  Future<bool> exchange() async {
    try {
      final process = await start(executable, ['--office-update-register']);
      child = process;
      if (expired) { process.kill(); return false; }
      process.stdin.write(body);
      await process.stdin.close();
      final exit = process.exitCode;
      await Future.wait<void>([process.stdout.drain<void>(), process.stderr.drain<void>(), exit.then<void>((_) {})]);
      return await exit == 0;
    } catch (_) { child?.kill(); return false; }
  }
  return exchange().timeout(timeout, onTimeout: () {
    expired = true; child?.kill(); return false;
  });
}
