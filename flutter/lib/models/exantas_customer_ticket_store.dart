import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'exantas_customer_ticket.dart';

/// Two encrypted generations; no credential, description or original path is
/// written in clear text. Corruption fails closed instead of downgrading a nonce.
class ExantasTicketFileStore extends ExantasTicketStore {
  ExantasTicketFileStore(
      {required this.directory,
      required this.scope,
      required this.protect,
      required this.unprotect,
      required this.protectedPrefix});
  final Directory directory;
  final String scope, protectedPrefix;
  final Future<String> Function(String) protect, unprotect;
  static final Set<String> _open = {};
  RandomAccessFile? _lock;
  bool _locked = false;
  int _generation = 0;
  String? _canonical;

  Future<void> _ownedRegular(String path, {bool allowAbsent = true}) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        !(allowAbsent && type == FileSystemEntityType.notFound)) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
  }

  Future<void> _acquire() async {
    if (_lock != null) return;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    final type =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    await directory.create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    if (!p.equals(
        p.normalize(p.absolute(directory.path)), p.normalize(canonical))) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    if (!_open.add(canonical)) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    _canonical = canonical;
    try {
      final path = p.join(canonical, 'draft.lock');
      await _ownedRegular(path);
      _lock = await File(path).open(mode: FileMode.append);
      await _lock!.lock(FileLock.exclusive);
      _locked = true;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  String _slot(int slot) => p.join(_canonical!, 'draft.$slot.protected');

  @override
  Future<Map<String, dynamic>?> read() async {
    await _acquire();
    Map<String, dynamic>? result;
    var newest = 0;
    for (var index = 0; index < 2; index++) {
      final path = _slot(index);
      await _ownedRegular(path);
      final file = File(path);
      if (!await file.exists()) continue;
      if (await file.length() > 2000000) {
        throw const ExantasTicketFailure('ticket_local_storage');
      }
      final text = await file.readAsString();
      if (!text.startsWith(protectedPrefix)) {
        throw const ExantasTicketFailure('ticket_local_storage');
      }
      final envelope = ticketMap(jsonDecode(await unprotect(text)));
      final value = ticketMap(envelope['value']);
      final generation = envelope['generation'];
      if (generation is! int ||
          generation < 1 ||
          generation % 2 != index ||
          envelope['scope'] != scope ||
          value['scope'] != scope ||
          envelope['sha256'] !=
              sha256.convert(utf8.encode(jsonEncode(value))).toString()) {
        throw const ExantasTicketFailure('ticket_local_storage');
      }
      if (generation > newest) {
        newest = generation;
        result = value;
      }
    }
    if (newest > _generation) _generation = newest;
    return result;
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    await _acquire();
    if (value['scope'] != scope) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    final generation = _generation + 1;
    final plain = jsonEncode({
      'generation': generation,
      'scope': scope,
      'sha256': sha256.convert(utf8.encode(jsonEncode(value))).toString(),
      'value': value
    });
    if (utf8.encode(plain).length > 500000) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    final encrypted = await protect(plain);
    if (!encrypted.startsWith(protectedPrefix)) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    final path = _slot(generation % 2), temporary = '$path.tmp';
    await _ownedRegular(path);
    await _ownedRegular(temporary);
    final file = File(temporary);
    await file.writeAsString(encrypted, flush: true);
    await _ownedRegular(path);
    await file.rename(path);
    _generation = generation;
  }

  @override
  Future<void> close() async {
    final lock = _lock;
    _lock = null;
    try {
      if (lock != null) {
        try {
          if (_locked) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    } finally {
      _locked = false;
      if (_canonical != null) _open.remove(_canonical);
      _canonical = null;
    }
  }
}
