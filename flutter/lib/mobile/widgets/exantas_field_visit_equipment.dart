import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../models/exantas_field_visit.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_list_row.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_sheet.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'exantas_field_visit_attendance.dart';

/// Camera scan page. Camera permission is requested by the scanner itself, only
/// when this page opens. Pops with the scanned text (or a typed one).
class FvBarcodeScanPage extends StatefulWidget {
  const FvBarcodeScanPage({super.key});
  @override
  State<FvBarcodeScanPage> createState() => _FvBarcodeScanPageState();
}

class _FvBarcodeScanPageState extends State<FvBarcodeScanPage> {
  final qrKey = GlobalKey(debugLabel: 'fv-scan');
  final manual = TextEditingController();
  StreamSubscription<Barcode>? sub;
  bool denied = false, done = false;

  @override
  void dispose() {
    sub?.cancel();
    manual.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (done || code.trim().isEmpty) return;
    done = true;
    Navigator.of(context).pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.scanTitle)),
        body: Column(children: [
          Expanded(
              child: denied
                  ? const ExEmptyState(
                      icon: Icons.no_photography_outlined,
                      title: FvStrings.cameraDenied,
                      message: FvStrings.cameraDeniedHint)
                  : QRView(
                      key: qrKey,
                      onQRViewCreated: (c) => sub = c.scannedDataStream.listen((b) {
                        final code = b.code;
                        if (code != null) _finish(code);
                      }),
                      overlay: QrScannerOverlayShape(
                          borderColor: t.accent, borderRadius: 10, borderLength: 30, borderWidth: 8, cutOutSize: 220),
                      onPermissionSet: (c, ok) {
                        if (!ok && mounted) setState(() => denied = true);
                      })),
          Padding(
              padding: const EdgeInsets.all(ExantasTokens.gutter),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: manual,
                        decoration: const InputDecoration(labelText: FvStrings.typeBarcode),
                        onSubmitted: _finish)),
                const SizedBox(width: ExantasTokens.space2),
                IconButton.filled(
                    tooltip: FvStrings.useCode,
                    onPressed: () => _finish(manual.text),
                    icon: const Icon(Icons.check)),
              ])),
        ]));
  }
}

Future<String?> fvScanBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const FvBarcodeScanPage()));

/// Register a device (also used after a scan found nothing).
Future<FvEquipment?> showFvEquipmentSheet(BuildContext context, {String barcode = ''}) {
  final kind = TextEditingController(), brand = TextEditingController(), serial = TextEditingController();
  final code = TextEditingController(text: barcode), notes = TextEditingController();
  String? error;
  return showExSheet<FvEquipment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(FvStrings.newEquipment, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: ExantasTokens.space3),
                TextField(
                    key: const ValueKey('fv-eq-kind'),
                    controller: kind,
                    decoration: InputDecoration(labelText: FvStrings.equipmentKind, errorText: error)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: brand, decoration: const InputDecoration(labelText: FvStrings.equipmentBrand)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: serial, decoration: const InputDecoration(labelText: FvStrings.equipmentSerial)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: code, decoration: const InputDecoration(labelText: FvStrings.equipmentBarcode)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: notes, decoration: const InputDecoration(labelText: FvStrings.equipmentNotes)),
                const SizedBox(height: ExantasTokens.space4),
                FilledButton(
                    key: const ValueKey('fv-eq-save'),
                    onPressed: () {
                      if (kind.text.trim().isEmpty) {
                        set(() => error = FvStrings.equipmentKindRequired);
                        return;
                      }
                      Navigator.of(ctx).pop(FvEquipment(
                          id: const Uuid().v4(),
                          kind: kind.text.trim(),
                          brandModel: brand.text.trim(),
                          serialNumber: serial.text.trim(),
                          barcode: code.text.trim(),
                          notes: notes.text.trim()));
                    },
                    child: const Text(FvStrings.saveToRegister)),
              ])));
}

Future<FvDefective?> showFvDefectiveSheet(BuildContext context) {
  final description = TextEditingController(), serial = TextEditingController(), condition = TextEditingController();
  String? error;
  return showExSheet<FvDefective>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(FvStrings.defectiveTitle, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: ExantasTokens.space3),
                TextField(
                    key: const ValueKey('fv-def-description'),
                    controller: description,
                    decoration: InputDecoration(labelText: FvStrings.defectiveDescription, errorText: error)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: serial, decoration: const InputDecoration(labelText: FvStrings.equipmentSerial)),
                const SizedBox(height: ExantasTokens.space3),
                TextField(controller: condition, decoration: const InputDecoration(labelText: FvStrings.defectiveCondition)),
                const SizedBox(height: ExantasTokens.space4),
                FilledButton(
                    key: const ValueKey('fv-def-save'),
                    onPressed: () {
                      if (description.text.trim().isEmpty) {
                        set(() => error = FvStrings.defectiveDescriptionRequired);
                        return;
                      }
                      Navigator.of(ctx).pop(FvDefective(
                          id: const Uuid().v4(),
                          description: description.text.trim(),
                          serial: serial.text.trim(),
                          condition: condition.text.trim()));
                    },
                    child: const Text(FvStrings.defectiveSave)),
              ])));
}

/// Screen 4: equipment register, defective receipt, photos, internal note.
class FvEquipmentPage extends StatefulWidget {
  const FvEquipmentPage({super.key, required this.env, required this.visitId});
  final FvEnv env;
  final String visitId;
  @override
  State<FvEquipmentPage> createState() => _FvEquipmentPageState();
}

class _FvEquipmentPageState extends State<FvEquipmentPage> {
  late final note = TextEditingController(text: widget.env.sync.visit(widget.visitId)?.internalNote ?? '');
  String? error, info;
  bool busy = false;

  @override
  void dispose() {
    _saveNote();
    note.dispose();
    super.dispose();
  }

  void _saveNote() {
    final v = widget.env.sync.visit(widget.visitId);
    if (v == null || v.contentLocked || v.internalNote == note.text) return;
    unawaited(widget.env.sync.editContent(v.id, (x) => x.internalNote = note.text).catchError((_) {}));
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await action();
      unawaited(widget.env.sync.sync().catchError((_) {}));
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _scan() => _guard(() async {
        final code = await widget.env.scanBarcode(context);
        if (code == null || code.isEmpty || !mounted) return;
        final sync = widget.env.sync;
        final v = sync.visit(widget.visitId)!;
        FvEquipment? hit;
        for (final e in v.equipment) {
          if (e.barcode.toLowerCase() == code.toLowerCase()) hit = e;
        }
        if (hit == null && v.customerId != null) {
          try {
            final found = await sync.api.equipmentList(customerId: v.customerId, barcode: code, scope: await sync.scope());
            if (found.isNotEmpty) hit = found.first;
          } catch (_) {
            // Offline: register it locally below.
          }
        }
        if (hit != null) {
          await sync.saveEquipment(v.id, hit, action: 'present');
          if (mounted) setState(() => info = FvStrings.inRegister(hit!.title));
          return;
        }
        if (!mounted) return;
        final created = await showFvEquipmentSheet(context, barcode: code);
        if (created != null) await sync.saveEquipment(v.id, created, action: 'installed');
      });

  Future<void> _add() => _guard(() async {
        final created = await showFvEquipmentSheet(context);
        if (created != null) await widget.env.sync.saveEquipment(widget.visitId, created, action: 'installed');
      });

  Future<void> _defective() => _guard(() async {
        final d = await showFvDefectiveSheet(context);
        if (d == null) return;
        await widget.env.sync.editContent(widget.visitId, (x) => x.defectiveUnits.add(d));
      });

  Future<void> _photo() => _guard(() async {
        final p = await widget.env.pickPhoto();
        if (p == null) return;
        await widget.env.sync.addPhoto(widget.visitId, p.bytes, mediaType: p.mediaType);
      });

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.equipmentTitle)),
        body: ListenableBuilder(
            listenable: widget.env.sync,
            builder: (context, _) {
              final v = widget.env.sync.visit(widget.visitId);
              if (v == null) return const SizedBox.shrink();
              final byId = {for (final e in v.equipment) e.id: e};
              final locked = v.contentLocked;
              return ColoredBox(
                  color: t.surfaceAlt,
                  child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
                    if (busy) const LinearProgressIndicator(minHeight: 2),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
                          child: Text(error!, style: text.bodyMedium?.copyWith(color: t.danger))),
                    if (info != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
                          child: Text(info!, style: text.bodyMedium?.copyWith(color: t.success))),
                    Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                      FilledButton.icon(
                          key: const ValueKey('fv-scan'),
                          onPressed: busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text(FvStrings.scan)),
                      OutlinedButton.icon(
                          key: const ValueKey('fv-eq-add'),
                          onPressed: busy ? null : _add,
                          icon: const Icon(Icons.add),
                          label: const Text(FvStrings.newEquipment)),
                    ]),
                    const SizedBox(height: ExantasTokens.space2),
                    Text(FvStrings.scanHint, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                    const SizedBox(height: ExantasTokens.space3),
                    const ExSectionHeader(FvStrings.equipmentLines),
                    const SizedBox(height: ExantasTokens.space2),
                    if (v.equipmentLines.isEmpty)
                      const ExCard(padding: EdgeInsets.zero, child: ExEmptyState(icon: Icons.devices_other_outlined, title: FvStrings.noEquipment))
                    else
                      for (final line in v.equipmentLines)
                        Padding(
                            padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
                            child: ExCard(
                                key: ValueKey('fv-line-${line.equipmentId}'),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(byId[line.equipmentId]?.title ?? FvStrings.unknownEquipment, style: text.titleSmall)),
                                    ExStatusPill(byId[line.equipmentId]?.synced == true ? FvStrings.inRegisterShort : FvStrings.newInRegister,
                                        status: byId[line.equipmentId]?.synced == true ? ExStatus.success : ExStatus.info),
                                  ]),
                                  if ((byId[line.equipmentId]?.serialNumber ?? '').isNotEmpty)
                                    Text('S/N ${byId[line.equipmentId]!.serialNumber}', style: text.bodySmall?.copyWith(color: t.textSecondary)),
                                  const SizedBox(height: ExantasTokens.space2),
                                  Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space1, children: [
                                    for (final a in fvEquipmentActions)
                                      ChoiceChip(
                                          showCheckmark: false,
                                          label: Text(FvStrings.equipmentAction(a)),
                                          selected: line.action == a,
                                          onSelected: locked
                                              ? null
                                              : (_) => _guard(() => widget.env.sync.editContent(v.id, (x) {
                                                    for (final l in x.equipmentLines) {
                                                      if (l.equipmentId == line.equipmentId) l.action = a;
                                                    }
                                                  }))),
                                    if (!locked)
                                      TextButton(
                                          onPressed: () => _guard(() => widget.env.sync.editContent(v.id, (x) => x.equipmentLines.removeWhere((l) => l.equipmentId == line.equipmentId))),
                                          child: const Text(FvStrings.remove)),
                                  ]),
                                ]))),
                    const SizedBox(height: ExantasTokens.space3),
                    ExSectionHeader(FvStrings.defectiveTitle,
                        action: locked ? null : TextButton(key: const ValueKey('fv-defective-add'), onPressed: busy ? null : _defective, child: const Text(FvStrings.add))),
                    const SizedBox(height: ExantasTokens.space2),
                    if (v.defectiveUnits.isEmpty)
                      Text(FvStrings.noDefective, style: text.bodySmall?.copyWith(color: t.textSecondary))
                    else
                      for (final d in v.defectiveUnits)
                        ExCard(
                            padding: EdgeInsets.zero,
                            child: ExListRow(
                                title: d.description,
                                subtitle: [if (d.serial.isNotEmpty) 'S/N ${d.serial}', if (d.condition.isNotEmpty) d.condition].join(' · '),
                                icon: Icons.build_circle_outlined,
                                trailing: locked
                                    ? const ExStatusPill(FvStrings.defectiveStatus, status: ExStatus.warning)
                                    : IconButton(
                                        tooltip: FvStrings.remove,
                                        onPressed: () => _guard(() => widget.env.sync.editContent(v.id, (x) => x.defectiveUnits.removeWhere((u) => u.id == d.id))),
                                        icon: const Icon(Icons.close)))),
                    const SizedBox(height: ExantasTokens.space3),
                    ExSectionHeader(FvStrings.photosTitle,
                        action: TextButton(key: const ValueKey('fv-photo-add'), onPressed: busy ? null : _photo, child: const Text(FvStrings.add))),
                    Text(FvStrings.photosInternal, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                    const SizedBox(height: ExantasTokens.space2),
                    Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                      for (final p in v.photos)
                        Semantics(
                            label: FvStrings.photoState(p.state),
                            child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(ExantasTokens.radiusMd), border: Border.all(color: t.border)),
                                child: Icon(p.state == 'ready' ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined, color: t.accent))),
                    ]),
                    const SizedBox(height: ExantasTokens.space3),
                    const ExSectionHeader(FvStrings.internalNote),
                    const SizedBox(height: ExantasTokens.space2),
                    Focus(
                        onFocusChange: (f) {
                          if (!f) _saveNote();
                        },
                        child: TextField(
                            key: const ValueKey('fv-internal-note'),
                            controller: note,
                            enabled: !locked,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(hintText: FvStrings.internalNoteHint))),
                  ]));
            }));
  }
}
