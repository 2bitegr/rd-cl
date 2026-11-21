import 'dart:convert';

/// Δελτίο τεχνικού (field visit) models. Pure Dart: no Flutter, no network.
/// Money is NEVER computed here: charge figures only mirror what Office sent.
/// Minute math below is for display and local validation only.

const fvContractVersion = 1;

final _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
bool fvIsUuid(String s) => _uuidRe.hasMatch(s);

DateTime? fvParseTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  final t = DateTime.tryParse(v);
  return t?.toUtc();
}

String fvIso(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second)
      .toIso8601String();
}

DateTime fvFloorMinute(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute);
}

String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
    : <Map<String, dynamic>>[];
double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

enum FvOutcome {
  done('done'),
  pending('pending'),
  newVisit('new_visit');

  const FvOutcome(this.wire);
  final String wire;
  static FvOutcome? parse(dynamic v) {
    for (final o in values) {
      if (o.wire == v) return o;
    }
    return null;
  }
}

enum FvChargeSource {
  prepaid('prepaid'),
  invoice('invoice');

  const FvChargeSource(this.wire);
  final String wire;
  static FvChargeSource? parse(dynamic v) {
    for (final o in values) {
      if (o.wire == v) return o;
    }
    return null;
  }
}

/// Local lifecycle of the visit on this phone.
enum FvLocalStatus { draft, closing, awaiting, closed, cancelled }

// ---------------------------------------------------------------- attendance

class FvPause {
  const FvPause(this.start, [this.end]);
  final DateTime start;
  final DateTime? end;
  FvPause withEnd(DateTime e) => FvPause(start, e);
  Map<String, dynamic> toJson() =>
      {'start_utc': fvIso(start), 'end_utc': end == null ? null : fvIso(end!)};
  static FvPause? fromJson(dynamic j) {
    if (j is! Map) return null;
    final s = fvParseTime(j['start_utc']);
    return s == null ? null : FvPause(s, fvParseTime(j['end_utc']));
  }
}

/// One technician's span on a visit (full state, last-writer-wins by
/// [clientRev]).
class FvAttendance {
  FvAttendance(
      {this.arrivalAt,
      this.lat,
      this.lng,
      this.accuracyM,
      this.fixAt,
      this.gpsMissing = false,
      this.departureAt,
      List<FvPause>? pauses,
      this.clientRev = 0})
      : pauses = pauses ?? [];
  DateTime? arrivalAt, fixAt, departureAt;
  double? lat, lng, accuracyM;
  bool gpsMissing;
  List<FvPause> pauses;
  int clientRev;

  bool get arrived => arrivalAt != null;
  bool get departed => departureAt != null;
  bool get onPause => pauses.isNotEmpty && pauses.last.end == null;
  bool get isOpen => arrived && !departed;

  FvAttendance copy() => FvAttendance(
      arrivalAt: arrivalAt,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      fixAt: fixAt,
      gpsMissing: gpsMissing,
      departureAt: departureAt,
      pauses: [...pauses],
      clientRev: clientRev);

  /// Request body (besides key/client_sent_at). Server floors to the minute.
  Map<String, dynamic> toBody() => {
        'client_rev': clientRev,
        'arrival': arrivalAt == null
            ? null
            : {
                'at': fvIso(arrivalAt!),
                'lat': lat,
                'lng': lng,
                'accuracy_m': accuracyM,
                'fix_at': fixAt == null ? null : fvIso(fixAt!),
              },
        'departure_at': departureAt == null ? null : fvIso(departureAt!),
        'pauses': [for (final p in pauses) p.toJson()],
      };

  Map<String, dynamic> toJson() => {
        ...toBody(),
        'gps_missing': gpsMissing,
      };

  /// Parses both the local document and the server participant DTO.
  static FvAttendance fromJson(Map<String, dynamic> j) {
    final a = j['arrival'];
    return FvAttendance(
        arrivalAt: fvParseTime(a is Map ? a['at'] : null),
        lat: a is Map ? _d(a['lat']) : null,
        lng: a is Map ? _d(a['lng']) : null,
        accuracyM: a is Map ? _d(a['accuracy_m']) : null,
        fixAt: fvParseTime(a is Map ? a['fix_at'] : null),
        gpsMissing: j['gps_missing'] == true,
        departureAt: fvParseTime(j['departure_at']),
        pauses: [
          for (final p in (j['pauses'] as List? ?? const []))
            if (FvPause.fromJson(p) case final x?) x
        ],
        clientRev: (j['client_rev'] as num?)?.toInt() ?? 0);
  }

  int workedMinutes(DateTime now) =>
      fvWorkedMinutes(arrivalAt, departureAt, pauses, now);
}

/// Minutes between arrival and departure (or [now]) minus the union of pauses,
/// every instant floored to the minute. Display only; Office decides billing.
int fvWorkedMinutes(
    DateTime? arrival, DateTime? departure, List<FvPause> pauses, DateTime now) {
  if (arrival == null) return 0;
  final a = fvFloorMinute(arrival);
  final d = fvFloorMinute(departure ?? now);
  if (!d.isAfter(a)) return 0;
  final clipped = <(DateTime, DateTime)>[];
  for (final p in pauses) {
    var s = fvFloorMinute(p.start);
    var e = fvFloorMinute(p.end ?? d);
    if (s.isBefore(a)) s = a;
    if (e.isAfter(d)) e = d;
    if (e.isAfter(s)) clipped.add((s, e));
  }
  clipped.sort((x, y) => x.$1.compareTo(y.$1));
  var paused = Duration.zero;
  DateTime? curS, curE;
  for (final (s, e) in clipped) {
    if (curE == null || s.isAfter(curE)) {
      if (curS != null) paused += curE!.difference(curS);
      curS = s;
      curE = e;
    } else if (e.isAfter(curE)) {
      curE = e;
    }
  }
  if (curS != null) paused += curE!.difference(curS);
  final total = d.difference(a) - paused;
  return total.isNegative ? 0 : total.inMinutes;
}

/// Local mirror of the server's attendance rules. Null = valid.
String? fvValidateAttendance(FvAttendance a, DateTime now) {
  final a0 = a.arrivalAt;
  if (a0 == null) return a.departureAt != null || a.pauses.isNotEmpty ? 'arrival_required' : null;
  final limit = now.toUtc().add(const Duration(minutes: 5));
  if (a0.isAfter(limit)) return 'time_in_future';
  final d = a.departureAt;
  if (d != null) {
    if (d.isAfter(limit)) return 'time_in_future';
    if (!fvFloorMinute(d).isAfter(fvFloorMinute(a0))) return 'departure_before_arrival';
    if (d.difference(a0) > const Duration(hours: 24)) return 'span_too_long';
  }
  DateTime? prevEnd;
  for (var i = 0; i < a.pauses.length; i++) {
    final p = a.pauses[i];
    if (p.end == null && (d != null || i != a.pauses.length - 1)) return 'open_pause_invalid';
    if (p.end != null && p.end!.isBefore(p.start)) return 'pause_invalid';
    if (p.start.isBefore(a0)) return 'pause_outside';
    if (prevEnd != null && p.start.isBefore(prevEnd)) return 'pause_overlap';
    prevEnd = p.end;
  }
  if (a.pauses.length > 40) return 'too_many_pauses';
  return null;
}

class FvParticipant {
  FvParticipant(
      {required this.userId,
      required this.displayName,
      this.role = 'member',
      this.isSelf = false,
      FvAttendance? attendance,
      this.color,
      this.serverWorkedMinutes})
      : attendance = attendance ?? FvAttendance();
  final String userId, displayName, role;
  final bool isSelf;
  final String? color;
  final FvAttendance attendance;
  final int? serverWorkedMinutes;
  bool get isLead => role == 'lead';

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'role': role,
        'is_self': isSelf,
        'color': color,
        ...attendance.toJson(),
      };

  static FvParticipant fromJson(Map<String, dynamic> j) => FvParticipant(
      userId: '${j['user_id']}',
      displayName: _s(j['display_name']) ?? '',
      role: j['role'] == 'lead' ? 'lead' : 'member',
      isSelf: j['is_self'] == true,
      color: _s(j['color']),
      attendance: FvAttendance.fromJson(j),
      serverWorkedMinutes: ((j['minutes'] as Map?)?['worked'] as num?)?.toInt());
}

// ------------------------------------------------------------------- content

class FvChecklistItem {
  FvChecklistItem({this.itemId, required this.label, this.checked = false, this.note = ''});
  final String? itemId;
  final String label;
  bool checked;
  String note;
  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'label': label,
        'checked': checked,
        if (note.isNotEmpty) 'note': note,
      };
  static FvChecklistItem fromJson(Map<String, dynamic> j) => FvChecklistItem(
      itemId: _s(j['item_id']),
      label: '${j['label'] ?? ''}',
      checked: j['checked'] == true,
      note: _s(j['note']) ?? '');
}

const fvEquipmentActions = ['installed', 'serviced', 'present', 'removed'];

class FvEquipmentLine {
  FvEquipmentLine({required this.equipmentId, this.action = 'present'});
  final String equipmentId;
  String action;
  Map<String, dynamic> toJson() => {'equipment_id': equipmentId, 'action': action};
  static FvEquipmentLine fromJson(Map<String, dynamic> j) => FvEquipmentLine(
      equipmentId: '${j['equipment_id']}',
      action: fvEquipmentActions.contains(j['action']) ? j['action'] as String : 'present');
}

class FvEquipment {
  FvEquipment(
      {required this.id,
      this.customerId,
      this.draftCustomerId,
      required this.kind,
      this.brandModel = '',
      this.serialNumber = '',
      this.barcode = '',
      this.notes = '',
      this.synced = false});
  final String id;
  String? customerId, draftCustomerId;
  String kind, brandModel, serialNumber, barcode, notes;
  bool synced;
  String get title => brandModel.isEmpty ? kind : '$kind $brandModel';

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'draft_customer_id': draftCustomerId,
        'kind': kind,
        'brand_model': brandModel,
        'serial_number': serialNumber,
        'barcode': barcode,
        'notes': notes,
        'synced': synced,
      };

  /// Body of `fieldVisitEquipmentSave` (besides key / client_sent_at).
  Map<String, dynamic> toBody() => {
        'equipment_id': id,
        if (customerId != null) 'customer_id': customerId else 'draft_customer_id': draftCustomerId,
        'kind': kind,
        if (brandModel.isNotEmpty) 'brand_model': brandModel,
        if (serialNumber.isNotEmpty) 'serial_number': serialNumber,
        if (barcode.isNotEmpty) 'barcode': barcode,
        if (notes.isNotEmpty) 'notes': notes,
      };

  static FvEquipment fromJson(Map<String, dynamic> j) => FvEquipment(
      id: '${j['id'] ?? j['equipment_id']}',
      customerId: _s(j['customer_id']),
      draftCustomerId: _s(j['draft_customer_id']),
      kind: '${j['kind'] ?? ''}',
      brandModel: '${j['brand_model'] ?? ''}',
      serialNumber: '${j['serial_number'] ?? ''}',
      barcode: '${j['barcode'] ?? ''}',
      notes: '${j['notes'] ?? ''}',
      synced: j['synced'] == true || j.containsKey('revision'));
}

class FvDefective {
  FvDefective(
      {required this.id,
      required this.description,
      this.serial = '',
      this.barcode = '',
      this.condition = '',
      this.equipmentId});
  final String id;
  String description, serial, barcode, condition;
  String? equipmentId;
  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description.replaceAll('\r\n', '\n'),
        'serial': serial,
        'barcode': barcode,
        'condition': condition,
        'equipment_id': equipmentId,
      };
  static FvDefective fromJson(Map<String, dynamic> j) => FvDefective(
      id: '${j['id']}',
      description: '${j['description'] ?? ''}',
      serial: '${j['serial'] ?? ''}',
      barcode: '${j['barcode'] ?? ''}',
      condition: '${j['condition'] ?? ''}',
      equipmentId: _s(j['equipment_id']));
}

class FvPayment {
  FvPayment(
      {required this.id,
      required this.method,
      required this.amountMinor,
      required this.receivedAt,
      this.reference = '',
      this.voided = false});
  final String id, method;
  final int amountMinor; // entered by the technician, never computed
  final DateTime receivedAt;
  final String reference;
  bool voided;
  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'amount_minor': '$amountMinor',
        'received_at': fvIso(receivedAt),
        'reference': reference,
        'voided': voided,
      };
  static FvPayment? fromJson(Map<String, dynamic> j) {
    final amount = int.tryParse('${j['amount_minor']}');
    final at = fvParseTime(j['received_at']);
    if (amount == null || at == null) return null;
    return FvPayment(
        id: '${j['id']}',
        method: j['method'] == 'bank_deposit' ? 'bank_deposit' : 'cash',
        amountMinor: amount,
        receivedAt: at,
        reference: '${j['reference'] ?? ''}',
        voided: j['voided'] == true);
  }
}

class FvPhoto {
  FvPhoto(
      {required this.id,
      this.caption = '',
      this.state = 'pending',
      this.byteSize = 0,
      this.mediaType = 'image/jpeg',
      this.sha256 = ''});
  final String id;
  String caption, state, mediaType, sha256;
  int byteSize;
  Map<String, dynamic> toJson() => {
        'id': id,
        'caption': caption,
        'state': state,
        'byte_size': byteSize,
        'media_type': mediaType,
        'sha256': sha256,
      };
  static FvPhoto fromJson(Map<String, dynamic> j) => FvPhoto(
      id: '${j['id']}',
      caption: '${j['caption'] ?? ''}',
      state: '${j['state'] ?? 'pending'}',
      // Office sends bigint columns as decimal strings (`byte_size::text`).
      byteSize: int.tryParse('${j['byte_size'] ?? ''}') ?? 0,
      mediaType: '${j['media_type'] ?? 'image/jpeg'}',
      sha256: '${j['sha256'] ?? ''}');
}

// --------------------------------------------------------------------- ops

enum FvOpKind {
  save('save'),
  attendance('attendance'),
  payment('payment'),
  photo('photo'),
  equipment('equipment'),
  draftCustomer('draft_customer'),
  appointment('appointment'),
  close('close'),
  cancel('cancel');

  const FvOpKind(this.wire);
  final String wire;
  static FvOpKind? parse(dynamic v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }
}

/// One outbox entry. A body that was sent is frozen; [sentAt] marks that.
class FvOp {
  FvOp(
      {required this.key,
      required this.kind,
      required this.path,
      required this.body,
      required this.createdAt,
      this.state = 'queued',
      this.reservedAt,
      this.sentAt,
      this.notFoundAt,
      this.attempts = 0,
      this.nextRetryAt,
      this.rejected,
      this.stage = 0,
      this.photoId});
  final String key, path;
  final FvOpKind kind;
  Map<String, dynamic> body;
  final DateTime createdAt;
  // queued | unknown | rejected
  String state;
  DateTime? reservedAt, sentAt, notFoundAt, nextRetryAt;
  int attempts;
  Map<String, dynamic>? rejected;
  int stage; // photo: 0 request, 1 uploaded
  final String? photoId;

  bool get financial => kind == FvOpKind.close;
  bool get sent => sentAt != null;

  /// Marks consumed by [exantasAbandonEligible].
  Map<String, dynamic> get marks => {
        'reserved_at': reservedAt == null ? null : fvIso(reservedAt!),
        'not_found_at': notFoundAt == null ? null : fvIso(notFoundAt!),
        if (rejected != null) 'rejected': rejected,
      };

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind.wire,
        'path': path,
        'body': body,
        'created_at': fvIso(createdAt),
        'state': state,
        'reserved_at': reservedAt == null ? null : fvIso(reservedAt!),
        'sent_at': sentAt == null ? null : fvIso(sentAt!),
        'not_found_at': notFoundAt == null ? null : fvIso(notFoundAt!),
        'attempts': attempts,
        'next_retry_at': nextRetryAt == null ? null : fvIso(nextRetryAt!),
        'rejected': rejected,
        'stage': stage,
        'photo_id': photoId,
      };

  static FvOp? fromJson(dynamic j) {
    if (j is! Map) return null;
    final kind = FvOpKind.parse(j['kind']);
    final created = fvParseTime(j['created_at']);
    if (kind == null || created == null || j['key'] is! String || j['path'] is! String || j['body'] is! Map) {
      return null;
    }
    return FvOp(
        key: j['key'] as String,
        kind: kind,
        path: j['path'] as String,
        body: Map<String, dynamic>.from(j['body'] as Map),
        createdAt: created,
        state: '${j['state'] ?? 'queued'}',
        reservedAt: fvParseTime(j['reserved_at']),
        sentAt: fvParseTime(j['sent_at']),
        notFoundAt: fvParseTime(j['not_found_at']),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        nextRetryAt: fvParseTime(j['next_retry_at']),
        rejected: j['rejected'] is Map ? Map<String, dynamic>.from(j['rejected'] as Map) : null,
        stage: (j['stage'] as num?)?.toInt() ?? 0,
        photoId: _s(j['photo_id']));
  }
}

// -------------------------------------------------------------------- visit

class FieldVisit {
  FieldVisit({
    required this.id,
    required this.owner,
    required this.api,
    required this.selfUserId,
    this.serverRevision,
    this.status = 'in_progress',
    this.localStatus = FvLocalStatus.draft,
    this.source = 'mobile',
    this.customerId,
    this.draftCustomerId,
    this.customerName = '',
    this.customerIsDraft = false,
    this.customerChargeDefault,
    this.branchId,
    this.branchName = '',
    this.contactId,
    this.workItemId,
    this.workTitle = '',
    this.jobTypeId = '',
    this.jobTypeLabel = '',
    this.scheduledStart,
    this.scheduledEnd,
    this.scheduledNote = '',
    this.leadUserId = '',
    List<FvParticipant>? participants,
    this.workSummary = '',
    this.internalNote = '',
    List<FvChecklistItem>? checklist,
    List<FvEquipmentLine>? equipmentLines,
    List<FvDefective>? defectiveUnits,
    List<FvEquipment>? equipment,
    this.contentClientRev = 0,
    this.outcome,
    this.outcomeNote = '',
    this.followUpStart,
    this.chargeSource,
    this.discountBps = 0,
    this.discountReason = '',
    this.showPrices = false,
    this.afterHoursApply = false,
    this.afterHoursRateText = '',
    this.afterHoursMinutes,
    this.signerName = '',
    this.noSignature = false,
    this.signaturePngBase64,
    List<FvPayment>? payments,
    List<FvPhoto>? photos,
    this.charge,
    this.report,
    this.followUp,
    this.permissions,
    List<String>? warnings,
    this.closeRejection,
    this.lastAbandonedAt,
    this.updatedAt,
    List<FvOp>? ops,
    this.createdLocally = false,
    this.autoDepartAt,
  })  : participants = participants ?? [],
        checklist = checklist ?? [],
        equipmentLines = equipmentLines ?? [],
        defectiveUnits = defectiveUnits ?? [],
        equipment = equipment ?? [],
        payments = payments ?? [],
        photos = photos ?? [],
        warnings = warnings ?? [],
        ops = ops ?? [];

  final String id, owner, api, selfUserId;
  String? serverRevision;
  String status, source;
  FvLocalStatus localStatus;
  String? customerId, draftCustomerId, branchId, contactId, workItemId;
  String customerName, branchName, workTitle, jobTypeId, jobTypeLabel, scheduledNote, leadUserId;
  bool customerIsDraft;
  String? customerChargeDefault;
  DateTime? scheduledStart, scheduledEnd, updatedAt, lastAbandonedAt, autoDepartAt;
  List<FvParticipant> participants;
  String workSummary, internalNote;
  List<FvChecklistItem> checklist;
  List<FvEquipmentLine> equipmentLines;
  List<FvDefective> defectiveUnits;
  List<FvEquipment> equipment;
  int contentClientRev;
  FvOutcome? outcome;
  String outcomeNote;
  DateTime? followUpStart;
  FvChargeSource? chargeSource;
  int discountBps;
  String discountReason;
  bool showPrices, noSignature;

  /// Per-visit after-hours pricing input (technician-owned, persisted offline).
  /// [afterHoursRateText] is the raw comma-decimal text of «Τιμή ανά ώρα (€)».
  bool afterHoursApply;
  String afterHoursRateText;

  /// Last after-hours minute count Office reported (preview/charge). Display
  /// gate only; the app never classifies minutes itself.
  int? afterHoursMinutes;
  String signerName;
  String? signaturePngBase64;
  List<FvPayment> payments;
  List<FvPhoto> photos;
  Map<String, dynamic>? charge, report, followUp, permissions, closeRejection;
  List<String> warnings;
  List<FvOp> ops;
  bool createdLocally;

  bool get isLead => leadUserId == selfUserId;
  bool get hasPendingOps => ops.isNotEmpty;
  bool get hasUnsynced => ops.any((o) => o.state != 'rejected') ;
  bool get serverKnown => serverRevision != null;
  FvParticipant? get self {
    for (final p in participants) {
      if (p.userId == selfUserId || p.isSelf) return p;
    }
    return null;
  }

  FvAttendance get myAttendance => self?.attendance ?? FvAttendance();
  bool get isClosedOrCancelled =>
      localStatus == FvLocalStatus.closed || localStatus == FvLocalStatus.cancelled;
  bool get contentLocked =>
      localStatus != FvLocalStatus.draft || !isLead;
  bool get isAppointment => status == 'scheduled' && !myAttendance.arrived;
  bool get customerPending => customerIsDraft || (customerId == null && draftCustomerId != null);

  FvOp? opOf(FvOpKind k) {
    for (final o in ops) {
      if (o.kind == k) return o;
    }
    return null;
  }

  FvOp? get closeOp => opOf(FvOpKind.close);

  int totalWorkedMinutes(DateTime now) =>
      participants.fold(0, (a, p) => a + p.attendance.workedMinutes(now));

  /// Identity fields used by `create` and by the close guard.
  Map<String, dynamic> createBody() => {
        if (customerId != null) 'customer_id': customerId else 'draft_customer_id': draftCustomerId,
        if (branchId != null) 'branch_id': branchId,
        if (contactId != null) 'contact_id': contactId,
        if (workItemId != null) 'work_item_id': workItemId,
        'job_type_id': jobTypeId,
        'participants': [for (final p in participants) p.userId],
      };

  Map<String, dynamic> contentBody() => {
        'work_summary': workSummary,
        'internal_note': internalNote,
        'checklist': [for (final c in checklist) c.toJson()],
        'equipment_lines': [for (final l in equipmentLines) l.toJson()],
        'defective_units': [for (final d in defectiveUnits) d.toJson()],
      };

  Map<String, dynamic> toJson() => {
        'visit_id': id,
        'owner': owner,
        'api': api,
        'self_user_id': selfUserId,
        'server_revision': serverRevision,
        'status': status,
        'status_local': localStatus.name,
        'source': source,
        'customer': {
          'id': customerId,
          'draft_customer_id': draftCustomerId,
          'name': customerName,
          'is_draft': customerIsDraft,
          'charge_source_default': customerChargeDefault,
        },
        'branch': {'id': branchId, 'name': branchName},
        'contact_id': contactId,
        'work_item': {'id': workItemId, 'title': workTitle},
        'job_type': {'id': jobTypeId, 'label_el': jobTypeLabel},
        'scheduled_start': scheduledStart == null ? null : fvIso(scheduledStart!),
        'scheduled_end': scheduledEnd == null ? null : fvIso(scheduledEnd!),
        'scheduled_note': scheduledNote,
        'lead_user_id': leadUserId,
        'participants': [for (final p in participants) p.toJson()],
        'local': {
          ...contentBody(),
          'content_client_rev': contentClientRev,
          'equipment': [for (final e in equipment) e.toJson()],
          'outcome': outcome?.wire,
          'outcome_note': outcomeNote,
          'follow_up_start': followUpStart == null ? null : fvIso(followUpStart!),
          'charge_source': chargeSource?.wire,
          'discount_bps': discountBps,
          'discount_reason': discountReason,
          'show_prices': showPrices,
          'after_hours_apply': afterHoursApply,
          'after_hours_rate_text': afterHoursRateText,
          'after_hours_minutes': afterHoursMinutes,
          'signer_name': signerName,
          'no_signature': noSignature,
          'signature_png_base64': signaturePngBase64,
          'auto_depart_at': autoDepartAt == null ? null : fvIso(autoDepartAt!),
        },
        'payments': [for (final p in payments) p.toJson()],
        'photos': [for (final p in photos) p.toJson()],
        'charge': charge,
        'report': report,
        'follow_up': followUp,
        'permissions': permissions,
        'warnings': warnings,
        'close_rejection': closeRejection,
        'last_abandoned_at': lastAbandonedAt == null ? null : fvIso(lastAbandonedAt!),
        'updated_at': updatedAt == null ? null : fvIso(updatedAt!),
        'created_locally': createdLocally,
        'ops': [for (final o in ops) o.toJson()],
      };

  String encode() => jsonEncode(toJson());

  static FieldVisit? decode(String text) {
    try {
      final j = jsonDecode(text);
      return j is Map ? fromJson(Map<String, dynamic>.from(j)) : null;
    } catch (_) {
      return null;
    }
  }

  static FieldVisit? fromJson(Map<String, dynamic> j) {
    final id = _s(j['visit_id']);
    if (id == null || !fvIsUuid(id) || j['owner'] is! String || j['api'] is! String) {
      return null;
    }
    final c = Map<String, dynamic>.from(j['customer'] as Map? ?? const {});
    final b = Map<String, dynamic>.from(j['branch'] as Map? ?? const {});
    final w = Map<String, dynamic>.from(j['work_item'] as Map? ?? const {});
    final t = Map<String, dynamic>.from(j['job_type'] as Map? ?? const {});
    final l = Map<String, dynamic>.from(j['local'] as Map? ?? const {});
    return FieldVisit(
      id: id,
      owner: j['owner'] as String,
      api: j['api'] as String,
      selfUserId: '${j['self_user_id'] ?? ''}',
      serverRevision: _s(j['server_revision']),
      status: '${j['status'] ?? 'in_progress'}',
      localStatus: FvLocalStatus.values.firstWhere(
          (e) => e.name == j['status_local'],
          orElse: () => FvLocalStatus.draft),
      source: '${j['source'] ?? 'mobile'}',
      customerId: _s(c['id']),
      draftCustomerId: _s(c['draft_customer_id']),
      customerName: '${c['name'] ?? ''}',
      customerIsDraft: c['is_draft'] == true,
      customerChargeDefault: _s(c['charge_source_default']),
      branchId: _s(b['id']),
      branchName: '${b['name'] ?? ''}',
      contactId: _s(j['contact_id']),
      workItemId: _s(w['id']),
      workTitle: '${w['title'] ?? ''}',
      jobTypeId: '${t['id'] ?? ''}',
      jobTypeLabel: '${t['label_el'] ?? ''}',
      scheduledStart: fvParseTime(j['scheduled_start']),
      scheduledEnd: fvParseTime(j['scheduled_end']),
      scheduledNote: '${j['scheduled_note'] ?? ''}',
      leadUserId: '${j['lead_user_id'] ?? ''}',
      participants: [for (final p in _maps(j['participants'])) FvParticipant.fromJson(p)],
      workSummary: '${l['work_summary'] ?? ''}',
      internalNote: '${l['internal_note'] ?? ''}',
      checklist: [for (final x in _maps(l['checklist'])) FvChecklistItem.fromJson(x)],
      equipmentLines: [for (final x in _maps(l['equipment_lines'])) FvEquipmentLine.fromJson(x)],
      defectiveUnits: [for (final x in _maps(l['defective_units'])) FvDefective.fromJson(x)],
      equipment: [for (final x in _maps(l['equipment'])) FvEquipment.fromJson(x)],
      contentClientRev: (l['content_client_rev'] as num?)?.toInt() ?? 0,
      outcome: FvOutcome.parse(l['outcome']),
      outcomeNote: '${l['outcome_note'] ?? ''}',
      followUpStart: fvParseTime(l['follow_up_start']),
      chargeSource: FvChargeSource.parse(l['charge_source']),
      discountBps: (l['discount_bps'] as num?)?.toInt() ?? 0,
      discountReason: '${l['discount_reason'] ?? ''}',
      showPrices: l['show_prices'] == true,
      afterHoursApply: l['after_hours_apply'] == true,
      afterHoursRateText: '${l['after_hours_rate_text'] ?? ''}',
      afterHoursMinutes: (l['after_hours_minutes'] as num?)?.toInt(),
      signerName: '${l['signer_name'] ?? ''}',
      noSignature: l['no_signature'] == true,
      signaturePngBase64: _s(l['signature_png_base64']),
      autoDepartAt: fvParseTime(l['auto_depart_at']),
      payments: [
        for (final x in _maps(j['payments']))
          if (FvPayment.fromJson(x) case final p?) p
      ],
      photos: [for (final x in _maps(j['photos'])) FvPhoto.fromJson(x)],
      charge: j['charge'] is Map ? Map<String, dynamic>.from(j['charge'] as Map) : null,
      report: j['report'] is Map ? Map<String, dynamic>.from(j['report'] as Map) : null,
      followUp: j['follow_up'] is Map ? Map<String, dynamic>.from(j['follow_up'] as Map) : null,
      permissions: j['permissions'] is Map ? Map<String, dynamic>.from(j['permissions'] as Map) : null,
      warnings: [for (final x in (j['warnings'] as List? ?? const [])) '$x'],
      closeRejection: j['close_rejection'] is Map
          ? Map<String, dynamic>.from(j['close_rejection'] as Map)
          : null,
      lastAbandonedAt: fvParseTime(j['last_abandoned_at']),
      updatedAt: fvParseTime(j['updated_at']),
      createdLocally: j['created_locally'] == true,
      ops: [
        for (final o in (j['ops'] as List? ?? const []))
          if (FvOp.fromJson(o) case final op?) op
      ],
    );
  }

  /// Builds a local visit from a server VisitDto.
  static FieldVisit fromServer(Map<String, dynamic> dto,
      {required String owner, required String api, required String selfUserId}) {
    final v = FieldVisit(id: '${dto['id']}', owner: owner, api: api, selfUserId: selfUserId);
    v.applyServer(dto, keepLocalContent: false, keepLocalAttendance: false);
    v.createdLocally = false;
    return v;
  }

  /// Server wins for status, charge, report, other participants and shared
  /// facts. Own unsynced attendance and lead content are kept while ops that
  /// carry them are still queued ([keepLocalAttendance] / [keepLocalContent]).
  void applyServer(Map<String, dynamic> dto,
      {required bool keepLocalContent, required bool keepLocalAttendance}) {
    final customer = Map<String, dynamic>.from(dto['customer'] as Map? ?? const {});
    final branch = dto['branch'] is Map ? Map<String, dynamic>.from(dto['branch'] as Map) : null;
    final contact = dto['contact'] is Map ? Map<String, dynamic>.from(dto['contact'] as Map) : null;
    final work = dto['work_item'] is Map ? Map<String, dynamic>.from(dto['work_item'] as Map) : null;
    final job = Map<String, dynamic>.from(dto['job_type'] as Map? ?? const {});
    serverRevision = '${dto['revision'] ?? serverRevision ?? ''}'.isEmpty
        ? serverRevision
        : '${dto['revision'] ?? serverRevision}';
    status = '${dto['status'] ?? status}';
    source = '${dto['source'] ?? source}';
    updatedAt = fvParseTime(dto['updated_at']) ?? updatedAt;
    customerId = _s(customer['id']);
    draftCustomerId = _s(customer['draft_customer_id']);
    customerName = '${customer['name'] ?? customerName}';
    customerIsDraft = customer['is_draft'] == true;
    customerChargeDefault = _s(customer['charge_source_default']) ?? customerChargeDefault;
    branchId = _s(branch?['id']);
    branchName = '${branch?['name'] ?? ''}';
    contactId = _s(contact?['id']);
    workItemId = _s(work?['id']);
    workTitle = '${work?['title'] ?? ''}';
    jobTypeId = '${job['id'] ?? jobTypeId}';
    jobTypeLabel = '${job['label_el'] ?? jobTypeLabel}';
    scheduledStart = fvParseTime(dto['scheduled_start']);
    scheduledEnd = fvParseTime(dto['scheduled_end']);
    scheduledNote = '${dto['scheduled_note'] ?? ''}';
    leadUserId = '${dto['lead_user_id'] ?? leadUserId}';

    final mine = self?.attendance;
    final incoming = [for (final p in _maps(dto['participants'])) FvParticipant.fromJson(p)];
    participants = [
      for (final p in incoming)
        if (p.userId == selfUserId && keepLocalAttendance && mine != null)
          FvParticipant(
              userId: p.userId,
              displayName: p.displayName,
              role: p.role,
              isSelf: true,
              color: p.color,
              attendance: mine,
              serverWorkedMinutes: p.serverWorkedMinutes)
        else
          FvParticipant(
              userId: p.userId,
              displayName: p.displayName,
              role: p.role,
              isSelf: p.userId == selfUserId || p.isSelf,
              color: p.color,
              attendance: p.attendance,
              serverWorkedMinutes: p.serverWorkedMinutes)
    ];
    if (!keepLocalContent) {
      workSummary = '${dto['work_summary'] ?? workSummary}';
      internalNote = '${dto['internal_note'] ?? internalNote}';
      if (dto['checklist'] is List) checklist = [for (final x in _maps(dto['checklist'])) FvChecklistItem.fromJson(x)];
      if (dto['equipment_lines'] is List) equipmentLines = [for (final x in _maps(dto['equipment_lines'])) FvEquipmentLine.fromJson(x)];
      if (dto['defective_units'] is List) defectiveUnits = [for (final x in _maps(dto['defective_units'])) FvDefective.fromJson(x)];
      final sc = (dto['client_rev'] as num?)?.toInt();
      if (sc != null && sc > contentClientRev) contentClientRev = sc;
      outcome = FvOutcome.parse(dto['outcome']) ?? outcome;
      outcomeNote = '${dto['outcome_note'] ?? outcomeNote}';
      chargeSource = FvChargeSource.parse(dto['charge_source']) ?? chargeSource;
      if (dto['discount_bps'] is num) discountBps = (dto['discount_bps'] as num).toInt();
      if (dto['show_prices'] is bool) showPrices = dto['show_prices'] as bool;
      final sig = dto['signature'];
      if (sig is Map) {
        signerName = '${sig['signer_name'] ?? signerName}';
        noSignature = sig['no_signature'] == true;
      }
    }
    // Payments: server rows + local ones the server has not echoed yet.
    final serverPayments = [
      for (final x in _maps(dto['payments']))
        if (FvPayment.fromJson(x) case final p?) p
    ];
    final queued = {
      for (final o in ops)
        if (o.kind == FvOpKind.payment) '${o.body['payment_id']}'
    };
    payments = [
      ...serverPayments,
      for (final p in payments)
        if (queued.contains(p.id) && !serverPayments.any((s) => s.id == p.id)) p
    ];
    if (dto['photos'] is List) {
      final serverPhotos = [for (final x in _maps(dto['photos'])) FvPhoto.fromJson(x)];
      final inflight = {
        for (final o in ops)
          if (o.kind == FvOpKind.photo) o.photoId
      };
      photos = [
        ...serverPhotos,
        for (final p in photos)
          if (inflight.contains(p.id) && !serverPhotos.any((s) => s.id == p.id)) p
      ];
    }
    charge = dto['charge'] is Map ? Map<String, dynamic>.from(dto['charge'] as Map) : null;
    report = dto['report'] is Map ? Map<String, dynamic>.from(dto['report'] as Map) : null;
    followUp = dto['follow_up'] is Map ? Map<String, dynamic>.from(dto['follow_up'] as Map) : null;
    permissions = dto['permissions'] is Map ? Map<String, dynamic>.from(dto['permissions'] as Map) : null;
    // Local lifecycle follows the server once it is authoritative.
    switch (status) {
      case 'closed':
        localStatus = FvLocalStatus.closed;
      case 'cancelled':
        localStatus = FvLocalStatus.cancelled;
      case 'awaiting_participants':
        localStatus = FvLocalStatus.awaiting;
      default:
        if (localStatus == FvLocalStatus.awaiting) localStatus = FvLocalStatus.draft;
    }
  }
}

// ------------------------------------------------------------ config / misc

class FvJobType {
  const FvJobType(this.id, this.code, this.label, this.checklist);
  final String id, code, label;
  final List<({String id, String label})> checklist;
}

class FvPhrase {
  const FvPhrase(this.id, this.text, this.jobTypeId);
  final String id, text;
  final String? jobTypeId;
}

class FvStaff {
  const FvStaff(this.id, this.name, this.color);
  final String id, name;
  final String? color;
}

class FvConfig {
  const FvConfig(
      {this.jobTypes = const [],
      this.phrases = const [],
      this.staff = const [],
      this.myDiscountLimitBps = 0,
      this.defaultAfterHoursRateMinor,
      this.revision = ''});
  final List<FvJobType> jobTypes;
  final List<FvPhrase> phrases;
  final List<FvStaff> staff;
  final int myDiscountLimitBps;

  /// Admin's `default_after_hours_rate_minor_per_hour` (null = no suggestion).
  /// Only ever a prefill; never applied automatically.
  final int? defaultAfterHoursRateMinor;
  final String revision;

  FvJobType? jobType(String id) {
    for (final j in jobTypes) {
      if (j.id == id) return j;
    }
    return null;
  }

  List<FvPhrase> phrasesFor(String jobTypeId) =>
      [for (final p in phrases) if (p.jobTypeId == null || p.jobTypeId == jobTypeId) p];

  Map<String, dynamic> toJson() => {
        'job_types': [
          for (final j in jobTypes)
            {
              'id': j.id,
              'code': j.code,
              'label_el': j.label,
              'checklist': [for (final c in j.checklist) {'id': c.id, 'label_el': c.label}],
            }
        ],
        'phrases': [for (final p in phrases) {'id': p.id, 'text_el': p.text, 'job_type_id': p.jobTypeId}],
        'eligible_staff': [for (final s in staff) {'id': s.id, 'display_name': s.name, 'color': s.color}],
        'my_discount_limit_bps': myDiscountLimitBps,
        'default_after_hours_rate_minor_per_hour':
            defaultAfterHoursRateMinor == null ? null : '$defaultAfterHoursRateMinor',
        'config_revision': revision,
      };

  static FvConfig fromJson(Map<String, dynamic> j) => FvConfig(
      jobTypes: [
        for (final x in _maps(j['job_types']))
          FvJobType('${x['id']}', '${x['code'] ?? ''}', '${x['label_el'] ?? ''}', [
            for (final c in _maps(x['checklist'])) (id: '${c['id']}', label: '${c['label_el'] ?? ''}')
          ])
      ],
      phrases: [
        for (final x in _maps(j['phrases'])) FvPhrase('${x['id']}', '${x['text_el'] ?? ''}', _s(x['job_type_id']))
      ],
      staff: [
        for (final x in _maps(j['eligible_staff'])) FvStaff('${x['id']}', '${x['display_name'] ?? ''}', _s(x['color']))
      ],
      myDiscountLimitBps: (j['my_discount_limit_bps'] as num?)?.toInt() ?? 0,
      defaultAfterHoursRateMinor: fvParseMinorString(j['default_after_hours_rate_minor_per_hour'] ??
          (j['settings'] is Map ? (j['settings'] as Map)['default_after_hours_rate_minor_per_hour'] : null)),
      revision: '${j['config_revision'] ?? ''}');
}

/// Reasons a visit cannot be closed yet. Empty = ready. Keys are stable ids;
/// the UI maps them to Greek copy.
List<String> fvCloseBlockers(FieldVisit v, {required int discountLimitBps}) {
  final out = <String>[];
  if (!v.isLead) out.add('not_lead');
  if (!v.myAttendance.arrived) out.add('close_requires_arrival');
  if (v.outcome == null) out.add('outcome_required');
  if (v.chargeSource == null) out.add('charge_source_required');
  if (v.afterHoursApply) {
    final issue = fvAfterHoursRateIssue(v.afterHoursRateText);
    if (issue != null) out.add(issue);
  }
  if (v.discountBps < 0 || v.discountBps > discountLimitBps) out.add('discount_exceeds_limit');
  final hasSig = v.signaturePngBase64 != null && v.signaturePngBase64!.isNotEmpty;
  if (!hasSig && !v.noSignature) out.add('signature_required');
  if (hasSig && v.signerName.trim().isEmpty) out.add('signer_required');
  if (v.myAttendance.onPause) out.add('open_pause');
  if (v.jobTypeId.isEmpty) out.add('job_type_required');
  return out;
}

/// "1 ώρα 05 λεπτά" style helper used by summary lines (display only).
String fvFormatMinutes(int minutes) {
  if (minutes < 60) return "$minutes'";
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h ώρ.' : "$h ώρ. $m'";
}

/// 00:34 style elapsed clock for the work screen.
String fvFormatClock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Parses a typed euro amount ("50", "50,5", "50.00") into minor units. Input
/// handling only; the app never derives any other amount.
int? fvParseEuroToMinor(String text) {
  final t = text.trim().replaceAll(' ', '').replaceAll('€', '');
  final m = RegExp(r'^(\d{1,9})(?:[.,](\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(frac.isEmpty ? '00' : frac);
}

/// Maximum accepted after-hours hourly rate: 1.000,00 €/ώρα in minor units.
const int fvAfterHoursRateMaxMinor = 100000;

/// Parses a typed after-hours rate. Comma decimal only ("60", "60,5",
/// "1000,00"); returns integer minor units, or null when empty, malformed or
/// outside 0 < x <= 1000,00.
int? fvParseAfterHoursRate(String text) {
  final m = RegExp(r'^(\d{1,4})(?:,(\d{1,2}))?$').firstMatch(text.trim());
  if (m == null) return null;
  final minor = int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '0').padRight(2, '0'));
  return minor > 0 && minor <= fvAfterHoursRateMaxMinor ? minor : null;
}

/// null = valid; otherwise a stable blocker id (Greek copy in FvStrings).
String? fvAfterHoursRateIssue(String text) {
  if (text.trim().isEmpty) return 'after_hours_rate_required';
  return fvParseAfterHoursRate(text) == null ? 'invalid_after_hours_rate' : null;
}

/// Minor units -> comma-decimal field text ("6000" -> "60,00").
String fvRateFieldText(int minor) => '${minor ~/ 100},${(minor % 100).toString().padLeft(2, '0')}';

/// Integer minor value from an Office string/number (digits only), else null.
int? fvParseMinorString(dynamic v) {
  if (v is num) return v == v.truncate() ? v.toInt() : null;
  if (v is String && RegExp(r'^\d{1,18}$').hasMatch(v)) return int.parse(v);
  return null;
}

/// The `after_hours` input of the close/preview payload.
Map<String, dynamic> fvAfterHoursPayload(FieldVisit v) {
  final rate = v.afterHoursApply ? fvParseAfterHoursRate(v.afterHoursRateText) : null;
  return rate == null ? {'apply': false} : {'apply': true, 'rate_minor_per_hour': '$rate'};
}

/// Read-only view of the ChargeDto after-hours fields Office returns
/// (`after_hours_minutes`, `after_hours_apply`, `after_hours_rate_minor_per_hour`,
/// `surcharge_minor`). The legacy `surcharge_bps` is intentionally ignored.
class FvChargeAfterHours {
  const FvChargeAfterHours(this.minutes, this.apply, this.rateMinorPerHour, this.surchargeMinor);
  final int minutes;
  final bool apply;
  final int? rateMinorPerHour;
  final int? surchargeMinor;

  static FvChargeAfterHours? fromCharge(Map<String, dynamic>? c) {
    if (c == null) return null;
    final sur = c['surcharge_minor'];
    return FvChargeAfterHours(
        fvParseMinorString(c['after_hours_minutes']) ?? 0,
        c['after_hours_apply'] == true,
        fvParseMinorString(c['after_hours_rate_minor_per_hour']),
        sur is num ? sur.toInt() : (sur is String ? int.tryParse(sur) : null));
  }
}
