import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final ticketUuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    caseSensitive: false);
const ticketCategories = {
  'question': 'Ερώτηση',
  'problem': 'Πρόβλημα / σφάλμα',
  'urgent': 'Επείγουσα ανάγκη',
  'install_device': 'Εγκατάσταση / ρύθμιση',
};
const ticketPriorities = {
  'low': 'Χαμηλή',
  'normal': 'Κανονική',
  'high': 'Υψηλή',
};
const ticketStates = {
  'open': 'Ανοιχτό',
  'in_progress': 'Σε εξέλιξη',
  'resolved': 'Ολοκληρωμένο',
  'dismissed': 'Κλειστό χωρίς εργασία',
};
const ticketMedia = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};

Map<String, dynamic> ticketMap(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid ticket response.');
  return Map<String, dynamic>.from(value);
}

class ExantasTicketFailure implements Exception {
  const ExantasTicketFailure(this.code, {this.status});
  final String code;
  final int? status;
  bool get definitive => status != null && status! >= 400 && status! < 500;
  @override
  String toString() => ticketFailureMessage(this);
}

String ticketFailureMessage(Object error) {
  if (error is ExantasTicketFailure) {
    if (error.status == 401 || error.status == 403) {
      return 'Η πρόσβαση του υπολογιστή άλλαξε. Το πρόχειρο διατηρείται. Ελέγξτε τη σύνδεση με την υποστήριξη.';
    }
    const messages = {
      'customer_tickets_unavailable':
          'Τα αιτήματα υποστήριξης δεν είναι ακόμη διαθέσιμα.',
      'ticket_identity_changed':
          'Η σύνδεση του υπολογιστή άλλαξε. Το προστατευμένο πρόχειρο διατηρείται χωριστά.',
      'ticket_device_scope_changed':
          'Η επιχείρηση ή η εγκατάσταση άλλαξε. Το παλιό πρόχειρο δεν μεταφέρθηκε στον νέο πελάτη.',
      'ticket_not_found': 'Το αίτημα δεν βρέθηκε ή δεν επιτρέπεται η πρόσβαση.',
      'ticket_closed':
          'Το αίτημα έχει κλείσει. Η υποστήριξη πρέπει να το ανοίξει ξανά πριν από νέα απάντηση.',
      'ticket_pending_create':
          'Εκκρεμεί επιβεβαίωση υποβολής. Ελέγξτε ή επαναλάβετε την ίδια υποβολή.',
      'ticket_pending_reply':
          'Εκκρεμεί απάντηση. Συνεχίστε την ίδια ενέργεια από το αντίστοιχο αίτημα.',
      'ticket_pending_files':
          'Υπάρχουν εκκρεμή συνημμένα σε άλλο αίτημα. Συνεχίστε πρώτα εκεί.',
      'ticket_file_changed':
          'Το αρχείο άλλαξε ή δεν είναι διαθέσιμο. Επιλέξτε ξανά το αρχικό αρχείο.',
      'ticket_file_limit':
          'Επιτρέπονται έως 5 αρχεία και 200 MB συνολικά ανά αίτημα.',
      'invalid_ticket_upload':
          'Επιλέξτε PNG/JPEG έως 10 MB ή MP4/WebM έως 50 MB.',
      'ticket_upload_expired':
          'Έληξε το παράθυρο μεταφοράς. Το αίτημα και το αρχικό αρχείο διατηρούνται.',
      'ticket_file_expired':
          'Το συνημμένο δεν είναι πλέον διαθέσιμο ή έληξε ο χρόνος διατήρησής του.',
      'ticket_file_hash_mismatch':
          'Το αρχείο διαφέρει από το αρχικό. Δεν επισυνάφθηκε.',
      'ticket_private_storage_required':
          'Ο ιδιωτικός χώρος αρχείων δεν είναι ακόμη έτοιμος. Το αίτημα διατηρείται.',
      'ticket_storage_unavailable':
          'Ο χώρος αρχείων δεν είναι διαθέσιμος. Το αίτημα διατηρείται.',
      'ticket_rate_limited':
          'Έγιναν πολλές προσπάθειες. Δοκιμάστε ξανά αργότερα.',
      'ticket_open_limit':
          'Υπάρχουν πολλά ανοιχτά αιτήματα. Ελέγξτε τα προηγούμενα.',
      'ticket_local_storage':
          'Δεν αποθηκεύτηκε προστατευμένα το πρόχειρο. Δεν ξεκίνησε νέα υποβολή.',
      'ticket_cancelled':
          'Η μεταφορά διακόπηκε. Το αίτημα και το αρχικό αρχείο διατηρούνται.',
      'ticket_contract': 'Δεν επιβεβαιώθηκε συμβατή υπηρεσία υποστήριξης.',
      'ticket_custom_proxy':
          'Δεν επιβεβαιώθηκε η σύνδεση μέσω του ρυθμισμένου proxy. Δεν έγινε παράκαμψή του. Το πρόχειρο διατηρείται.',
      'ticket_network_changed':
          'Οι ρυθμίσεις δικτύου άλλαξαν. Κλείστε και ανοίξτε ξανά την υποστήριξη· το πρόχειρο διατηρείται.',
      'ticket_capture_unavailable':
          'Δεν ολοκληρώθηκε η λήψη της κύριας οθόνης. Μπορείτε να επιλέξετε υπάρχον screenshot.',
      'ticket_preview_unavailable':
          'Δεν άνοιξε ο τοπικός player ή browser. Το αρχείο και το αίτημα διατηρούνται.',
    };
    if (messages.containsKey(error.code)) return messages[error.code]!;
  }
  return 'Δεν επιβεβαιώθηκε η ενέργεια. Το πρόχειρο διατηρείται. Ελέγξτε την κατάσταση πριν από νέα προσπάθεια.';
}

class ExantasTicketIdentity {
  ExantasTicketIdentity(this.api, this.deviceId, this.token) {
    final u = Uri.tryParse(api);
    if (u == null ||
        u.scheme != 'https' ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment ||
        u.path != '/api/v1' ||
        !ticketUuid.hasMatch(deviceId) ||
        token.isEmpty ||
        token.length > 8192) {
      throw const ExantasTicketFailure('ticket_identity_changed');
    }
  }
  final String api, deviceId, token;
  String get scope =>
      sha256.convert(utf8.encode('$api\n$deviceId\n$token')).toString();
  bool sameAs(ExantasTicketIdentity other) =>
      api == other.api && deviceId == other.deviceId && token == other.token;
}

Uri checkedTicketMediaUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const ExantasTicketFailure('ticket_contract');
  }
  return uri;
}

Future<Map<String, dynamic>> inspectTicketFile(String path) async {
  final file = File(path), name = p.basename(path);
  final type = ticketMedia[p.extension(name).toLowerCase()];
  final info = await file.stat();
  if (type == null ||
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      info.type != FileSystemEntityType.file ||
      RegExp(r'[/\\\x00-\x1f\x7f"]').hasMatch(name) ||
      name.contains('..') ||
      info.size <= 0 ||
      info.size > (type.startsWith('video/') ? 50000000 : 10000000)) {
    throw const ExantasTicketFailure('invalid_ticket_upload');
  }
  final digest = (await sha256.bind(file.openRead()).first).toString();
  final after = await file.stat();
  if (info.size != after.size || info.modified != after.modified) {
    throw const ExantasTicketFailure('ticket_file_changed');
  }
  return {
    'path': p.absolute(path),
    'filename': name,
    'media_type': type,
    'byte_size': info.size,
    'sha256': digest,
    'prepare_key': const Uuid().v4(),
    'complete_key': const Uuid().v4()
  };
}

void checkTicketFileQuota(List<Map<String, dynamic>> files) {
  final total = files.fold<int>(0, (n, f) => n + (f['byte_size'] as int));
  if (files.length > 5 || total > 200000000) {
    throw const ExantasTicketFailure('ticket_file_limit');
  }
}

abstract class ExantasTicketStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> close() async {}
}

abstract class ExantasTicketTransport {
  Future<Map<String, dynamic>> request(
      ExantasTicketIdentity identity, String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query});
  Future<void> upload(Uri url, File file, int length, String mediaType,
      {required bool Function() cancelled, void Function(int, int)? progress});
  void close();
}

class ExantasTicketHttpTransport implements ExantasTicketTransport {
  ExantasTicketHttpTransport({HttpClient? client})
      : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 15));
  final HttpClient _client;
  @override
  Future<Map<String, dynamic>> request(
      ExantasTicketIdentity identity, String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    if (!RegExp(r'^(/capabilities|/operations/[a-f0-9-]{36}|/[a-f0-9-]{36}(/messages|/files(/[a-f0-9-]{36}(/complete)?)?)?)?$')
            .hasMatch(path) ||
        !['GET', 'POST'].contains(method)) {
      throw const ExantasTicketFailure('ticket_contract');
    }
    final uri =
        Uri.parse('${identity.api}/rustdesk-devices/support/tickets$path')
            .replace(
                queryParameters: query == null || query.isEmpty ? null : query);
    final request =
        await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    request.headers.set('authorization', 'Bearer ${identity.token}');
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final builder = BytesBuilder(copy: false);
    await for (final bytes in response.timeout(const Duration(seconds: 30))) {
      if (builder.length + bytes.length > 8000000) {
        throw const ExantasTicketFailure('ticket_contract');
      }
      builder.add(bytes);
    }
    Map<String, dynamic> value;
    try {
      value = ticketMap(jsonDecode(utf8.decode(builder.takeBytes())));
    } catch (_) {
      throw const ExantasTicketFailure('ticket_contract');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExantasTicketFailure(
          value['status'] is String ? value['status'] : 'ticket_request_failed',
          status: response.statusCode);
    }
    if (value['status'] != 'ok') {
      throw const ExantasTicketFailure('ticket_contract');
    }
    return value;
  }

  @override
  Future<void> upload(Uri url, File file, int length, String mediaType,
      {required bool Function() cancelled,
      void Function(int, int)? progress}) async {
    checkedTicketMediaUrl(url.toString());
    final request =
        await _client.openUrl('PUT', url).timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    request.headers.contentType = ContentType.parse(mediaType);
    request.headers.set('x-upsert', 'false');
    request.contentLength = length;
    // The signed capability is sufficient. No Office bearer goes to storage.
    var sent = 0;
    try {
      await for (final bytes
          in file.openRead().timeout(const Duration(seconds: 30))) {
        if (cancelled()) throw const ExantasTicketFailure('ticket_cancelled');
        sent += bytes.length;
        if (sent > length) {
          throw const ExantasTicketFailure('ticket_file_changed');
        }
        request.add(bytes);
        await request.flush().timeout(const Duration(seconds: 30));
        progress?.call(sent, length);
      }
      if (sent != length) {
        throw const ExantasTicketFailure('ticket_file_changed');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 120));
      await response.drain<void>().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ExantasTicketFailure('ticket_storage_response',
            status: response.statusCode);
      }
    } catch (_) {
      request.abort();
      rethrow;
    }
  }

  @override
  void close() => _client.close(force: true);
}

/// One retained create/file draft and one reply per enrolled device/credential.
/// Persist the exact operation before network I/O; never replay it for a new scope.
class ExantasCustomerTicketClient {
  ExantasCustomerTicketClient(
      {required this.identity,
      required this.current,
      required this.store,
      required this.transport});
  final ExantasTicketIdentity identity;
  final Future<ExantasTicketIdentity> Function() current;
  final ExantasTicketStore store;
  final ExantasTicketTransport transport;
  Map<String, dynamic> _state = {};
  Map<String, dynamic>? capabilities;
  bool busy = false, cancelled = false;
  bool _loaded = false;

  Map<String, dynamic>? get draft =>
      _state['draft'] == null ? null : ticketMap(_state['draft']);
  Map<String, dynamic>? get pendingReply =>
      _state['reply'] == null ? null : ticketMap(_state['reply']);
  Future<void> checkIdentity() async {
    if (!identity.sameAs(await current())) {
      throw const ExantasTicketFailure('ticket_identity_changed');
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    await checkIdentity();
    final saved = await store.read();
    if (saved != null &&
        (saved['version'] != 1 || saved['scope'] != identity.scope)) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    _state = saved ??
        {'version': 1, 'scope': identity.scope, 'draft': null, 'reply': null};
    _loaded = true;
  }

  Future<void> _save(Map<String, dynamic> next) async {
    await checkIdentity();
    try {
      await store.write(next);
    } catch (_) {
      throw const ExantasTicketFailure('ticket_local_storage');
    }
    _state = ticketMap(jsonDecode(jsonEncode(next)));
  }

  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    await checkIdentity();
    final result = await transport.request(
        identity, body == null ? 'GET' : 'POST', path,
        body: body, query: query);
    await checkIdentity();
    return result;
  }

  Future<Map<String, dynamic>> refreshCapabilities() async {
    final response = await request('/capabilities');
    if (response['contract_version'] != 1 || response['enabled'] is! bool) {
      throw const ExantasTicketFailure('ticket_contract');
    }
    if (response['enabled'] == true) {
      final context = ticketMap(response['context']);
      if (response['viewer_id'] != identity.deviceId ||
          !ticketUuid.hasMatch(context['customer_id']?.toString() ?? '') ||
          context['branch_id'] != null &&
              !ticketUuid.hasMatch(context['branch_id'].toString())) {
        throw const ExantasTicketFailure('ticket_contract');
      }
    }
    capabilities = response;
    return response;
  }

  Map<String, dynamic> _scope() {
    if (capabilities?['enabled'] != true) {
      throw const ExantasTicketFailure('customer_tickets_unavailable');
    }
    final context = ticketMap(capabilities!['context']);
    return {
      'customer_id': context['customer_id'],
      'branch_id': context['branch_id']
    };
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (busy) throw const ExantasTicketFailure('ticket_pending_create');
    busy = true;
    cancelled = false;
    try {
      await load();
      return await operation();
    } finally {
      busy = false;
    }
  }

  Future<void> saveDraft(
          Map<String, dynamic> input, List<Map<String, dynamic>> files) =>
      _exclusive(() async {
        final old = draft;
        if (old?['attempted'] == true || old?['request_id'] != null) {
          throw const ExantasTicketFailure('ticket_pending_create');
        }
        checkTicketFileQuota(files);
        await _save({
          ..._state,
          'draft': {
            'key': old?['key'] ?? const Uuid().v4(),
            'input': input,
            'files': files,
            'attempted': false,
            'binding': old?['binding'] ??
                (capabilities?['enabled'] == true ? _scope() : null),
          }
        });
      });
  Future<void> discardDraft() => _exclusive(() async {
        if (draft?['attempted'] == true && draft?['request_id'] == null) {
          throw const ExantasTicketFailure('ticket_pending_create');
        }
        await _save({..._state, 'draft': null});
      });
  Future<Map<String, dynamic>?> recoverCreate() => _exclusive(() async {
        final row = draft;
        if (row == null || row['attempted'] != true) return null;
        if (row['request_id'] != null) return row;
        final response = await request('/operations/${row['key']}');
        if (response['found'] != true) return null;
        final ticket = ticketMap(response['ticket']);
        if (!ticketUuid.hasMatch(ticket['id']?.toString() ?? '')) {
          throw const ExantasTicketFailure('ticket_contract');
        }
        await _save({
          ..._state,
          'draft': {
            ...row,
            'request_id': ticket['id'],
            'reference': ticket['reference']
          }
        });
        return ticket;
      });
  Future<Map<String, dynamic>> submit() => _exclusive(() async {
        var row = draft;
        if (row == null) {
          throw const ExantasTicketFailure('ticket_local_storage');
        }
        if (row['request_id'] != null) return row;
        await refreshCapabilities();
        final binding = _scope();
        if (row['binding'] != null &&
            jsonEncode(row['binding']) != jsonEncode(binding)) {
          throw const ExantasTicketFailure('ticket_device_scope_changed');
        }
        row = {...row, 'binding': binding, 'attempted': true};
        await _save({..._state, 'draft': row});
        try {
          final response = await request('', body: {
            ...ticketMap(row['input']),
            'request_key': row['key'],
            'expected_scope': binding,
          });
          final ticket = ticketMap(response['ticket']);
          if (!ticketUuid.hasMatch(ticket['id']?.toString() ?? '')) {
            throw const ExantasTicketFailure('ticket_contract');
          }
          await _save({
            ..._state,
            'draft': {
              ...row,
              'request_id': ticket['id'],
              'reference': ticket['reference']
            }
          });
          return ticket;
        } on ExantasTicketFailure catch (error) {
          if (error.definitive &&
              error.code != 'ticket_idempotency_conflict' &&
              error.code != 'ticket_device_scope_changed') {
            await _save({
              ..._state,
              'draft': {...row, 'attempted': false}
            });
          }
          rethrow;
        }
      });
  Future<void> stageFiles(String ticketId, List<Map<String, dynamic>> files) =>
      _exclusive(() async {
        if (!ticketUuid.hasMatch(ticketId)) {
          throw const ExantasTicketFailure('ticket_contract');
        }
        if (draft != null && draft!['request_id'] != ticketId) {
          throw const ExantasTicketFailure('ticket_pending_files');
        }
        final combined = [
          ...((draft?['files'] as List?) ?? []).map(ticketMap),
          ...files,
        ];
        checkTicketFileQuota(combined);
        await _save({
          ..._state,
          'draft': {
            ...?draft,
            'key': draft?['key'] ?? const Uuid().v4(),
            'request_id': ticketId,
            'attempted': true,
            'files': combined,
          }
        });
      });
  Future<void> reselectFile(int index, String path) => _exclusive(() async {
        final row = draft, replacement = await inspectTicketFile(path);
        if (row == null) {
          throw const ExantasTicketFailure('ticket_local_storage');
        }
        final files = (row['files'] as List).map(ticketMap).toList();
        final old = files[index];
        if (old['sha256'] != replacement['sha256'] ||
            old['byte_size'] != replacement['byte_size'] ||
            old['filename'] != replacement['filename']) {
          throw const ExantasTicketFailure('ticket_file_changed');
        }
        files[index] = {...old, 'path': replacement['path']};
        await _save({
          ..._state,
          'draft': {...row, 'files': files}
        });
      });
  Future<void> uploadPending(
          {void Function(int, String, int, int)? progress}) =>
      _exclusive(() async {
        final row = draft;
        if (row == null ||
            !ticketUuid.hasMatch(row['request_id']?.toString() ?? '')) {
          throw const ExantasTicketFailure('ticket_pending_create');
        }
        final files = (row['files'] as List).map(ticketMap).toList();
        for (var index = 0; index < files.length; index++) {
          if (cancelled) throw const ExantasTicketFailure('ticket_cancelled');
          var file = files[index];
          if (file['ready'] == true) continue;
          final inspected = await inspectTicketFile(file['path']);
          if (inspected['sha256'] != file['sha256'] ||
              inspected['byte_size'] != file['byte_size']) {
            throw const ExantasTicketFailure('ticket_file_changed');
          }
          final path = '/${row['request_id']}/files';
          Future<Map<String, dynamic>> complete() async =>
              ticketMap((await request('$path/${file['file_id']}/complete',
                  body: {'request_key': file['complete_key']}))['file']);
          Map<String, dynamic>? receipt;
          if (file['file_id'] != null && file['upload_attempted'] == true) {
            try {
              receipt = await complete();
            } on ExantasTicketFailure catch (error) {
              if (!['ticket_file_unavailable', 'uploaded_size_unconfirmed']
                  .contains(error.code)) rethrow;
            }
          }
          if (receipt == null) {
            progress?.call(index, 'Προετοιμασία', 0, file['byte_size']);
            final prepared = await request(path, body: {
              'request_key': file['prepare_key'],
              'filename': file['filename'],
              'media_type': file['media_type'],
              'byte_size': file['byte_size'],
              'sha256': file['sha256'],
            });
            final preparedFile = ticketMap(prepared['file']);
            file = {
              ...file,
              'file_id': preparedFile['id'],
              'upload_attempted': true
            };
            files[index] = file;
            await _save({
              ..._state,
              'draft': {...row, 'files': files}
            });
            if (prepared['already_uploaded'] == true) {
              receipt = preparedFile;
            } else {
              final url = checkedTicketMediaUrl(
                  ticketMap(prepared['signed_upload'])['url']);
              Object? uploadError;
              try {
                await transport.upload(url, File(file['path']),
                    file['byte_size'], file['media_type'],
                    cancelled: () => cancelled,
                    progress: (sent, total) =>
                        progress?.call(index, 'Μεταφόρτωση', sent, total));
              } catch (error) {
                uploadError = error;
              }
              await checkIdentity();
              if (cancelled) {
                throw const ExantasTicketFailure('ticket_cancelled');
              }
              try {
                receipt = await complete();
              } catch (_) {
                if (uploadError != null) throw uploadError;
                rethrow;
              }
            }
          }
          if (receipt['id'] != file['file_id'] || receipt['state'] != 'ready') {
            throw const ExantasTicketFailure('ticket_contract');
          }
          files[index] = {...file, 'ready': true};
          await _save({
            ..._state,
            'draft': {...row, 'files': files}
          });
          progress?.call(
              index, 'Επισυνάφθηκε', file['byte_size'], file['byte_size']);
        }
      });
  Future<void> finishDraft() => _exclusive(() async {
        final row = draft;
        if (row == null) return;
        if (row['request_id'] == null ||
            (row['files'] as List)
                .map(ticketMap)
                .any((file) => file['ready'] != true)) {
          throw const ExantasTicketFailure('ticket_pending_files');
        }
        await _save({..._state, 'draft': null});
      });
  Future<void> reply(String ticketId, String text) => _exclusive(() async {
        final pending = pendingReply;
        if (pending != null &&
            (pending['ticket_id'] != ticketId || pending['body'] != text)) {
          throw const ExantasTicketFailure('ticket_pending_reply');
        }
        final row = pending ??
            {'ticket_id': ticketId, 'body': text, 'key': const Uuid().v4()};
        if (!ticketUuid.hasMatch(ticketId) ||
            text.trim().isEmpty ||
            text.length > 4000) {
          throw const ExantasTicketFailure('ticket_contract');
        }
        await _save({..._state, 'reply': row});
        await request('/$ticketId/messages',
            body: {'request_key': row['key'], 'body': row['body']});
        await _save({..._state, 'reply': null});
      });
  Future<void> discardReply() => _exclusive(() async {
        await _save({..._state, 'reply': null});
      });
  Future<void> dispose() async {
    cancelled = true;
    transport.close();
    await store.close();
  }
}
