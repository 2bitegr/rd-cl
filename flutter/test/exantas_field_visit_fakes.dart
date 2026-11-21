import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/exantas_field_visit.dart';
import 'package:flutter_hbb/models/exantas_field_visit_api.dart';
import 'package:flutter_hbb/models/exantas_field_visit_store.dart';
import 'package:flutter_hbb/models/exantas_office_response.dart';

const fvOwner = '00000000-0000-4000-8000-0000000000a1';
const fvApi = 'https://office.example/api/v1';
const fvScopeA = FvScope(fvOwner, fvApi);

/// Last attendance body per visit so a scripted Office echoes what it applied.
final Map<String, Map<String, dynamic>> fvAttendanceEcho = {};

/// Last applied save body per visit (content echo).
final Map<String, Map<String, dynamic>> fvContentEcho = {};

/// Reversible "encryption" so tests can assert nothing is stored in plain text.
Future<String> fakeProtect(String s) async => 'enc:${base64Encode(utf8.encode(s).reversed.toList())}';
Future<String> fakeUnprotect(String s) async {
  if (!s.startsWith('enc:')) throw StateError('not encrypted');
  return utf8.decode(base64Decode(s.substring(4)).reversed.toList());
}

ExantasFieldVisitStore fakeStore(Directory dir) => ExantasFieldVisitStore(
    directory: () async => dir, protect: fakeProtect, unprotect: fakeUnprotect);

class Call {
  Call(this.method, this.path, this.body);
  final String method, path;
  final Map<String, dynamic>? body;
  @override
  String toString() => '$method $path';
}

/// Scripted Office. [onPost]/[onGet] return a body or throw.
class FakeOffice {
  final calls = <Call>[];
  Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body)? onPost;
  Future<Map<String, dynamic>> Function(String path)? onGet;
  FvScope? lastScope;

  List<Call> posts([String? contains]) =>
      [for (final c in calls) if (c.method == 'POST' && (contains == null || c.path.contains(contains))) c];
  List<Call> gets() => [for (final c in calls) if (c.method == 'GET') c];

  ExantasFieldVisitApi get api => ExantasFieldVisitApi(get: (path, scope) async {
        calls.add(Call('GET', path, null));
        lastScope = scope;
        final h = onGet;
        if (h == null) return {'status': 'ok', 'items': []};
        return h(path);
      }, post: (path, body, scope) async {
        calls.add(Call('POST', path, Map<String, dynamic>.from(body)));
        lastScope = scope;
        final h = onPost;
        if (h == null) throw StateError('no server');
        return h(path, body);
      });
}

ExantasOfficeRejection rejection(int status, String code, [String message = 'Απορρίφθηκε']) =>
    ExantasOfficeRejection(status, code, message);

FvJobType jobType([String id = 'jt-1']) =>
    FvJobType(id, 'maintenance', 'Συντήρηση', [(id: 'ck-1', label: 'Backup'), (id: 'ck-2', label: 'Antivirus')]);

Map<String, dynamic> visitDto(String id, {String status = 'in_progress', String revision = '2', List<Map<String, dynamic>>? participants, Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'status': status,
      'source': 'mobile',
      'revision': revision,
      'client_rev': 1,
      'updated_at': '2026-11-21T09:00:00Z',
      'customer': {'id': 'c-1', 'name': 'Κ. Αλεξίου', 'is_draft': false, 'draft_customer_id': null},
      'job_type': {'id': 'jt-1', 'code': 'maintenance', 'label_el': 'Συντήρηση'},
      'lead_user_id': fvOwner,
      'participants': participants ??
          [
            {
              'user_id': fvOwner,
              'display_name': 'Εσύ',
              'role': 'lead',
              'is_self': true,
              'arrival': fvAttendanceEcho[id]?['arrival'],
              'departure_at': fvAttendanceEcho[id]?['departure_at'],
              'pauses': fvAttendanceEcho[id]?['pauses'] ?? [],
            },
          ],
      'work_summary': fvContentEcho[id]?['work_summary'] ?? '',
      'internal_note': fvContentEcho[id]?['internal_note'] ?? '',
      'checklist': fvContentEcho[id]?['checklist'] ?? [],
      'equipment_lines': fvContentEcho[id]?['equipment_lines'] ?? [],
      'defective_units': fvContentEcho[id]?['defective_units'] ?? [],
      'payments': [],
      'photos': [],
      ...extra,
    };
