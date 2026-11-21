import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/exantas_field_visit.dart';
import '../../models/exantas_field_visit_sync.dart';
import '../ui/ex_card.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';

/// Everything the field-visit screens need from the outside world. Production
/// wires real GPS/camera/scanner; tests inject fakes (no plugins involved).
class FvEnv {
  const FvEnv({
    required this.sync,
    required this.locate,
    required this.pickPhoto,
    required this.scanBarcode,
    this.now = DateTime.now,
  });
  final ExantasFieldVisitSync sync;

  /// One GPS fix at arrival (15 s timeout); null = failed (arrival still recorded).
  final Future<FvFix?> Function() locate;
  final Future<({List<int> bytes, String mediaType})?> Function() pickPhoto;
  final Future<String?> Function(BuildContext context) scanBarcode;
  final DateTime Function() now;
}

/// Location is requested only here, at arrival. Any failure returns null.
Future<FvFix?> fvLocateOnce() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15));
    return FvFix(p.latitude, p.longitude, p.accuracy, p.timestamp);
  } catch (_) {
    return null;
  }
}

String fvHm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String fvErrorText(Object e) {
  final raw = e.toString().replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');
  return FvStrings.errorFor(raw);
}

/// Arrival / pause / departure controls of the signed-in technician.
class FvAttendancePanel extends StatefulWidget {
  const FvAttendancePanel({super.key, required this.env, required this.visitId, this.showArrival = true});
  final FvEnv env;
  final String visitId;
  final bool showArrival;

  @override
  State<FvAttendancePanel> createState() => _FvAttendancePanelState();
}

class _FvAttendancePanelState extends State<FvAttendancePanel> {
  bool busy = false;
  String? error;

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
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

  @override
  Widget build(BuildContext context) {
    final sync = widget.env.sync;
    return ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final v = sync.visit(widget.visitId);
          if (v == null) return const SizedBox.shrink();
          final a = v.myAttendance;
          final t = context.ex;
          final text = Theme.of(context).textTheme;
          final now = widget.env.now();
          final locked = v.localStatus != FvLocalStatus.draft && v.localStatus != FvLocalStatus.awaiting;
          return ExCard(
              key: const ValueKey('fv-attendance'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(FvStrings.attendance, style: text.labelLarge?.copyWith(color: t.textSecondary)),
                const SizedBox(height: ExantasTokens.space2),
                if (!a.arrived)
                  Text(FvStrings.notArrivedHint, style: text.bodySmall?.copyWith(color: t.textSecondary))
                else
                  Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ExStatusPill(
                        a.departed
                            ? FvStrings.leftAt(fvHm(a.departureAt!))
                            : a.onPause
                                ? FvStrings.onPause
                                : FvStrings.arrivedAt(fvHm(a.arrivalAt!)),
                        status: a.departed ? ExStatus.neutral : (a.onPause ? ExStatus.warning : ExStatus.success)),
                    if (a.gpsMissing) const ExStatusPill(FvStrings.noGps, status: ExStatus.warning, icon: Icons.location_off_outlined),
                    Text(FvStrings.workedMinutes(fvFormatMinutes(a.workedMinutes(now))), style: text.bodyMedium),
                  ]),
                if (error != null) ...[
                  const SizedBox(height: ExantasTokens.space2),
                  Text(error!, key: const ValueKey('fv-attendance-error'), style: text.bodySmall?.copyWith(color: t.danger)),
                ],
                const SizedBox(height: ExantasTokens.space3),
                Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                  if (!a.arrived && widget.showArrival && !locked)
                    FilledButton.icon(
                        key: const ValueKey('fv-arrive'),
                        onPressed: busy ? null : () => _run(() async => sync.arrive(v.id, fix: await widget.env.locate())),
                        icon: const Icon(Icons.place_outlined),
                        label: const Text(FvStrings.arrive)),
                  if (a.isOpen && !locked) ...[
                    OutlinedButton.icon(
                        key: const ValueKey('fv-pause'),
                        onPressed: busy ? null : () => _run(() => a.onPause ? sync.endPause(v.id) : sync.startPause(v.id)),
                        icon: Icon(a.onPause ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        label: Text(a.onPause ? FvStrings.resume : FvStrings.pause)),
                    OutlinedButton.icon(
                        key: const ValueKey('fv-depart'),
                        onPressed: busy ? null : () => _run(() => sync.depart(v.id)),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text(FvStrings.depart)),
                  ],
                ]),
              ]));
        });
  }
}

/// Ticking elapsed clock (display only; refreshes each 30 s).
class FvTimerPill extends StatefulWidget {
  const FvTimerPill({super.key, required this.attendance, required this.now});
  final FvAttendance attendance;
  final DateTime Function() now;
  @override
  State<FvTimerPill> createState() => _FvTimerPillState();
}

class _FvTimerPillState extends State<FvTimerPill> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attendance;
    if (!a.arrived) return const SizedBox.shrink();
    return Semantics(
        label: FvStrings.elapsedLabel,
        child: ExStatusPill(fvFormatClock(a.workedMinutes(widget.now())),
            status: a.onPause ? ExStatus.warning : ExStatus.success, icon: Icons.timer_outlined));
  }
}
