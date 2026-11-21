import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exantas_field_visit.dart';
import '../../models/exantas_field_visit_sync.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'exantas_field_visit_attendance.dart';
import 'exantas_field_visit_flow.dart';

bool fvSameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// The moment a visit belongs to on the day list.
DateTime? fvVisitMoment(FieldVisit v) => v.scheduledStart ?? v.myAttendance.arrivalAt ?? v.updatedAt;

/// (label, status) shown on a visit card.
(String, ExStatus) fvVisitBadge(FieldVisit v) {
  if (v.ops.any((o) => o.state == 'rejected')) return (FvStrings.badgeRejected, ExStatus.danger);
  if (v.localStatus == FvLocalStatus.cancelled) return (FvStrings.badgeCancelled, ExStatus.neutral);
  if (v.ops.isNotEmpty) return (FvStrings.badgeUnsynced, ExStatus.warning);
  if (v.customerPending) return (FvStrings.customerPendingApproval, ExStatus.warning);
  switch (v.localStatus) {
    case FvLocalStatus.closed:
      return (FvStrings.badgeClosed, ExStatus.success);
    case FvLocalStatus.awaiting:
      return (FvStrings.badgeAwaiting, ExStatus.info);
    case FvLocalStatus.closing:
      return (FvStrings.badgeClosing, ExStatus.warning);
    default:
      break;
  }
  if (v.myAttendance.isOpen) return (FvStrings.badgeInProgress, ExStatus.success);
  return (FvStrings.badgeScheduled, ExStatus.info);
}

class FvVisitCard extends StatelessWidget {
  const FvVisitCard({super.key, required this.visit, required this.onTap});
  final FieldVisit visit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final moment = fvVisitMoment(visit);
    final (label, status) = fvVisitBadge(visit);
    final others = visit.participants.where((p) => !p.isSelf).map((p) => p.displayName).toList();
    return Padding(
        padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
        child: ExCard(
            key: ValueKey('fv-card-${visit.id}'),
            onTap: onTap,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 52, child: Text(moment == null ? '—' : fvHm(moment), style: text.titleSmall)),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(visit.customerName, style: text.titleSmall),
                Text([visit.jobTypeLabel, if (visit.branchName.isNotEmpty) visit.branchName else if (visit.workTitle.isNotEmpty) visit.workTitle].where((e) => e.isNotEmpty).join(' · '),
                    style: text.bodyMedium?.copyWith(color: t.textSecondary)),
                const SizedBox(height: ExantasTokens.space1),
                Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space1, children: [
                  ExStatusPill(label, status: status),
                  if (others.isNotEmpty) ExStatusPill(FvStrings.withOthers(others.join(', ')), status: ExStatus.info, icon: Icons.group_outlined),
                ]),
              ])),
            ])));
  }
}

Future<void> openFvStart(BuildContext context, FvEnv env) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FvStartPage(env: env)));

/// Σήμερα: today's visits + start without an appointment.
class FvTodayPanel extends StatelessWidget {
  const FvTodayPanel({super.key, required this.env});
  final FvEnv env;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: env.sync,
      builder: (context, _) {
        final today = env.now();
        final list = [for (final v in env.sync.visits) if (fvVisitMoment(v) != null && fvSameDay(fvVisitMoment(v)!, today)) v];
        final t = context.ex;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExSectionHeader(FvStrings.visitsToday,
              action: FilledButton.tonalIcon(
                  key: const ValueKey('fv-new-visit'),
                  onPressed: () => openFvStart(context, env),
                  icon: const Icon(Icons.add),
                  label: const Text(FvStrings.newVisit))),
          const SizedBox(height: ExantasTokens.space2),
          if (list.isEmpty)
            const ExCard(padding: EdgeInsets.zero, child: ExEmptyState(icon: Icons.event_available_outlined, title: FvStrings.noVisitsToday, message: FvStrings.noVisitsTodayHint))
          else
            for (final v in list) FvVisitCard(visit: v, onTap: () => openFvVisit(context, env, v.id)),
          if (env.sync.lastOffline)
            Padding(padding: const EdgeInsets.only(top: ExantasTokens.space1), child: Text(FvStrings.offlineWorking, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.textSecondary))),
          const SizedBox(height: ExantasTokens.space3),
        ]);
      });
}

/// Ημερολόγιο: week strip + the day's own visits + book an appointment.
class FvCalendarPanel extends StatefulWidget {
  const FvCalendarPanel({super.key, required this.env});
  final FvEnv env;
  @override
  State<FvCalendarPanel> createState() => _FvCalendarPanelState();
}

class _FvCalendarPanelState extends State<FvCalendarPanel> {
  late DateTime day = _dayOnly(widget.env.now().toLocal());

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime get weekStart => day.subtract(Duration(days: day.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
        listenable: widget.env.sync,
        builder: (context, _) {
          final list = [
            for (final v in widget.env.sync.visits)
              if (v.scheduledStart != null && fvSameDay(v.scheduledStart!, day) && v.localStatus != FvLocalStatus.cancelled) v
          ]..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text(FvStrings.monthYear(day), style: text.titleMedium))),
              IconButton(key: const ValueKey('fv-week-prev'), tooltip: FvStrings.prevWeek, onPressed: () => setState(() => day = day.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
              IconButton(key: const ValueKey('fv-week-next'), tooltip: FvStrings.nextWeek, onPressed: () => setState(() => day = day.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
            ]),
            Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
              for (var i = 0; i < 7; i++)
                ChoiceChip(
                    key: ValueKey('fv-day-$i'),
                    showCheckmark: false,
                    label: Text(FvStrings.dayChip(weekStart.add(Duration(days: i)))),
                    selected: fvSameDay(weekStart.add(Duration(days: i)), day),
                    onSelected: (_) => setState(() => day = weekStart.add(Duration(days: i)))),
            ]),
            const SizedBox(height: ExantasTokens.space3),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                    key: const ValueKey('fv-new-appointment'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FvAppointmentPage(env: widget.env, day: day))),
                    icon: const Icon(Icons.add),
                    label: const Text(FvStrings.newAppointment))),
            const SizedBox(height: ExantasTokens.space2),
            if (list.isEmpty)
              const ExCard(padding: EdgeInsets.zero, child: ExEmptyState(icon: Icons.event_busy_outlined, title: FvStrings.noAppointments))
            else
              for (final v in list) FvVisitCard(visit: v, onTap: () => openFvVisit(context, widget.env, v.id)),
            Text(FvStrings.calendarHint, style: text.bodySmall?.copyWith(color: t.textSecondary)),
            const SizedBox(height: ExantasTokens.space3),
          ]);
        });
  }
}

/// Booking an appointment from the phone (admin books on the web).
class FvAppointmentPage extends StatefulWidget {
  const FvAppointmentPage({super.key, required this.env, required this.day});
  final FvEnv env;
  final DateTime day;
  @override
  State<FvAppointmentPage> createState() => _FvAppointmentPageState();
}

class _FvAppointmentPageState extends State<FvAppointmentPage> {
  Map<String, dynamic>? customer;
  FvDraftCustomerInput? draft;
  FvJobType? jobType;
  late TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
  int durationMinutes = 60;
  final note = TextEditingController();
  final helpers = <String>{};
  bool busy = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  DateTime get startAt => DateTime(widget.day.year, widget.day.month, widget.day.day, start.hour, start.minute);

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.env.sync.createAppointment(
          customerId: customer == null ? null : '${customer!['id']}',
          customerName: customer == null ? '' : '${customer!['company_name'] ?? ''}',
          draft: draft,
          jobType: jobType!,
          start: startAt.toUtc(),
          end: startAt.add(Duration(minutes: durationMinutes)).toUtc(),
          note: note.text.trim(),
          participantIds: helpers.toList());
      unawaited(widget.env.sync.sync().catchError((_) {}));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final ready = (customer != null || draft != null) && jobType != null && !busy;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.newAppointment)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              Text(FvStrings.dayChip(widget.day), style: text.titleMedium),
              const SizedBox(height: ExantasTokens.space3),
              const ExSectionHeader(FvStrings.customerStep),
              const SizedBox(height: ExantasTokens.space2),
              FvCustomerPicker(
                  env: widget.env,
                  customer: customer,
                  draft: draft,
                  onCustomer: (c) => setState(() {
                        customer = c;
                        draft = null;
                      }),
                  onDraft: (d) => setState(() {
                        draft = d;
                        customer = null;
                      }),
                  onClear: () => setState(() {
                        customer = null;
                        draft = null;
                      })),
              const SizedBox(height: ExantasTokens.space4),
              const ExSectionHeader(FvStrings.jobTypeStep),
              const SizedBox(height: ExantasTokens.space2),
              FvJobTypeChips(config: widget.env.sync.config, selected: jobType, onSelected: (j) => setState(() => jobType = j)),
              const SizedBox(height: ExantasTokens.space4),
              const ExSectionHeader(FvStrings.whenStep),
              const SizedBox(height: ExantasTokens.space2),
              Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                    key: const ValueKey('fv-appt-time'),
                    onPressed: () async {
                      final p = await showTimePicker(context: context, initialTime: start);
                      if (p != null) setState(() => start = p);
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(start.format(context))),
                for (final m in const [30, 60, 90, 120])
                  ChoiceChip(showCheckmark: false, label: Text(fvFormatMinutes(m)), selected: durationMinutes == m, onSelected: (_) => setState(() => durationMinutes = m)),
              ]),
              const SizedBox(height: ExantasTokens.space3),
              TextField(controller: note, decoration: const InputDecoration(labelText: FvStrings.appointmentNote)),
              FvHelperChips(env: widget.env, selected: helpers, onChanged: () => setState(() {})),
              if (error != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space3), child: Text(error!, style: text.bodyMedium?.copyWith(color: t.danger))),
            ])),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                child: FilledButton(key: const ValueKey('fv-appt-save'), onPressed: ready ? _save : null, child: const Text(FvStrings.bookAppointment)))));
  }
}
