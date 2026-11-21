import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'exantas_field_visit.dart';
import 'exantas_field_visit_api.dart';
import 'exantas_field_visit_store.dart';
import 'exantas_financial_ledger.dart' show exantasAbandonEligible;
import 'exantas_office_response.dart';

/// One GPS fix taken at arrival.
class FvFix {
  const FvFix(this.lat, this.lng, this.accuracyM, this.at);
  final double lat, lng, accuracyM;
  final DateTime at;
}

/// Uploads photo bytes to the signed storage URL returned by Office.
typedef FvPhotoUploader = Future<void> Function(
    Map<String, dynamic> signedUpload, List<int> bytes, String mediaType);

Future<void> fvHttpPhotoUploader(
    Map<String, dynamic> signed, List<int> bytes, String mediaType) async {
  var url = '${signed['url'] ?? ''}';
  final token = '${signed['token'] ?? ''}';
  if (url.isEmpty) throw StateError('Λείπει η διεύθυνση αποστολής φωτογραφίας.');
  if (token.isNotEmpty && !url.contains('token=')) {
    url = '$url${url.contains('?') ? '&' : '?'}token=${Uri.encodeQueryComponent(token)}';
  }
  final r = await http
      .put(Uri.parse(url), headers: {'content-type': mediaType, 'x-upsert': 'false'}, body: bytes)
      .timeout(const Duration(seconds: 60));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw StateError('Η αποστολή φωτογραφίας απέτυχε (HTTP ${r.statusCode}).');
  }
}

class FvDraftCustomerInput {
  const FvDraftCustomerInput(
      {required this.companyName,
      this.afm = '',
      this.phone = '',
      this.email = '',
      this.contactName = '',
      this.address = '',
      this.notes = ''});
  final String companyName, afm, phone, email, contactName, address, notes;
  Map<String, dynamic> toBody(String draftId) => {
        'draft_customer_id': draftId,
        'company_name': companyName.trim(),
        if (afm.trim().isNotEmpty) 'afm': afm.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (email.trim().isNotEmpty) 'email': email.trim(),
        if (contactName.trim().isNotEmpty) 'contact_name': contactName.trim(),
        if (address.trim().isNotEmpty) 'address': address.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
}

/// Offline-first outbox and sync engine for field visits.
///
/// * Every change is persisted to the encrypted store BEFORE any network call.
/// * Per visit, ops run strictly in list order; different visits run in
///   parallel. A sent op body is frozen; unsent ops of the same kind coalesce.
/// * Non-financial ops retry the identical body+key with backoff (replay safe).
/// * Close is financial: persist (`reserved_at`) -> ONE POST -> on an unknown
///   outcome only GET `/support-workflow/requests/{key}`; abandon needs proof of
///   not-applied and >= 2 min (`exantasAbandonEligible`) and a NEW key later.
class ExantasFieldVisitSync extends ChangeNotifier {
  ExantasFieldVisitSync({
    required this.store,
    required this.api,
    required this.scope,
    FvPhotoUploader? uploader,
    DateTime Function()? now,
    String Function()? newId,
  })  : uploader = uploader ?? fvHttpPhotoUploader,
        now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());

  final ExantasFieldVisitStore store;
  final ExantasFieldVisitApi api;
  final Future<FvScope?> Function() scope;
  final FvPhotoUploader uploader;
  final DateTime Function() now;
  final String Function() _newId;

  final Map<String, FieldVisit> _visits = {};
  final Map<String, Future<void>> _locks = {};
  Future<void>? _syncing;
  FvScope? _scope;
  bool? _enabled;
  FvConfig config = const FvConfig();
  String? lastError;
  bool lastOffline = false;
  int staleIgnored = 0;

  /// null = not detected yet (entry point stays hidden), false = feature off.
  bool? get enabled => _enabled;
  String get selfUserId => _scope?.owner ?? '';

  List<FieldVisit> get visits {
    final all = _visits.values.toList();
    all.sort((a, b) {
      final x = a.scheduledStart ?? a.myAttendance.arrivalAt ?? a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final y = b.scheduledStart ?? b.myAttendance.arrivalAt ?? b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return x.compareTo(y);
    });
    return all;
  }

  FieldVisit? visit(String id) => _visits[id];

  /// Visits with something not yet accepted by Office (incl. rejected ops that
  /// need the technician's attention).
  List<FieldVisit> get unsynced => [for (final v in visits) if (v.ops.isNotEmpty) v];
  int get unsyncedCount => unsynced.length;

  void _notify() {
    if (hasListeners) notifyListeners();
  }

  // ------------------------------------------------------------------ load

  /// Reads the store and keeps only visits of the current Office session.
  Future<void> load() async {
    _scope = await scope();
    final all = await store.loadAll();
    _visits.clear();
    final s = _scope;
    if (s == null) {
      _notify();
      return;
    }
    for (final v in all) {
      if (fvBelongsToScope(v, s.owner, s.api)) _visits[v.id] = v;
    }
    final cached = await store.readMeta('config');
    if (cached != null && cached['owner'] == s.owner && cached['api'] == s.api && cached['config'] is Map) {
      config = FvConfig.fromJson(Map<String, dynamic>.from(cached['config'] as Map));
    }
    _notify();
  }

  /// Drops memory state when the Office account or API changed (files stay).
  Future<void> reset() async {
    _visits.clear();
    _enabled = null;
    config = const FvConfig();
    _scope = null;
    _notify();
  }

  Future<bool> detectFeature() async {
    final s = _scope ??= await scope();
    if (s == null) return false;
    try {
      _enabled = await api.capabilities(s);
    } catch (e) {
      lastOffline = fvIsOfflineError(e);
      // Offline: keep an earlier answer; with local visits the entry stays.
      _enabled ??= _visits.isNotEmpty ? true : null;
    }
    _notify();
    return _enabled == true;
  }

  Future<void> refreshConfig() async {
    final s = _scope ??= await scope();
    if (s == null) return;
    try {
      config = await api.config(s);
      await store.writeMeta('config', {'owner': s.owner, 'api': s.api, 'config': config.toJson()});
      _notify();
    } catch (e) {
      lastOffline = fvIsOfflineError(e);
    }
  }

  // ------------------------------------------------------------- plumbing

  Future<T> _lock<T>(String id, Future<T> Function() fn) {
    final previous = _locks[id] ?? Future<void>.value();
    final done = Completer<T>();
    final next = previous.catchError((Object _) {}).then((_) async {
      try {
        done.complete(await fn());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    _locks[id] = next;
    return done.future;
  }

  Future<void> _persist(FieldVisit v) => store.save(v);

  FieldVisit _require(String id) {
    final v = _visits[id];
    if (v == null) throw StateError('Η επίσκεψη δεν βρέθηκε.');
    return v;
  }

  FvOp _newOp(FvOpKind kind, String path, Map<String, dynamic> body, {String? photoId, bool reserve = false}) {
    final key = _newId();
    return FvOp(
        key: key,
        kind: kind,
        path: path,
        body: {...body, 'idempotency_key': key},
        createdAt: now().toUtc(),
        reservedAt: reserve ? now().toUtc() : null,
        photoId: photoId);
  }

  /// Replaces an unsent op of the same kind in place (newer rev, new key), or
  /// appends. A sent op is never touched.
  void _coalesce(FieldVisit v, FvOpKind kind, String path, Map<String, dynamic> body) {
    final op = _newOp(kind, path, body);
    final i = v.ops.indexWhere((o) => o.kind == kind && !o.sent && o.state == 'queued');
    if (i >= 0) {
      v.ops[i] = op;
    } else {
      v.ops.add(op);
    }
  }

  /// Dependencies (draft customer, equipment) must reach Office before the
  /// first unsent op that may reference them.
  void _insertDependency(FieldVisit v, FvOp op) {
    final i = v.ops.indexWhere((o) => !o.sent && o.state == 'queued');
    if (i >= 0) {
      v.ops.insert(i, op);
    } else {
      v.ops.add(op);
    }
  }

  Map<String, dynamic> _saveBody(FieldVisit v) {
    final first = !v.serverKnown && !v.ops.any((o) => o.kind == FvOpKind.save && o.sent);
    final create = first && v.createdLocally && v.source == 'mobile';
    return {
      'client_rev': v.contentClientRev,
      if (create) 'create': v.createBody(),
      if (create) 'start': true,
      'job_type_id': v.jobTypeId,
      ...v.contentBody(),
    };
  }

  void _queueSave(FieldVisit v) {
    // Rebuilt from scratch each time; coalesces into an unsent save and keeps
    // `create` when that unsent save carried it.
    final keepsCreate = v.ops.any((o) => o.kind == FvOpKind.save && !o.sent && o.body.containsKey('create'));
    final body = _saveBody(v);
    if (keepsCreate && !body.containsKey('create')) {
      body['create'] = v.createBody();
      body['start'] = true;
    }
    _coalesce(v, FvOpKind.save, ExantasFieldVisitApi.savePath(v.id), body);
  }

  void _queueAttendance(FieldVisit v) {
    final a = v.myAttendance;
    a.clientRev += 1;
    _coalesce(v, FvOpKind.attendance, ExantasFieldVisitApi.attendancePath(v.id), a.toBody());
  }

  Future<void> _commit(FieldVisit v) async {
    await _persist(v);
    _notify();
  }

  // ------------------------------------------------------- local mutations

  /// Starts a free visit (no appointment) and persists it with its first
  /// `save` (and the draft-customer op when the customer is new).
  Future<FieldVisit> startVisit({
    String? customerId,
    required String customerName,
    FvDraftCustomerInput? draft,
    String? draftCustomerId,
    String? branchId,
    String branchName = '',
    String? contactId,
    String? workItemId,
    String workTitle = '',
    required FvJobType jobType,
    List<String> participantIds = const [],
    String? chargeDefault,
  }) async {
    final s = _scope ??= await scope();
    if (s == null) throw StateError('Απαιτείται είσοδος στο Office.');
    if (customerId == null && draft == null && draftCustomerId == null) {
      throw StateError('Διάλεξε πελάτη.');
    }
    final id = _newId();
    final draftId = draft == null ? draftCustomerId : _newId();
    final ids = <String>{s.owner, ...participantIds};
    final v = FieldVisit(
        id: id,
        owner: s.owner,
        api: s.api,
        selfUserId: s.owner,
        status: 'in_progress',
        source: 'mobile',
        createdLocally: true,
        customerId: customerId,
        draftCustomerId: customerId == null ? draftId : null,
        customerName: draft?.companyName.trim().isNotEmpty == true ? draft!.companyName.trim() : customerName,
        customerIsDraft: customerId == null,
        customerChargeDefault: chargeDefault,
        branchId: branchId,
        branchName: branchName,
        contactId: contactId,
        workItemId: workItemId,
        workTitle: workTitle,
        jobTypeId: jobType.id,
        jobTypeLabel: jobType.label,
        leadUserId: s.owner,
        participants: [
          for (final uid in ids)
            FvParticipant(
                userId: uid,
                displayName: uid == s.owner
                    ? 'Εσύ'
                    : config.staff.where((x) => x.id == uid).map((x) => x.name).firstOrNull ?? uid,
                role: uid == s.owner ? 'lead' : 'member',
                isSelf: uid == s.owner)
        ],
        checklist: [for (final c in jobType.checklist) FvChecklistItem(itemId: c.id, label: c.label)],
        chargeSource: FvChargeSource.parse(chargeDefault),
        updatedAt: now().toUtc());
    if (draft != null) {
      v.ops.add(_newOp(FvOpKind.draftCustomer, ExantasFieldVisitApi.draftCustomerPath(), draft.toBody(draftId!)));
    } else if (customerId == null && draftId != null) {
      // Reusing a draft whose creation is still queued in another visit: the
      // identical op (same key and body) is replay-safe, so copy it.
      for (final other in _visits.values) {
        for (final o in other.ops) {
          if (o.kind == FvOpKind.draftCustomer && o.body['draft_customer_id'] == draftId) {
            v.ops.add(FvOp.fromJson(o.toJson())!);
          }
        }
      }
    }
    v.contentClientRev = 1;
    _queueSave(v);
    _visits[id] = v;
    await _commit(v);
    return v;
  }

  /// Booking from the phone (status `scheduled`, no attendance).
  Future<FieldVisit> createAppointment({
    String? customerId,
    required String customerName,
    FvDraftCustomerInput? draft,
    String? draftCustomerId,
    String? branchId,
    String? workItemId,
    required FvJobType jobType,
    required DateTime start,
    required DateTime end,
    String note = '',
    List<String> participantIds = const [],
  }) async {
    final s = _scope ??= await scope();
    if (s == null) throw StateError('Απαιτείται είσοδος στο Office.');
    if (!end.isAfter(start)) throw StateError('Η λήξη πρέπει να είναι μετά την έναρξη.');
    final id = _newId();
    final draftId = draft == null ? draftCustomerId : _newId();
    final ids = <String>{s.owner, ...participantIds};
    final v = FieldVisit(
        id: id,
        owner: s.owner,
        api: s.api,
        selfUserId: s.owner,
        status: 'scheduled',
        source: 'appointment_mobile',
        createdLocally: true,
        customerId: customerId,
        draftCustomerId: customerId == null ? draftId : null,
        customerName: draft?.companyName.trim().isNotEmpty == true ? draft!.companyName.trim() : customerName,
        customerIsDraft: customerId == null,
        branchId: branchId,
        workItemId: workItemId,
        jobTypeId: jobType.id,
        jobTypeLabel: jobType.label,
        scheduledStart: start.toUtc(),
        scheduledEnd: end.toUtc(),
        scheduledNote: note,
        leadUserId: s.owner,
        participants: [
          for (final uid in ids)
            FvParticipant(
                userId: uid,
                displayName: uid == s.owner ? 'Εσύ' : config.staff.where((x) => x.id == uid).map((x) => x.name).firstOrNull ?? uid,
                role: uid == s.owner ? 'lead' : 'member',
                isSelf: uid == s.owner)
        ],
        checklist: [for (final c in jobType.checklist) FvChecklistItem(itemId: c.id, label: c.label)],
        updatedAt: now().toUtc());
    if (draft != null) {
      v.ops.add(_newOp(FvOpKind.draftCustomer, ExantasFieldVisitApi.draftCustomerPath(), draft.toBody(draftId!)));
    }
    v.ops.add(_newOp(FvOpKind.appointment, ExantasFieldVisitApi.appointmentCreatePath(), {
      'visit_id': id,
      if (customerId != null) 'customer_id': customerId else 'draft_customer_id': draftId,
      if (branchId != null) 'branch_id': branchId,
      if (workItemId != null) 'work_item_id': workItemId,
      'job_type_id': jobType.id,
      'scheduled_start': fvIso(start),
      'scheduled_end': fvIso(end),
      if (note.isNotEmpty) 'scheduled_note': note,
      'participants': ids.toList(),
    }));
    _visits[id] = v;
    await _commit(v);
    return v;
  }

  /// Lead-only content edit. [edit] mutates the visit; one `save` is queued.
  Future<void> editContent(String id, void Function(FieldVisit v) edit) =>
      _lock(id, () async {
        final v = _require(id);
        if (v.contentLocked) throw StateError('Το περιεχόμενο δεν αλλάζει πια.');
        edit(v);
        v.contentClientRev += 1;
        v.updatedAt = now().toUtc();
        _queueSave(v);
        await _commit(v);
      });

  Future<void> changeJobType(String id, FvJobType type) => editContent(id, (v) {
        final checked = {for (final c in v.checklist) if (c.checked && c.itemId != null) c.itemId!: c};
        v.jobTypeId = type.id;
        v.jobTypeLabel = type.label;
        v.checklist = [
          for (final c in type.checklist)
            checked[c.id] ?? FvChecklistItem(itemId: c.id, label: c.label)
        ];
      });

  Future<void> _attendanceChange(String id, void Function(FvAttendance a, DateTime t) change) =>
      _lock(id, () async {
        final v = _require(id);
        if (v.localStatus == FvLocalStatus.cancelled) throw StateError('Η επίσκεψη ακυρώθηκε.');
        final me = v.self;
        if (me == null) throw StateError('Δεν συμμετέχεις σε αυτή την επίσκεψη.');
        final before = me.attendance.copy();
        final t = now().toUtc();
        change(me.attendance, t);
        final problem = fvValidateAttendance(me.attendance, t);
        if (problem != null) {
          me.attendance
            ..arrivalAt = before.arrivalAt
            ..lat = before.lat
            ..lng = before.lng
            ..accuracyM = before.accuracyM
            ..fixAt = before.fixAt
            ..gpsMissing = before.gpsMissing
            ..departureAt = before.departureAt
            ..pauses = before.pauses
            ..clientRev = before.clientRev;
          throw StateError(problem);
        }
        if (v.status == 'scheduled' && me.attendance.arrived) v.status = 'in_progress';
        _queueAttendance(v);
        await _commit(v);
      });

  /// Arrival: one fix taken by the caller (null = GPS failed: still recorded).
  Future<void> arrive(String id, {FvFix? fix}) => _attendanceChange(id, (a, t) {
        if (a.arrived) throw StateError('already_arrived');
        a.arrivalAt = t;
        a.lat = fix?.lat;
        a.lng = fix?.lng;
        a.accuracyM = fix?.accuracyM;
        a.fixAt = fix?.at;
        a.gpsMissing = fix == null;
      });

  Future<void> startPause(String id) => _attendanceChange(id, (a, t) {
        if (!a.isOpen || a.onPause) throw StateError('pause_invalid');
        a.pauses = [...a.pauses, FvPause(t)];
      });

  Future<void> endPause(String id) => _attendanceChange(id, (a, t) {
        if (!a.onPause) throw StateError('pause_invalid');
        a.pauses = [...a.pauses.sublist(0, a.pauses.length - 1), a.pauses.last.withEnd(t)];
      });

  Future<void> depart(String id) => _attendanceChange(id, (a, t) {
        if (!a.isOpen) throw StateError('departure_invalid');
        if (a.onPause) a.pauses = [...a.pauses.sublist(0, a.pauses.length - 1), a.pauses.last.withEnd(t)];
        a.departureAt = t;
      });

  Future<FvPayment> addPayment(String id,
      {required String method, required int amountMinor, String reference = ''}) async {
    if (amountMinor <= 0) throw StateError('Μη έγκυρο ποσό.');
    return _lock(id, () async {
      final v = _require(id);
      final p = FvPayment(
          id: _newId(), method: method, amountMinor: amountMinor, receivedAt: now().toUtc(), reference: reference);
      v.payments.add(p);
      v.ops.add(_newOp(FvOpKind.payment, ExantasFieldVisitApi.paymentPath(id), {
        'payment_id': p.id,
        'method': method,
        'amount_minor': '$amountMinor',
        'received_at': fvIso(p.receivedAt),
        if (reference.isNotEmpty) 'reference': reference,
      }));
      await _commit(v);
      return p;
    });
  }

  Future<FvPhoto> addPhoto(String id, List<int> bytes, {String mediaType = 'image/jpeg', String caption = ''}) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) throw StateError('Μη έγκυρο μέγεθος φωτογραφίας.');
    return _lock(id, () async {
      final v = _require(id);
      final photo = FvPhoto(
          id: _newId(),
          caption: caption,
          byteSize: bytes.length,
          mediaType: mediaType,
          sha256: crypto.sha256.convert(bytes).toString());
      await store.writeBinary(id, photo.id, bytes);
      v.photos.add(photo);
      v.ops.add(_newOp(
          FvOpKind.photo,
          ExantasFieldVisitApi.photoRequestPath(id),
          {
            'photo_id': photo.id,
            'media_type': mediaType,
            'byte_size': bytes.length,
            'sha256': photo.sha256,
            if (caption.isNotEmpty) 'caption': caption,
          },
          photoId: photo.id));
      await _commit(v);
      return photo;
    });
  }

  /// Registers a new device (also from the scanner) in the customer's register.
  Future<FvEquipment> saveEquipment(String id, FvEquipment e, {String action = 'present'}) =>
      _lock(id, () async {
        final v = _require(id);
        e
          ..customerId = v.customerId
          ..draftCustomerId = v.customerId == null ? v.draftCustomerId : null;
        v.equipment.removeWhere((x) => x.id == e.id);
        v.equipment.add(e);
        if (!v.equipmentLines.any((l) => l.equipmentId == e.id)) {
          v.equipmentLines.add(FvEquipmentLine(equipmentId: e.id, action: action));
        }
        if (!e.synced) {
          _insertDependency(v, _newOp(FvOpKind.equipment, ExantasFieldVisitApi.equipmentSavePath(), e.toBody()));
        }
        if (!v.contentLocked) {
          v.contentClientRev += 1;
          _queueSave(v);
        }
        await _commit(v);
        return e;
      });

  Future<void> cancelVisit(String id, String reason) => _lock(id, () async {
        final v = _require(id);
        if (v.myAttendance.arrived && v.serverKnown && v.status != 'scheduled') {
          throw StateError('visit_not_cancellable');
        }
        v.ops.add(_newOp(FvOpKind.cancel, ExantasFieldVisitApi.cancelPath(id), {'reason': reason}));
        v.localStatus = FvLocalStatus.cancelled;
        await _commit(v);
      });

  /// Rejected ops stay visible until the technician dismisses them.
  Future<void> dismissRejected(String id, String key) => _lock(id, () async {
        final v = _require(id);
        v.ops.removeWhere((o) => o.key == key && o.state == 'rejected');
        if (v.ops.isEmpty && v.localStatus == FvLocalStatus.cancelled && !v.serverKnown) {
          _visits.remove(id);
          await store.delete(id);
        } else {
          await _persist(v);
        }
        _notify();
      });

  // ------------------------------------------------------------------ close

  /// Builds the single close op from the visit state and persists it with
  /// `reserved_at` BEFORE any POST. Then syncs that visit once.
  Future<void> closeVisit(String id) async {
    await _lock(id, () async {
      final v = _require(id);
      if (!v.isLead) throw StateError('field_visit_lead_required');
      if (v.closeOp != null) throw StateError('Υπάρχει ήδη αίτημα κλεισίματος σε εξέλιξη.');
      if (v.localStatus != FvLocalStatus.draft) throw StateError('Το δελτίο δεν είναι ανοιχτό.');
      final blockers = fvCloseBlockers(v, discountLimitBps: config.myDiscountLimitBps);
      if (blockers.isNotEmpty) throw StateError(blockers.first);
      final t = now().toUtc();
      final me = v.self!;
      // The lead's own departure completes at close (also sent as a guard).
      if (me.attendance.departureAt == null) {
        if (me.attendance.onPause) {
          me.attendance.pauses = [
            ...me.attendance.pauses.sublist(0, me.attendance.pauses.length - 1),
            me.attendance.pauses.last.withEnd(t)
          ];
        }
        me.attendance.departureAt = t;
        // Sent as `auto_depart_at`: the close itself completes the departure,
        // so the close never waits behind an extra attendance op.
        v.autoDepartAt = t;
      }
      final sig = v.signaturePngBase64;
      final body = <String, dynamic>{
        'client_rev': v.contentClientRev,
        'content': {
          ...v.contentBody(),
          if (!v.serverKnown) 'create': v.createBody(),
          if (!v.serverKnown) 'job_type_id': v.jobTypeId,
        },
        'outcome': v.outcome!.wire,
        if (v.outcomeNote.trim().isNotEmpty) 'outcome_note': v.outcomeNote.trim(),
        if (v.outcome == FvOutcome.newVisit && v.followUpStart != null) 'follow_up_start': fvIso(v.followUpStart!),
        'charge_source': v.chargeSource!.wire,
        'discount_bps': v.discountBps,
        if (v.discountReason.trim().isNotEmpty) 'discount_reason': v.discountReason.trim(),
        'show_prices': v.showPrices,
        'signature': sig != null && sig.isNotEmpty
            ? {'signer_name': v.signerName.trim(), 'png_base64': sig}
            : {'no_signature': true},
        if (v.autoDepartAt != null) 'auto_depart_at': fvIso(v.autoDepartAt!),
      };
      v.ops.add(_newOp(FvOpKind.close, ExantasFieldVisitApi.closePath(id), body, reserve: true));
      v.localStatus = FvLocalStatus.closing;
      v.closeRejection = null;
      await _commit(v);
    });
    await syncVisit(id, force: true);
  }

  FvOp? _unresolvedClose(FieldVisit v) {
    final op = v.closeOp;
    return op != null && op.sent && op.state == 'unknown' ? op : null;
  }

  bool canAbandonClose(String id) {
    final op = _visits[id]?.closeOp;
    return op != null && op.sent && exantasAbandonEligible(op.marks, now());
  }

  /// GET only. Returns true when Office had applied the close.
  Future<bool> recoverClose(String id) async {
    final v = _require(id);
    final op = v.closeOp;
    if (op == null) return true;
    final s = await scope();
    if (s == null || !fvBelongsToScope(v, s.owner, s.api)) throw StateError('Η σύνδεση Office άλλαξε.');
    final response = await api.recover(op.key, s);
    final state = (response['request'] as Map?)?['state'];
    if (state == 'applied') {
      final result = Map<String, dynamic>.from((response['request'] as Map)['result'] as Map);
      await _lock(id, () async => _acceptClose(v, op, result));
      return true;
    }
    if (state == 'not_found' && op.notFoundAt == null) {
      await _lock(id, () async {
        op.notFoundAt = now().toUtc();
        await _commit(v);
      });
    }
    return false;
  }

  /// User-initiated. Clears the close op so the technician may close again with
  /// a NEW key. A fresh GET decides first: applied results are accepted instead.
  Future<bool> abandonClose(String id) async {
    final v = _require(id);
    final op = v.closeOp;
    if (op == null) return false;
    if (!exantasAbandonEligible(op.marks, now())) {
      throw StateError('Η ακύρωση επιτρέπεται μόνο όταν το Office δεν έχει το αίτημα και έχουν περάσει 2 λεπτά.');
    }
    final s = await scope();
    if (s == null || !fvBelongsToScope(v, s.owner, s.api)) throw StateError('Η σύνδεση Office άλλαξε.');
    final response = await api.recover(op.key, s);
    final state = (response['request'] as Map?)?['state'];
    if (state == 'applied') {
      final result = Map<String, dynamic>.from((response['request'] as Map)['result'] as Map);
      await _lock(id, () async => _acceptClose(v, op, result));
      return false;
    }
    if (state != 'not_found') throw StateError('Δεν επιβεβαιώθηκε η απουσία του αιτήματος.');
    await _lock(id, () async {
      v.ops.removeWhere((o) => identical(o, op));
      v.localStatus = FvLocalStatus.draft;
      v.lastAbandonedAt = now().toUtc();
      await _commit(v);
    });
    return true;
  }

  Future<void> _acceptClose(FieldVisit v, FvOp op, Map<String, dynamic> result) async {
    final dto = result['visit'];
    if (result['status'] != 'ok' || dto is! Map || '${dto['id']}' != v.id) {
      throw StateError('Το Office δεν επιβεβαίωσε το κλείσιμο.');
    }
    v.ops.removeWhere((o) => identical(o, op));
    v.applyServer(Map<String, dynamic>.from(dto),
        keepLocalContent: false, keepLocalAttendance: v.ops.any((o) => o.kind == FvOpKind.attendance));
    if (result['charge'] is Map) v.charge = Map<String, dynamic>.from(result['charge'] as Map);
    if (result['report'] is Map) v.report = Map<String, dynamic>.from(result['report'] as Map);
    v.warnings = [for (final w in (result['warnings'] as List? ?? const [])) '$w'];
    v.localStatus = result['finalized'] == true ? FvLocalStatus.closed : FvLocalStatus.awaiting;
    v.closeRejection = null;
    await _commit(v);
  }

  // ------------------------------------------------------------------- sync

  /// Single-flight over all visits. [force] ignores backoff (manual refresh).
  Future<void> sync({bool force = false}) => _syncing ??= _runSync(force).whenComplete(() => _syncing = null);

  Future<void> _runSync(bool force) async {
    try {
      final s = _scope = await scope();
      if (s == null) return;
      await Future.wait([for (final v in List.of(_visits.values)) if (v.ops.isNotEmpty) _processVisit(v, force)]);
      lastOffline = false;
      lastError = null;
      try {
        await pull();
      } catch (e) {
        lastOffline = fvIsOfflineError(e);
        if (!lastOffline && !fvIsFeatureOff(e)) lastError = e.toString();
      }
    } catch (e) {
      lastOffline = fvIsOfflineError(e);
      lastError = e.toString();
    }
    _notify();
  }

  Future<void> syncVisit(String id, {bool force = false}) async {
    final v = _visits[id];
    if (v == null) return;
    await _processVisit(v, force);
    _notify();
  }

  FvOp? _runnable(FieldVisit v, bool force) {
    for (final op in v.ops) {
      if (op.state == 'rejected') continue;
      if (op.financial && op.sent) return null; // GET-only recovery, never a re-POST
      if (op.state == 'unknown' && !force) {
        final at = op.nextRetryAt;
        if (at != null && at.isAfter(now())) return null;
      }
      return op;
    }
    return null;
  }

  Future<void> _processVisit(FieldVisit v, bool force) async {
    if (_visitBusy.contains(v.id)) {
      _visitDirty.add(v.id);
      return;
    }
    _visitBusy.add(v.id);
    try {
      do {
        _visitDirty.remove(v.id);
        await _processVisitOnce(v, force);
      } while (_visitDirty.contains(v.id));
    } finally {
      _visitBusy.remove(v.id);
    }
  }

  Future<void> _processVisitOnce(FieldVisit v, bool force) async {
    {
      final s = await scope();
      if (s == null || !fvBelongsToScope(v, s.owner, s.api)) return;
      // Automatic GET-only recovery of an unresolved close.
      if (_unresolvedClose(v) != null) {
        try {
          await recoverClose(v.id);
        } catch (e) {
          lastOffline = fvIsOfflineError(e);
        }
      }
      for (var guard = 0; guard < 200; guard++) {
        final op = await _lock(v.id, () async => _runnable(v, force));
        if (op == null) break;
        if (!await _send(v, op, s)) break;
      }
    }
  }

  final Set<String> _visitBusy = {}, _visitDirty = {};

  Duration _backoff(int attempts) {
    final secs = 5 * (1 << (attempts.clamp(1, 7) - 1));
    return Duration(seconds: secs.clamp(5, 300));
  }

  /// Returns true to continue with the next op, false to stop this visit.
  Future<bool> _send(FieldVisit v, FvOp op, FvScope s) async {
    await _lock(v.id, () async {
      if (!op.sent) {
        op.body['client_sent_at'] = fvIso(now());
        op.sentAt = now().toUtc();
        op.reservedAt ??= op.financial ? now().toUtc() : null;
      }
      op.attempts += 1;
      await _persist(v);
    });
    try {
      final result = op.kind == FvOpKind.photo
          ? await _sendPhoto(v, op, s)
          : await api.post(op.path, op.body, s);
      return await _lock(v.id, () async {
        try {
          await _accept(v, op, result);
          return true;
        } on StateError {
          // An unexpected body is NOT proof of failure: keep the op sent.
          await _markUnknown(v, op, financialKeep: true);
          return false;
        }
      });
    } on ExantasOfficeRejection catch (e) {
      if (e.definitive) {
        await _lock(v.id, () => _reject(v, op, e));
        return true;
      }
      await _lock(v.id, () => _markUnknown(v, op));
      return false;
    } catch (e) {
      lastOffline = fvIsOfflineError(e);
      await _lock(v.id, () => _markUnknown(v, op));
      return false;
    }
  }

  Future<void> _markUnknown(FieldVisit v, FvOp op, {bool financialKeep = false}) async {
    op.state = 'unknown';
    // The financial POST is never retried: no retry time, recovery by GET.
    op.nextRetryAt = op.financial ? null : now().toUtc().add(_backoff(op.attempts));
    await _commit(v);
  }

  Future<void> _reject(FieldVisit v, FvOp op, ExantasOfficeRejection e) async {
    final handled = await _handleSpecialRejection(v, op, e);
    if (handled) return;
    if (op.kind == FvOpKind.close) {
      // 4xx rolled the request back: the key is unused. Unlock the editor.
      v.ops.removeWhere((o) => identical(o, op));
      v.localStatus = FvLocalStatus.draft;
      v.closeRejection = {'status': e.statusCode, 'code': e.code, 'message': e.message};
      if (e.code == 'visit_closed') v.localStatus = FvLocalStatus.closed;
    } else {
      op.state = 'rejected';
      op.rejected = {'status': e.statusCode, 'code': e.code, 'message': e.message};
    }
    await _commit(v);
  }

  /// equipment_duplicate: re-point lines to the existing register row.
  Future<bool> _handleSpecialRejection(FieldVisit v, FvOp op, ExantasOfficeRejection e) async {
    if (op.kind != FvOpKind.equipment || e.code != 'equipment_duplicate') return false;
    final mine = v.equipment.where((x) => x.id == op.body['equipment_id']).firstOrNull;
    if (mine == null) return false;
    try {
      final found = await api.equipmentList(
          customerId: v.customerId,
          barcode: mine.barcode.isNotEmpty ? mine.barcode : null,
          q: mine.barcode.isEmpty ? mine.serialNumber : null,
          scope: await scope());
      final existing = found.where((x) => x.id != mine.id).firstOrNull;
      if (existing == null) return false;
      v.ops.removeWhere((o) => identical(o, op));
      for (final l in v.equipmentLines) {
        if (l.equipmentId == mine.id) {
          v.equipmentLines[v.equipmentLines.indexOf(l)] = FvEquipmentLine(equipmentId: existing.id, action: l.action);
        }
      }
      for (final d in v.defectiveUnits) {
        if (d.equipmentId == mine.id) d.equipmentId = existing.id;
      }
      v.equipment.removeWhere((x) => x.id == mine.id);
      v.equipment.add(existing);
      if (!v.contentLocked) {
        v.contentClientRev += 1;
        _queueSave(v);
      }
      await _commit(v);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _sendPhoto(FieldVisit v, FvOp op, FvScope s) async {
    final requested = await api.post(op.path, op.body, s);
    final signed = requested['signed_upload'];
    final photoId = op.photoId!;
    if (signed is Map) {
      final bytes = await store.readBinary(v.id, photoId);
      if (bytes == null) throw ExantasOfficeRejection(404, 'photo_missing', 'Η φωτογραφία δεν βρέθηκε στη συσκευή.');
      await uploader(Map<String, dynamic>.from(signed), bytes, '${op.body['media_type']}');
    }
    return api.post(ExantasFieldVisitApi.photoConfirmPath(v.id, photoId),
        {'idempotency_key': '${op.key}:confirm', 'client_sent_at': fvIso(now())}, s);
  }

  Future<void> _accept(FieldVisit v, FvOp op, Map<String, dynamic> result) async {
    if (op.kind == FvOpKind.close) return _acceptClose(v, op, result);
    final dto = result['visit'];
    switch (op.kind) {
      case FvOpKind.save:
      case FvOpKind.attendance:
      case FvOpKind.appointment:
      case FvOpKind.cancel:
        v.ops.removeWhere((o) => identical(o, op));
        if (result['applied'] == false) staleIgnored += 1;
        if (dto is Map) {
          v.applyServer(Map<String, dynamic>.from(dto),
              keepLocalContent: v.ops.any((o) => o.kind == FvOpKind.save || o.kind == FvOpKind.close) ||
                  v.localStatus == FvLocalStatus.closing,
              keepLocalAttendance: v.ops.any((o) => o.kind == FvOpKind.attendance));
          if (op.kind == FvOpKind.cancel) v.localStatus = FvLocalStatus.cancelled;
        }
        if (result['warnings'] is List) v.warnings = [for (final w in result['warnings'] as List) '$w'];
        if (op.kind == FvOpKind.attendance && result['finalized'] == true) v.localStatus = FvLocalStatus.closed;
      case FvOpKind.payment:
        v.ops.removeWhere((o) => identical(o, op));
        final p = result['payment'];
        if (p is Map) {
          final server = FvPayment.fromJson(Map<String, dynamic>.from(p));
          if (server != null) {
            v.payments.removeWhere((x) => x.id == server.id);
            v.payments.add(server);
          }
        }
      case FvOpKind.photo:
        v.ops.removeWhere((o) => identical(o, op));
        final p = result['photo'];
        final local = v.photos.where((x) => x.id == op.photoId).firstOrNull;
        if (local != null && p is Map) local.state = '${p['state'] ?? 'ready'}';
      case FvOpKind.equipment:
        v.ops.removeWhere((o) => identical(o, op));
        final id = op.body['equipment_id'];
        for (final e in v.equipment) {
          if (e.id == id) e.synced = true;
        }
      case FvOpKind.draftCustomer:
        v.ops.removeWhere((o) => identical(o, op));
        final hint = result['duplicate_hint'];
        if (hint is Map) v.warnings = {...v.warnings, 'duplicate_customer:${hint['name'] ?? ''}'}.toList();
      case FvOpKind.close:
        break;
    }
    await _commit(v);
  }

  // ------------------------------------------------------------------- pull

  /// `fieldVisitList?updated_since=` then `fieldVisitGet` for newer revisions.
  /// Server wins for status/charge/report/others; local unsynced attendance and
  /// lead content are never overwritten while their ops are queued.
  Future<void> pull() async {
    final s = _scope ??= await scope();
    if (s == null) return;
    final meta = await store.readMeta('pull');
    var since = meta != null && meta['owner'] == s.owner && meta['api'] == s.api ? meta['server_time'] as String? : null;
    String? firstServerTime;
    var page = 1;
    final changed = <String>[];
    while (true) {
      final r = await api.list(updatedSince: since, page: page, scope: s);
      firstServerTime ??= r.serverTime;
      for (final row in r.items) {
        final id = '${row['id']}';
        if (!fvIsUuid(id)) continue;
        final local = _visits[id];
        final remoteRev = BigInt.tryParse('${row['revision']}');
        final localRev = BigInt.tryParse(local?.serverRevision ?? '');
        if (local == null || localRev == null || (remoteRev != null && remoteRev > localRev)) changed.add(id);
      }
      if (r.nextPage == null || page > 50) break;
      page = r.nextPage!;
    }
    for (final id in changed) {
      final dto = await api.getVisit(id, s);
      await _lock(id, () async {
        var v = _visits[id];
        if (v == null) {
          v = FieldVisit.fromServer(dto, owner: s.owner, api: s.api, selfUserId: s.owner);
          _visits[id] = v;
        } else {
          v.applyServer(dto,
              keepLocalContent: v.ops.any((o) => o.kind == FvOpKind.save || o.kind == FvOpKind.close) ||
                  v.localStatus == FvLocalStatus.closing,
              keepLocalAttendance: v.ops.any((o) => o.kind == FvOpKind.attendance));
        }
        await _commit(v);
      });
    }
    if (firstServerTime != null) {
      await store.writeMeta('pull', {'owner': s.owner, 'api': s.api, 'server_time': firstServerTime});
    }
  }

  /// Raw JSON of what would be sent (used by tests and the pending center).
  Map<String, dynamic>? pendingSummary(String id) {
    final v = _visits[id];
    if (v == null) return null;
    return {
      'visit_id': id,
      'ops': [for (final o in v.ops) {'kind': o.kind.wire, 'state': o.state, 'key': o.key}]
    };
  }

  @visibleForTesting
  String encodeForTest(String id) => jsonEncode(_visits[id]?.toJson());
}
