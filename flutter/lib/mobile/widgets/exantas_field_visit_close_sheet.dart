import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/exantas_field_visit.dart';
import '../../models/exantas_financial_ledger.dart' show exantasAbandonEligible;
import '../ui/ex_card.dart';
import '../ui/ex_confirm_dialog.dart';
import '../ui/ex_offline_banner.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_segmented.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'exantas_field_visit_attendance.dart';

/// "9120" (minor units, as sent by Office) -> "91,20 €". Formatting only.
String fvMoneyText(dynamic minor) {
  final n = int.tryParse('$minor');
  if (n == null) return '—';
  final neg = n < 0;
  final abs = neg ? -n : n;
  final whole = abs ~/ 100, cents = (abs % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return '${neg ? '−' : ''}$grouped,$cents €';
}

// ----------------------------------------------------------------- signature

/// Collects finger strokes and exports them as a PNG (white background).
class FvSignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size padSize = Size.zero;

  /// A signature needs real ink: at least one stroke longer than 12 logical px.
  bool get hasInk {
    for (final s in strokes) {
      var len = 0.0;
      for (var i = 1; i < s.length; i++) {
        len += (s[i] - s[i - 1]).distance;
      }
      if (len >= 12) return true;
    }
    return false;
  }

  void start(Offset p) {
    strokes.add([p]);
    notifyListeners();
  }

  void extend(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// PNG bytes at [width] x [height]; strokes are scaled from the pad size.
  Future<List<int>> toPng({int width = 600, int height = 240}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.white);
    final sx = padSize.width <= 0 ? 1.0 : width / padSize.width;
    final sy = padSize.height <= 0 ? 1.0 : height / padSize.height;
    FvSignaturePainter.paintStrokes(canvas, strokes, const Color(0xFF111827), Offset.zero, sx, sy, 3.2);
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Δεν δημιουργήθηκε η υπογραφή.');
    return data.buffer.asUint8List();
  }
}

class FvSignaturePainter extends CustomPainter {
  FvSignaturePainter(this.controller, this.color) : super(repaint: controller);
  final FvSignatureController controller;
  final Color color;

  static void paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color, Offset origin, double sx, double sy, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(Offset(s.first.dx * sx, s.first.dy * sy), width / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx * sx, s.first.dy * sy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx * sx, s[i].dy * sy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    controller.padSize = size;
    paintStrokes(canvas, controller.strokes, color, Offset.zero, 1, 1, 2.6);
  }

  @override
  bool shouldRepaint(FvSignaturePainter oldDelegate) => oldDelegate.controller != controller || oldDelegate.color != color;
}

class FvSignaturePad extends StatelessWidget {
  const FvSignaturePad({super.key, required this.controller, this.height = 160});
  final FvSignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Semantics(
        label: FvStrings.signaturePadLabel,
        child: Container(
            height: height,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: t.inputBorder, width: 1.5),
                borderRadius: BorderRadius.circular(ExantasTokens.radiusMd)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(ExantasTokens.radiusMd),
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => controller.start(d.localPosition),
                    onPanUpdate: (d) => controller.extend(d.localPosition),
                    child: Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: FvSignaturePainter(controller, const Color(0xFF111827)))),
                      Positioned(
                          left: 12,
                          bottom: 8,
                          child: ListenableBuilder(
                              listenable: controller,
                              builder: (_, __) => controller.strokes.isEmpty
                                  ? Text(FvStrings.signHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF5B6472)))
                                  : const SizedBox.shrink())),
                    ])))));
  }
}

// ------------------------------------------------------------------- summary

/// Screen 5: time, server charge estimate, charge source, discount, outcome.
class FvSummaryPage extends StatefulWidget {
  const FvSummaryPage({super.key, required this.env, required this.visitId});
  final FvEnv env;
  final String visitId;
  @override
  State<FvSummaryPage> createState() => _FvSummaryPageState();
}

class _FvSummaryPageState extends State<FvSummaryPage> {
  Map<String, dynamic>? preview;
  bool previewing = false, offline = false;
  String? error;
  late final outcomeNote = TextEditingController(text: visit.outcomeNote);
  late final discountReason = TextEditingController(text: visit.discountReason);
  late final afterHoursRate = TextEditingController(text: visit.afterHoursRateText);
  bool rateTouched = false;

  @override
  void dispose() {
    afterHoursRate.dispose();
    outcomeNote.dispose();
    discountReason.dispose();
    super.dispose();
  }

  FieldVisit get visit => widget.env.sync.visit(widget.visitId)!;

  @override
  void initState() {
    super.initState();
    final v = visit;
    // Default charge source = the customer's default (server config), still editable.
    if (v.chargeSource == null && FvChargeSource.parse(v.customerChargeDefault) != null) {
      unawaited(_set((x) => x.chargeSource = FvChargeSource.parse(x.customerChargeDefault)));
    }
  }

  Future<void> _set(void Function(FieldVisit v) change) async {
    try {
      await widget.env.sync.updateLocal(widget.visitId, change);
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    }
  }

  /// Read-only estimate from Office. Never a gate: the close works offline.
  Future<void> _preview() async {
    final v = visit;
    if (v.chargeSource == null || previewing) return;
    setState(() {
      previewing = true;
      error = null;
    });
    try {
      final r = await widget.env.sync.api
          .chargePreview(v.id, v.chargeSource!, v.discountBps, await widget.env.sync.scope(), afterHours: fvAfterHoursPayload(v));
      final minutes = FvChargeAfterHours.fromCharge(r['charge'] is Map ? Map<String, dynamic>.from(r['charge'] as Map) : null)?.minutes;
      if (minutes != null && minutes != v.afterHoursMinutes) await _set((x) => x.afterHoursMinutes = minutes);
      if (mounted) {
        setState(() {
          preview = r;
          offline = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => offline = true);
    } finally {
      if (mounted) setState(() => previewing = false);
    }
  }

  Future<void> _pickFollowUp() async {
    final now = widget.env.now();
    final d = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (tm == null) return;
    await _set((x) => x.followUpStart = DateTime(d.year, d.month, d.day, tm.hour, tm.minute).toUtc());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.summaryTitle)),
        body: ListenableBuilder(
            listenable: widget.env.sync,
            builder: (context, _) {
              final v = widget.env.sync.visit(widget.visitId);
              if (v == null) return const SizedBox.shrink();
              final limit = widget.env.sync.config.myDiscountLimitBps;
              final now = widget.env.now();
              final blockers = fvCloseBlockers(v, discountLimitBps: limit)..remove('signature_required')..remove('signer_required');
              final charge = preview?['charge'] is Map ? Map<String, dynamic>.from(preview!['charge'] as Map) : null;
              return ColoredBox(
                  color: t.surfaceAlt,
                  child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
                    ExCard(
                        key: const ValueKey('fv-time-card'),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(FvStrings.timeCard, style: text.labelLarge?.copyWith(color: t.textSecondary)),
                          const SizedBox(height: ExantasTokens.space2),
                          for (final p in v.participants)
                            _line(context, '${p.isSelf ? FvStrings.you : p.displayName} · ${_span(p.attendance, now)}', fvFormatMinutes(p.attendance.workedMinutes(now))),
                          const Divider(),
                          _line(context, FvStrings.total, fvFormatMinutes(v.totalWorkedMinutes(now)), bold: true),
                        ])),
                    const SizedBox(height: ExantasTokens.space3),
                    ExCard(
                        key: const ValueKey('fv-charge-card'),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(FvStrings.chargeCard, style: text.labelLarge?.copyWith(color: t.textSecondary)),
                          const SizedBox(height: ExantasTokens.space2),
                          if (offline) const Padding(padding: EdgeInsets.only(bottom: ExantasTokens.space2), child: ExOfflineBanner(message: FvStrings.previewOffline)),
                          if (charge == null && !offline)
                            Text(v.serverKnown ? FvStrings.previewHint : FvStrings.previewNotSynced, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                          if (charge != null) ...[
                            if (FvChargeAfterHours.fromCharge(charge) case final ah? when ah.apply && ah.rateMinorPerHour != null && ah.minutes > 0)
                              _line(context, FvStrings.afterHoursLine(ah.minutes, fvMoneyText(ah.rateMinorPerHour)), '', key: const ValueKey('fv-preview-after-hours')),
                            if (FvChargeAfterHours.fromCharge(charge)?.surchargeMinor case final sur? when sur != 0)
                              _line(context, FvStrings.afterHoursSurcharge, fvMoneyText(sur), key: const ValueKey('fv-preview-surcharge')),
                            _line(context, FvStrings.subtotal, fvMoneyText(charge['subtotal_minor'])),
                            if ('${charge['discount_minor']}' != '0') _line(context, FvStrings.discountLine('${((int.tryParse('${charge['discount_bps']}') ?? 0) ~/ 100)}'), '−${fvMoneyText(charge['discount_minor']).replaceFirst('−', '')}'),
                            const Divider(),
                            _line(context, FvStrings.netValue, fvMoneyText(charge['net_minor']), bold: true, key: const ValueKey('fv-preview-net')),
                            Text(FvStrings.previewDisclaimer, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                          ],
                          const SizedBox(height: ExantasTokens.space2),
                          if (v.serverKnown)
                            TextButton.icon(
                                key: const ValueKey('fv-preview'),
                                onPressed: v.chargeSource == null || previewing ? null : _preview,
                                icon: const Icon(Icons.refresh),
                                label: const Text(FvStrings.refreshPreview)),
                        ])),
                    const SizedBox(height: ExantasTokens.space3),
                    const ExSectionHeader(FvStrings.chargeFrom),
                    const SizedBox(height: ExantasTokens.space2),
                    ExSegmented<FvChargeSource>(
                        segments: const [
                          ExSegment(FvChargeSource.prepaid, FvStrings.sourcePrepaid, key: ValueKey('fv-source-prepaid')),
                          ExSegment(FvChargeSource.invoice, FvStrings.sourceInvoice, key: ValueKey('fv-source-invoice')),
                        ],
                        selected: v.chargeSource ?? FvChargeSource.prepaid,
                        onChanged: (s) => _set((x) => x.chargeSource = s)),
                    if (v.chargeSource == null) Text(FvStrings.pickChargeSource, style: text.bodySmall?.copyWith(color: t.warning)),
                    const SizedBox(height: ExantasTokens.space4),
                    _discount(context, v, limit),
                    ..._afterHours(context, v, charge),
                    const SizedBox(height: ExantasTokens.space2),
                    SwitchListTile(
                        key: const ValueKey('fv-show-prices'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(FvStrings.showPrices),
                        subtitle: const Text(FvStrings.showPricesHint),
                        value: v.showPrices,
                        onChanged: (on) => _set((x) => x.showPrices = on)),
                    const SizedBox(height: ExantasTokens.space3),
                    const ExSectionHeader(FvStrings.outcome),
                    const SizedBox(height: ExantasTokens.space2),
                    Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                      for (final o in FvOutcome.values)
                        ChoiceChip(
                            key: ValueKey('fv-outcome-${o.wire}'),
                            showCheckmark: false,
                            label: Text(FvStrings.outcomeLabel(o.wire)),
                            selected: v.outcome == o,
                            onSelected: (_) => _set((x) => x.outcome = o)),
                    ]),
                    if (v.outcome == FvOutcome.pending || v.outcome == FvOutcome.newVisit) ...[
                      const SizedBox(height: ExantasTokens.space2),
                      TextField(
                          key: const ValueKey('fv-outcome-note'),
                          controller: outcomeNote,
                          onChanged: (s) => _set((x) => x.outcomeNote = s),
                          decoration: const InputDecoration(labelText: FvStrings.outcomeNote)),
                    ],
                    if (v.outcome == FvOutcome.newVisit) ...[
                      const SizedBox(height: ExantasTokens.space2),
                      OutlinedButton.icon(
                          onPressed: _pickFollowUp,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(v.followUpStart == null ? FvStrings.followUpPick : FvStrings.followUpAt('${fvHm(v.followUpStart!)} · ${v.followUpStart!.toLocal().day}/${v.followUpStart!.toLocal().month}'))),
                    ],
                    if (error != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space3), child: Text(error!, style: text.bodyMedium?.copyWith(color: t.danger))),
                    if (blockers.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: ExantasTokens.space3),
                          child: Text(FvStrings.errorFor(blockers.first), key: const ValueKey('fv-blocker'), style: text.bodySmall?.copyWith(color: t.warning))),
                  ]));
            }),
        bottomNavigationBar: ListenableBuilder(
            listenable: widget.env.sync,
            builder: (context, _) {
              final v = widget.env.sync.visit(widget.visitId);
              final ready = v != null && (fvCloseBlockers(v, discountLimitBps: widget.env.sync.config.myDiscountLimitBps)..remove('signature_required')..remove('signer_required')).isEmpty;
              return SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(ExantasTokens.gutter),
                      child: FilledButton(
                          key: const ValueKey('fv-to-signature'),
                          onPressed: ready
                              ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FvSignaturePage(env: widget.env, visitId: widget.visitId)))
                              : null,
                          child: const Text(FvStrings.toSignature))));
            }));
  }

  String _span(FvAttendance a, DateTime now) {
    if (!a.arrived) return '—';
    final pauses = a.pauses.where((p) => p.end != null).fold<int>(0, (s, p) => s + p.end!.difference(p.start).inMinutes);
    return '${fvHm(a.arrivalAt!)}–${a.departureAt == null ? fvHm(now) : fvHm(a.departureAt!)}${pauses > 0 ? FvStrings.pauseSuffix(pauses) : ''}';
  }

  Widget _line(BuildContext context, String label, String value, {bool bold = false, Key? key}) {
    final style = bold ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.bodyMedium;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: ExantasTokens.space2),
          Text(value, key: key, style: style),
        ]));
  }

  /// «Χρέωση εκτός ωραρίου»: shown only when Office reported after-hours minutes
  /// (or the technician already turned it on). Off by default.
  List<Widget> _afterHours(BuildContext context, FieldVisit v, Map<String, dynamic>? charge) {
    final minutes = FvChargeAfterHours.fromCharge(charge)?.minutes ?? FvChargeAfterHours.fromCharge(v.charge)?.minutes ?? v.afterHoursMinutes ?? 0;
    if (minutes <= 0 && !v.afterHoursApply) return const [];
    final issue = v.afterHoursApply && (rateTouched || v.afterHoursRateText.trim().isNotEmpty) ? fvAfterHoursRateIssue(v.afterHoursRateText) : null;
    return [
      const SizedBox(height: ExantasTokens.space2),
      SwitchListTile(
          key: const ValueKey('fv-after-hours'),
          contentPadding: EdgeInsets.zero,
          title: const Text(FvStrings.afterHoursRow),
          subtitle: minutes > 0 ? Text(FvStrings.afterHoursHint(minutes)) : null,
          value: v.afterHoursApply,
          onChanged: (on) async {
            final prefill = widget.env.sync.config.defaultAfterHoursRateMinor;
            final fill = on && v.afterHoursRateText.trim().isEmpty && prefill != null && fvParseAfterHoursRate(fvRateFieldText(prefill)) != null;
            await _set((x) {
              x.afterHoursApply = on;
              if (fill) x.afterHoursRateText = fvRateFieldText(prefill);
            });
            if (fill) afterHoursRate.text = fvRateFieldText(prefill);
            if (v.serverKnown && (!on || fvAfterHoursRateIssue(visit.afterHoursRateText) == null)) unawaited(_preview());
          }),
      if (v.afterHoursApply) ...[
        TextField(
            key: const ValueKey('fv-after-hours-rate'),
            controller: afterHoursRate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')), LengthLimitingTextInputFormatter(7)],
            onChanged: (s) {
              setState(() => rateTouched = true);
              _set((x) => x.afterHoursRateText = s);
            },
            decoration: InputDecoration(labelText: FvStrings.afterHoursRate, suffixText: '€/ώρα', errorMaxLines: 3, errorText: issue == null ? null : FvStrings.errorFor(issue))),
      ],
    ];
  }

  Widget _discount(BuildContext context, FieldVisit v, int limit) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final steps = limit ~/ 100; // whole percents up to the technician's limit
    final enabled = steps > 0;
    final pct = (v.discountBps / 100).round().clamp(0, steps == 0 ? 0 : steps);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(enabled ? FvStrings.discountLabel(pct, steps) : FvStrings.discountNone, key: const ValueKey('fv-discount-label'), style: text.titleSmall),
      Slider(
          key: const ValueKey('fv-discount'),
          min: 0,
          max: enabled ? steps.toDouble() : 1,
          divisions: enabled ? steps : null,
          value: enabled ? pct.toDouble() : 0,
          label: '$pct%',
          semanticFormatterCallback: (value) => FvStrings.discountPercent(value.round()),
          onChanged: enabled ? (x) => _set((y) => y.discountBps = x.round() * 100) : null),
      if (!enabled) Text(FvStrings.discountLimitZero, style: text.bodySmall?.copyWith(color: t.textSecondary)),
      if (enabled && v.discountBps > 0)
        TextField(
            key: const ValueKey('fv-discount-reason'),
            controller: discountReason,
            onChanged: (s) => _set((x) => x.discountReason = s),
            decoration: const InputDecoration(labelText: FvStrings.discountReason)),
    ]);
  }
}

// ----------------------------------------------------------------- signature

/// Screen 6: customer signature (or none) then the single close request.
class FvSignaturePage extends StatefulWidget {
  const FvSignaturePage({super.key, required this.env, required this.visitId});
  final FvEnv env;
  final String visitId;
  @override
  State<FvSignaturePage> createState() => _FvSignaturePageState();
}

class _FvSignaturePageState extends State<FvSignaturePage> {
  final pad = FvSignatureController();
  final name = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    pad.addListener(() => setState(() {}));
    name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    pad.dispose();
    name.dispose();
    super.dispose();
  }

  bool get canSign => pad.hasInk && name.text.trim().isNotEmpty && !busy;

  Future<void> _close({required bool signed}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sync = widget.env.sync;
      if (signed) {
        final png = await pad.toPng();
        if (png.length > 150 * 1024) throw StateError('signature_too_large');
        final encoded = base64Encode(png);
        await sync.updateLocal(widget.visitId, (v) {
          v.signaturePngBase64 = encoded;
          v.signerName = name.text.trim();
          v.noSignature = false;
        });
      } else {
        await sync.updateLocal(widget.visitId, (v) {
          v.signaturePngBase64 = null;
          v.signerName = '';
          v.noSignature = true;
        });
      }
      await sync.closeVisit(widget.visitId);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.settings.name == fvVisitRouteName || r.isFirst);
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _noSignature() async {
    final ok = await showExConfirmDialog(context,
        title: FvStrings.noSignatureTitle, message: FvStrings.noSignatureMessage, confirmLabel: FvStrings.noSignature);
    if (ok) await _close(signed: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final v = widget.env.sync.visit(widget.visitId);
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.signatureTitle)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              if (v != null)
                ExCard(
                    child: Text(
                        [
                          v.jobTypeLabel,
                          fvFormatMinutes(v.totalWorkedMinutes(widget.env.now())),
                          if (v.outcome != null) FvStrings.outcomeLabel(v.outcome!.wire),
                        ].join(' · '),
                        style: text.bodyMedium?.copyWith(color: t.textSecondary))),
              const SizedBox(height: ExantasTokens.space3),
              TextField(
                  key: const ValueKey('fv-signer'),
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: FvStrings.signerName)),
              const SizedBox(height: ExantasTokens.space3),
              FvSignaturePad(controller: pad),
              const SizedBox(height: ExantasTokens.space2),
              Wrap(alignment: WrapAlignment.spaceBetween, children: [
                TextButton(key: const ValueKey('fv-sign-clear'), onPressed: pad.strokes.isEmpty ? null : pad.clear, child: const Text(FvStrings.clear)),
                TextButton(key: const ValueKey('fv-no-signature'), onPressed: busy ? null : _noSignature, child: const Text(FvStrings.noSignature)),
              ]),
              if (error != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space2), child: Text(error!, key: const ValueKey('fv-close-error'), style: text.bodyMedium?.copyWith(color: t.danger))),
            ])),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                child: FilledButton(
                    key: const ValueKey('fv-sign-close'),
                    onPressed: canSign ? () => _close(signed: true) : null,
                    child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text(FvStrings.signAndClose)))));
  }
}

const fvVisitRouteName = 'fv-visit';

// -------------------------------------------------------------------- closed

/// Screen 7: saved / waiting for sync / waiting for colleagues / done, plus the
/// optional payment record.
class FvClosedPage extends StatefulWidget {
  const FvClosedPage({super.key, required this.env, required this.visitId});
  final FvEnv env;
  final String visitId;
  @override
  State<FvClosedPage> createState() => _FvClosedPageState();
}

class _FvClosedPageState extends State<FvClosedPage> {
  String method = 'cash';
  final amount = TextEditingController(), reference = TextEditingController();
  bool busy = false;
  String? error, info;

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pay() => _guard(() async {
        final minor = fvParseEuroToMinor(amount.text);
        if (minor == null || minor <= 0) throw StateError(FvStrings.paymentAmountInvalid);
        await widget.env.sync.addPayment(widget.visitId, method: method, amountMinor: minor, reference: reference.text.trim());
        amount.clear();
        reference.clear();
        unawaited(widget.env.sync.sync().catchError((_) {}));
        if (mounted) setState(() => info = FvStrings.paymentSaved);
      });

  Future<void> _abandon() async {
    final ok = await showExConfirmDialog(context,
        title: FvStrings.abandonTitle, message: FvStrings.abandonMessage, confirmLabel: FvStrings.abandonConfirm, destructive: true);
    if (!ok) return;
    await _guard(() async {
      final cleared = await widget.env.sync.abandonClose(widget.visitId);
      if (!cleared) throw StateError(FvStrings.abandonAnswered);
      if (mounted) Navigator.of(context).popUntil((r) => r.settings.name == fvVisitRouteName || r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final sync = widget.env.sync;
    return ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final v = sync.visit(widget.visitId);
          if (v == null) return const Scaffold(body: SizedBox.shrink());
          final op = v.closeOp;
          final unresolved = op != null && op.sent && op.state == 'unknown';
          final waitingSync = v.ops.any((o) => o.state != 'rejected');
          final canAbandon = op != null && op.sent && exantasAbandonEligible(op.marks, widget.env.now());
          final emailState = (v.report?['email'] is Map) ? '${(v.report!['email'] as Map)['state']}' : null;
          final cancelled = v.localStatus == FvLocalStatus.cancelled;
          return Scaffold(
              appBar: AppBar(title: Text(cancelled ? FvStrings.cancelledTitle : FvStrings.closedTitle), automaticallyImplyLeading: false),
              body: ColoredBox(
                  color: t.surfaceAlt,
                  child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
                    Column(children: [
                      const SizedBox(height: ExantasTokens.space3),
                      CircleAvatar(radius: 26, backgroundColor: cancelled ? t.warningSoft : t.successSoft, child: Icon(cancelled ? Icons.block : Icons.check, color: cancelled ? t.warning : t.success, size: 28)),
                      const SizedBox(height: ExantasTokens.space2),
                      Text(cancelled ? FvStrings.cancelledMessage : FvStrings.savedMessage, style: text.titleMedium, textAlign: TextAlign.center),
                      Text(v.customerName, style: text.bodyMedium?.copyWith(color: t.textSecondary), textAlign: TextAlign.center),
                    ]),
                    const SizedBox(height: ExantasTokens.space3),
                    if (unresolved)
                      ExCard(
                          key: const ValueKey('fv-close-unresolved'),
                          color: t.warningSoft,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(FvStrings.closeUnresolved, style: text.bodyMedium?.copyWith(color: t.warning)),
                            const SizedBox(height: ExantasTokens.space2),
                            Wrap(spacing: ExantasTokens.space2, children: [
                              FilledButton.tonal(
                                  key: const ValueKey('fv-recover'),
                                  onPressed: busy ? null : () => _guard(() async {
                                        final done = await sync.recoverClose(v.id);
                                        if (!done && mounted) setState(() => info = FvStrings.recoverStillUnknown);
                                      }),
                                  child: const Text(FvStrings.checkRequest)),
                              if (canAbandon) TextButton(key: const ValueKey('fv-abandon'), onPressed: busy ? null : _abandon, child: Text(FvStrings.abandonConfirm, style: TextStyle(color: t.danger))),
                            ]),
                          ]))
                    else if (waitingSync && !cancelled)
                      const ExOfflineBanner(message: FvStrings.waitingSyncBanner)
                    else if (v.localStatus == FvLocalStatus.awaiting)
                      ExCard(key: const ValueKey('fv-awaiting'), color: t.accentSoft, child: Text(FvStrings.awaitingColleagues, style: text.bodyMedium)),
                    if (error != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space2), child: Text(error!, key: const ValueKey('fv-closed-error'), style: text.bodyMedium?.copyWith(color: t.danger))),
                    if (info != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space2), child: Text(info!, style: text.bodyMedium?.copyWith(color: t.success))),
                    if (v.charge != null) ...[
                      const SizedBox(height: ExantasTokens.space3),
                      ExCard(
                          key: const ValueKey('fv-charge-result'),
                          child: Row(children: [
                            Expanded(child: Text(FvStrings.chargeState('${v.charge!['state']}'), style: text.bodyMedium)),
                            Text(fvMoneyText(v.charge!['net_minor']), style: text.titleSmall),
                          ])),
                    ],
                    const SizedBox(height: ExantasTokens.space3),
                    if (!cancelled)
                      ExCard(
                          key: const ValueKey('fv-payment-card'),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(FvStrings.paymentTitle, style: text.labelLarge?.copyWith(color: t.textSecondary)),
                            const SizedBox(height: ExantasTokens.space2),
                            Wrap(spacing: ExantasTokens.space2, children: [
                              ChoiceChip(showCheckmark: false, label: const Text(FvStrings.cash), selected: method == 'cash', onSelected: (_) => setState(() => method = 'cash')),
                              ChoiceChip(showCheckmark: false, label: const Text(FvStrings.bankDeposit), selected: method == 'bank_deposit', onSelected: (_) => setState(() => method = 'bank_deposit')),
                            ]),
                            const SizedBox(height: ExantasTokens.space2),
                            TextField(key: const ValueKey('fv-pay-amount'), controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: FvStrings.paymentAmount)),
                            const SizedBox(height: ExantasTokens.space2),
                            TextField(controller: reference, decoration: const InputDecoration(labelText: FvStrings.paymentReference)),
                            const SizedBox(height: ExantasTokens.space1),
                            Text(FvStrings.paymentHint, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                            const SizedBox(height: ExantasTokens.space2),
                            Align(alignment: Alignment.centerRight, child: FilledButton.tonal(key: const ValueKey('fv-pay-save'), onPressed: busy ? null : _pay, child: const Text(FvStrings.paymentSave))),
                            for (final p in v.payments)
                              Padding(padding: const EdgeInsets.only(top: ExantasTokens.space1), child: Text('${p.method == 'cash' ? FvStrings.cash : FvStrings.bankDeposit} · ${fvMoneyText(p.amountMinor)}${p.voided ? ' · ${FvStrings.voided}' : ''}', style: text.bodyMedium)),
                          ])),
                    const SizedBox(height: ExantasTokens.space3),
                    ExCard(
                        key: const ValueKey('fv-email-card'),
                        child: Row(children: [
                          const Expanded(child: Text(FvStrings.pdfToContact)),
                          ExStatusPill(FvStrings.emailStateLabel(emailState), status: emailState == 'provider_accepted' ? ExStatus.success : ExStatus.warning),
                        ])),
                  ])),
              bottomNavigationBar: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(ExantasTokens.gutter),
                      child: OutlinedButton(key: const ValueKey('fv-back-today'), onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text(FvStrings.backToToday)))));
        });
  }
}
