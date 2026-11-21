import 'dart:convert';
import 'dart:io';

import 'exantas_field_visit.dart';

/// Encrypted offline store: one JSON file per visit (`{visit_id}.json`), written
/// to a temporary file and renamed (like `ExantasLifecycleOutbox._save`).
/// Photo bytes live encrypted in `{visit_id}/{photo_id}.photo`.
/// The codec is injected: production passes `ExantasSecureStore`
/// (Android Keystore), tests pass an identity or reversible fake.
class ExantasFieldVisitStore {
  ExantasFieldVisitStore(
      {required this.directory, required this.protect, required this.unprotect});

  final Future<Directory> Function() directory;
  final Future<String> Function(String plain) protect;
  final Future<String> Function(String stored) unprotect;

  /// File names that could not be read or decoded. Never deleted: the owner
  /// can still recover them, and a later save of the same visit replaces them.
  final List<String> corrupt = [];

  static final _name = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');

  Future<Directory> _dir() async {
    final d = await directory();
    if (d.existsSync()) return d;
    return d.create(recursive: true);
  }

  static void _checkId(String id) {
    if (!fvIsUuid(id)) throw StateError('Μη έγκυρο αναγνωριστικό επίσκεψης.');
  }

  Future<void> _atomicWrite(File target, String text) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
  }

  /// Every readable visit. Corrupt/foreign files are skipped, never fatal.
  Future<List<FieldVisit>> loadAll() async {
    final dir = await _dir();
    corrupt.clear();
    final out = <FieldVisit>[];
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final base = entry.uri.pathSegments.last;
      if (!base.endsWith('.json') || base.startsWith('_')) {
        if (base.endsWith('.tmp')) {
          // A crash between write and rename: the old file (if any) is intact.
        }
        continue;
      }
      try {
        final visit = FieldVisit.decode(await unprotect(await entry.readAsString()));
        if (visit == null || '${visit.id}.json' != base) {
          corrupt.add(base);
        } else {
          out.add(visit);
        }
      } catch (_) {
        corrupt.add(base);
      }
    }
    return out;
  }

  Future<void> save(FieldVisit visit) async {
    _checkId(visit.id);
    final dir = await _dir();
    await _atomicWrite(File('${dir.path}/${visit.id}.json'), await protect(visit.encode()));
  }

  Future<void> delete(String visitId) async {
    _checkId(visitId);
    final dir = await _dir();
    final f = File('${dir.path}/$visitId.json');
    if (f.existsSync()) await f.delete();
    final files = Directory('${dir.path}/$visitId');
    if (files.existsSync()) await files.delete(recursive: true);
  }

  Future<void> writeBinary(String visitId, String name, List<int> bytes) async {
    _checkId(visitId);
    if (!_name.hasMatch(name)) throw StateError('Μη έγκυρο όνομα αρχείου.');
    final dir = await _dir();
    final sub = Directory('${dir.path}/$visitId');
    if (!sub.existsSync()) await sub.create(recursive: true);
    await _atomicWrite(File('${sub.path}/$name.photo'), await protect(base64Encode(bytes)));
  }

  Future<List<int>?> readBinary(String visitId, String name) async {
    _checkId(visitId);
    if (!_name.hasMatch(name)) return null;
    final dir = await _dir();
    final f = File('${dir.path}/$visitId/$name.photo');
    if (!f.existsSync()) return null;
    try {
      return base64Decode(await unprotect(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// Small keyed document (config cache, pull cursor), same encryption.
  Future<Map<String, dynamic>?> readMeta(String name) async {
    if (!_name.hasMatch(name)) return null;
    final f = File('${(await _dir()).path}/_$name.json');
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(await unprotect(await f.readAsString()));
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMeta(String name, Map<String, dynamic> value) async {
    if (!_name.hasMatch(name)) throw StateError('Μη έγκυρο όνομα.');
    final f = File('${(await _dir()).path}/_$name.json');
    await _atomicWrite(f, await protect(jsonEncode(value)));
  }
}

/// A visit belongs to the current Office session only when owner and API match
/// (same rule as `belongsToExantasOfficeScope`).
bool fvBelongsToScope(FieldVisit v, String owner, String api) =>
    owner.isNotEmpty && v.owner == owner && v.api == api;
