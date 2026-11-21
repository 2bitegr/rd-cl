import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exantas_field_visit.dart';
import '../../models/exantas_field_visit_sync.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_list_row.dart';
import '../ui/ex_search_field.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'exantas_field_visit_attendance.dart';
import 'exantas_field_visit_close_sheet.dart';
import 'exantas_field_visit_draft_customer.dart';
import 'exantas_field_visit_equipment.dart';

/// Opens the visit hub (arrival -> work -> summary -> signature -> closed).
Future<void> openFvVisit(BuildContext context, FvEnv env, String visitId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: fvVisitRouteName), builder: (_) => FvVisitPage(env: env, visitId: visitId)));

/// Customer chooser shared by the start page and the appointment page: search
/// (online), recent customers (offline), or a draft customer.
class FvCustomerPicker extends StatefulWidget {
  const FvCustomerPicker(
      {super.key, required this.env, required this.customer, required this.draft, required this.onCustomer, required this.onDraft, required this.onClear});
  final FvEnv env;
  final Map<String, dynamic>? customer;
  final FvDraftCustomerInput? draft;
  final void Function(Map<String, dynamic>) onCustomer;
  final void Function(FvDraftCustomerInput) onDraft;
  final VoidCallback onClear;
  @override
  State<FvCustomerPicker> createState() => _FvCustomerPickerState();
}

class _FvCustomerPickerState extends State<FvCustomerPicker> {
  final search = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool searching = false;
  String? searchError;

  ExantasFieldVisitSync get sync => widget.env.sync;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get recent {
    final seen = <String>{};
    return [
      for (final v in sync.visits.reversed)
        if (v.customerId != null && seen.add(v.customerId!)) {'id': v.customerId, 'company_name': v.customerName}
    ].take(5).toList();
  }

  Future<void> _search(String q) async {
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final r = await sync.api.searchCustomers(q, await sync.scope());
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) setState(() => searchError = fvErrorText(e));
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _newCustomer() async {
    final d = await Navigator.of(context).push<FvDraftCustomerInput>(
        MaterialPageRoute(builder: (_) => FvDraftCustomerPage(initialName: search.text)));
    if (d != null && mounted) widget.onDraft(d);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final selected = widget.draft != null || widget.customer != null;
    final name = widget.draft?.companyName ?? '${widget.customer?['company_name'] ?? ''}';
    if (selected) {
      return ExCard(
          key: const ValueKey('fv-selected-customer'),
          child: Row(children: [
            Expanded(child: Text(name, style: text.titleSmall)),
            if (widget.draft != null) const ExStatusPill(FvStrings.customerPendingApproval, status: ExStatus.warning),
            IconButton(tooltip: FvStrings.change, onPressed: widget.onClear, icon: const Icon(Icons.close)),
          ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ExSearchField(controller: search, label: FvStrings.searchCustomer, onSubmitted: _search),
      if (searching) const Padding(padding: EdgeInsets.all(ExantasTokens.space2), child: LinearProgressIndicator(minHeight: 2)),
      if (searchError != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space2), child: Text(searchError!, style: text.bodySmall?.copyWith(color: t.danger))),
      if (results.isEmpty && recent.isNotEmpty) ...[
        const SizedBox(height: ExantasTokens.space2),
        Text(FvStrings.recentCustomers, style: text.labelLarge?.copyWith(color: t.textSecondary)),
      ],
      for (final c in results.isEmpty ? recent : results)
        ExCard(
            padding: EdgeInsets.zero,
            child: ExListRow(
                key: ValueKey('fv-customer-${c['id']}'),
                title: '${c['company_name'] ?? ''}',
                subtitle: '${c['afm'] ?? ''}'.isEmpty ? null : 'ΑΦΜ ${c['afm']}',
                icon: Icons.business_outlined,
                onTap: () => widget.onCustomer(c))),
      const SizedBox(height: ExantasTokens.space2),
      OutlinedButton.icon(key: const ValueKey('fv-new-customer'), onPressed: _newCustomer, icon: const Icon(Icons.person_add_alt), label: const Text(FvStrings.newCustomer)),
    ]);
  }
}

/// Start without an appointment: customer, job type, optional work, helpers.
class FvStartPage extends StatefulWidget {
  const FvStartPage({super.key, required this.env});
  final FvEnv env;
  @override
  State<FvStartPage> createState() => _FvStartPageState();
}

class _FvStartPageState extends State<FvStartPage> {
  Map<String, dynamic>? customer;
  FvDraftCustomerInput? draft;
  FvJobType? jobType;
  List<Map<String, dynamic>> works = [];
  String? workId, workTitle;
  final helpers = <String>{};
  bool busy = false;
  String? error;

  ExantasFieldVisitSync get sync => widget.env.sync;

  Future<void> _pick(Map<String, dynamic> c) async {
    setState(() {
      customer = c;
      draft = null;
      works = [];
      workId = null;
    });
    try {
      final list = await sync.api.workList('${c['id']}', await sync.scope());
      if (mounted) setState(() => works = list);
    } catch (_) {
      // Offline: a free visit stays possible.
    }
  }

  bool get ready => (customer != null || draft != null) && jobType != null && !busy;

  Future<void> _start() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await sync.startVisit(
          customerId: customer == null ? null : '${customer!['id']}',
          customerName: customer == null ? '' : '${customer!['company_name'] ?? ''}',
          draft: draft,
          workItemId: workId,
          workTitle: workTitle ?? '',
          jobType: jobType!,
          participantIds: helpers.toList());
      unawaited(sync.sync().catchError((_) {}));
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
              settings: const RouteSettings(name: fvVisitRouteName),
              builder: (_) => FvVisitPage(env: widget.env, visitId: v.id)));
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
    final cfg = sync.config;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.newVisit)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              const ExSectionHeader(FvStrings.customerStep),
              const SizedBox(height: ExantasTokens.space2),
              FvCustomerPicker(
                  env: widget.env,
                  customer: customer,
                  draft: draft,
                  onCustomer: _pick,
                  onDraft: (d) => setState(() {
                        draft = d;
                        customer = null;
                        works = [];
                        workId = null;
                      }),
                  onClear: () => setState(() {
                        customer = null;
                        draft = null;
                      })),
              const SizedBox(height: ExantasTokens.space4),
              const ExSectionHeader(FvStrings.jobTypeStep),
              const SizedBox(height: ExantasTokens.space2),
              FvJobTypeChips(config: cfg, selected: jobType, onSelected: (j) => setState(() => jobType = j)),
              if (works.isNotEmpty) ...[
                const SizedBox(height: ExantasTokens.space4),
                const ExSectionHeader(FvStrings.workStep),
                const SizedBox(height: ExantasTokens.space2),
                Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                  ChoiceChip(
                      showCheckmark: false,
                      label: const Text(FvStrings.noWork),
                      selected: workId == null,
                      onSelected: (_) => setState(() => workId = null)),
                  for (final w in works)
                    ChoiceChip(
                        showCheckmark: false,
                        label: Text('${w['title'] ?? ''}', overflow: TextOverflow.ellipsis),
                        selected: workId == '${w['id']}',
                        onSelected: (_) => setState(() {
                              workId = '${w['id']}';
                              workTitle = '${w['title'] ?? ''}';
                            })),
                ]),
              ],
              FvHelperChips(env: widget.env, selected: helpers, onChanged: () => setState(() {})),
              if (error != null) Padding(padding: const EdgeInsets.only(top: ExantasTokens.space3), child: Text(error!, style: text.bodyMedium?.copyWith(color: t.danger))),
            ])),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                child: FilledButton(key: const ValueKey('fv-start'), onPressed: ready ? _start : null, child: const Text(FvStrings.startVisit)))));
  }
}

class FvJobTypeChips extends StatelessWidget {
  const FvJobTypeChips({super.key, required this.config, required this.selected, required this.onSelected});
  final FvConfig config;
  final FvJobType? selected;
  final ValueChanged<FvJobType> onSelected;
  @override
  Widget build(BuildContext context) {
    if (config.jobTypes.isEmpty) {
      return Text(FvStrings.noJobTypes, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ex.textSecondary));
    }
    return Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
      for (final j in config.jobTypes)
        ChoiceChip(
            key: ValueKey('fv-jobtype-${j.id}'),
            showCheckmark: false,
            label: Text(j.label),
            selected: selected?.id == j.id,
            onSelected: (_) => onSelected(j)),
    ]);
  }
}

class FvHelperChips extends StatelessWidget {
  const FvHelperChips({super.key, required this.env, required this.selected, required this.onChanged});
  final FvEnv env;
  final Set<String> selected;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final others = env.sync.config.staff.where((s) => s.id != env.sync.selfUserId).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: ExantasTokens.space4),
      const ExSectionHeader(FvStrings.helpersStep),
      const SizedBox(height: ExantasTokens.space2),
      Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
        for (final s in others)
          FilterChip(
              showCheckmark: false,
              label: Text(s.name),
              selected: selected.contains(s.id),
              onSelected: (on) {
                on ? selected.add(s.id) : selected.remove(s.id);
                onChanged();
              }),
      ]),
    ]);
  }
}

/// Debounced multi-line text bound to the visit content (flushes on blur and
/// when the page closes, so nothing typed is lost).
class _DebouncedText extends StatefulWidget {
  const _DebouncedText({super.key, required this.initial, required this.enabled, required this.onSave, required this.hint, this.controllerOut});
  final String initial, hint;
  final bool enabled;
  final void Function(String) onSave;
  final void Function(TextEditingController)? controllerOut;
  @override
  State<_DebouncedText> createState() => _DebouncedTextState();
}

class _DebouncedTextState extends State<_DebouncedText> {
  late final c = TextEditingController(text: widget.initial);
  Timer? timer;
  String saved = '';

  @override
  void initState() {
    super.initState();
    saved = widget.initial;
    widget.controllerOut?.call(c);
  }

  void _flush() {
    timer?.cancel();
    if (c.text != saved) {
      saved = c.text;
      widget.onSave(c.text);
    }
  }

  @override
  void dispose() {
    _flush();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
      onFocusChange: (f) {
        if (!f) _flush();
      },
      child: TextField(
          controller: c,
          enabled: widget.enabled,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 700), _flush);
          },
          decoration: InputDecoration(hintText: widget.hint)));
}

/// Screens 2 and 3 (and the closed view) of the visit, driven by its state.
class FvVisitPage extends StatefulWidget {
  const FvVisitPage({super.key, required this.env, required this.visitId});
  final FvEnv env;
  final String visitId;
  @override
  State<FvVisitPage> createState() => _FvVisitPageState();
}

class _FvVisitPageState extends State<FvVisitPage> {
  TextEditingController? summary;
  String? error;

  ExantasFieldVisitSync get sync => widget.env.sync;

  Future<void> _edit(void Function(FieldVisit v) change) async {
    try {
      await sync.editContent(widget.visitId, change);
      unawaited(sync.sync().catchError((_) {}));
    } catch (e) {
      if (mounted) setState(() => error = fvErrorText(e));
    }
  }

  void _appendPhrase(String phrase) {
    final c = summary;
    if (c == null) return;
    final next = c.text.trim().isEmpty ? phrase : '${c.text.trimRight()} $phrase';
    c.text = next;
    c.selection = TextSelection.collapsed(offset: next.length);
    unawaited(_edit((v) => v.workSummary = next));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final v = sync.visit(widget.visitId);
          if (v == null) {
            return Scaffold(appBar: AppBar(), body: const ExEmptyState(icon: Icons.search_off, title: FvStrings.visitMissing));
          }
          if (v.localStatus != FvLocalStatus.draft) {
            return FvClosedPage(env: widget.env, visitId: v.id);
          }
          return v.myAttendance.arrived ? _work(context, v) : _arrival(context, v);
        });
  }

  Widget _footer(FieldVisit v) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(ExantasTokens.gutter, ExantasTokens.space2, ExantasTokens.gutter, ExantasTokens.space2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FvAttendancePanel(env: widget.env, visitId: v.id),
          ])));

  Widget _participants(BuildContext context, FieldVisit v) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return ExCard(
        key: const ValueKey('fv-participants'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(FvStrings.technicians, style: text.labelLarge?.copyWith(color: t.textSecondary)),
          const SizedBox(height: ExantasTokens.space2),
          for (final p in v.participants)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: ExantasTokens.space1),
                child: Row(children: [
                  CircleAvatar(radius: 14, backgroundColor: t.accentSoft, child: Text(_initials(p.displayName), style: text.labelSmall?.copyWith(color: t.accent))),
                  const SizedBox(width: ExantasTokens.space2),
                  Expanded(child: Text(p.isSelf ? FvStrings.you : p.displayName)),
                  ExStatusPill(
                      p.attendance.departed
                          ? FvStrings.leftAt(fvHm(p.attendance.departureAt!))
                          : p.attendance.arrived
                              ? FvStrings.thereSince(fvHm(p.attendance.arrivalAt!))
                              : FvStrings.notArrived,
                      status: p.attendance.arrived ? ExStatus.success : ExStatus.info),
                ])),
        ]));
  }

  static String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  Widget _arrival(BuildContext context, FieldVisit v) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Scaffold(
        appBar: AppBar(title: Text(v.customerName, overflow: TextOverflow.ellipsis)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              ExCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(FvStrings.visitCard, style: text.labelLarge?.copyWith(color: t.textSecondary)),
                const SizedBox(height: ExantasTokens.space1),
                Text([v.jobTypeLabel, if (v.branchName.isNotEmpty) v.branchName].join(' · '), style: text.titleSmall),
                if (v.workTitle.isNotEmpty) Text(FvStrings.workLine(v.workTitle), style: text.bodyMedium?.copyWith(color: t.textSecondary)),
                if (v.scheduledStart != null) Text(FvStrings.scheduledLine(fvHm(v.scheduledStart!)), style: text.bodyMedium?.copyWith(color: t.textSecondary)),
                if (v.customerPending) ...[
                  const SizedBox(height: ExantasTokens.space2),
                  const ExStatusPill(FvStrings.customerPendingApproval, status: ExStatus.warning),
                ],
              ])),
              const SizedBox(height: ExantasTokens.space3),
              _participants(context, v),
              const SizedBox(height: ExantasTokens.space3),
              Text(FvStrings.arrivalHint, style: text.bodySmall?.copyWith(color: t.textSecondary)),
            ])),
        bottomNavigationBar: _footer(v));
  }

  Widget _work(BuildContext context, FieldVisit v) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final cfg = sync.config;
    final locked = v.contentLocked;
    return Scaffold(
        appBar: AppBar(
            title: Text(FvStrings.reportTitle(v.customerName), overflow: TextOverflow.ellipsis),
            actions: [Padding(padding: const EdgeInsets.only(right: ExantasTokens.gutter), child: Center(child: FvTimerPill(attendance: v.myAttendance, now: widget.env.now)))]),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(padding: const EdgeInsets.all(ExantasTokens.gutter), children: [
              if (error != null) Padding(padding: const EdgeInsets.only(bottom: ExantasTokens.space2), child: Text(error!, style: text.bodyMedium?.copyWith(color: t.danger))),
              if (v.closeRejection != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
                    child: ExCard(
                        key: const ValueKey('fv-close-rejected'),
                        color: t.dangerSoft,
                        child: Text(FvStrings.rejection('${v.closeRejection!['code']}', '${v.closeRejection!['message']}', limitBps: cfg.myDiscountLimitBps), style: text.bodyMedium?.copyWith(color: t.danger)))),
              if (!v.isLead)
                Padding(
                    padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
                    child: ExCard(color: t.accentSoft, child: Text(FvStrings.notLeadHint(v.participants.where((p) => p.isLead).map((p) => p.displayName).join(', ')), style: text.bodyMedium))),
              const ExSectionHeader(FvStrings.jobType),
              const SizedBox(height: ExantasTokens.space2),
              Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                for (final j in cfg.jobTypes.isEmpty ? [FvJobType(v.jobTypeId, '', v.jobTypeLabel, const [])] : cfg.jobTypes)
                  ChoiceChip(
                      showCheckmark: false,
                      label: Text(j.label),
                      selected: j.id == v.jobTypeId,
                      onSelected: locked ? null : (_) => unawaited(sync.changeJobType(v.id, j).catchError((Object e) => setState(() => error = fvErrorText(e))))),
              ]),
              const SizedBox(height: ExantasTokens.space3),
              if (v.checklist.isNotEmpty)
                ExCard(
                    key: const ValueKey('fv-checklist'),
                    padding: const EdgeInsets.symmetric(vertical: ExantasTokens.space2, horizontal: ExantasTokens.space2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(ExantasTokens.space2, ExantasTokens.space1, ExantasTokens.space2, 0),
                          child: Text(FvStrings.checklistTitle(v.jobTypeLabel), style: text.labelLarge?.copyWith(color: t.textSecondary))),
                      for (var i = 0; i < v.checklist.length; i++)
                        CheckboxListTile(
                            key: ValueKey('fv-check-$i'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: ExantasTokens.space2),
                            controlAffinity: ListTileControlAffinity.leading,
                            value: v.checklist[i].checked,
                            title: Text(v.checklist[i].label),
                            onChanged: locked ? null : (on) => _edit((x) => x.checklist[i].checked = on == true)),
                    ])),
              const SizedBox(height: ExantasTokens.space3),
              const ExSectionHeader(FvStrings.description),
              const SizedBox(height: ExantasTokens.space2),
              _DebouncedText(
                  key: const ValueKey('fv-summary'),
                  initial: v.workSummary,
                  enabled: !locked,
                  hint: FvStrings.descriptionHint,
                  controllerOut: (c) => summary = c,
                  onSave: (s) => _edit((x) => x.workSummary = s)),
              if (!locked && cfg.phrasesFor(v.jobTypeId).isNotEmpty) ...[
                const SizedBox(height: ExantasTokens.space2),
                Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
                  for (final p in cfg.phrasesFor(v.jobTypeId))
                    ActionChip(key: ValueKey('fv-phrase-${p.id}'), label: Text('+ ${p.text}'), onPressed: () => _appendPhrase(p.text)),
                ]),
              ],
              const SizedBox(height: ExantasTokens.space3),
              ExCard(
                  padding: EdgeInsets.zero,
                  child: ExListRow(
                      key: const ValueKey('fv-open-equipment'),
                      title: FvStrings.equipmentTitle,
                      subtitle: FvStrings.equipmentCounts(v.equipmentLines.length, v.photos.length),
                      icon: Icons.devices_other_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FvEquipmentPage(env: widget.env, visitId: v.id))))),
              const SizedBox(height: ExantasTokens.space3),
              _participants(context, v),
              if (v.isLead) ...[
                const SizedBox(height: ExantasTokens.space4),
                FilledButton(
                    key: const ValueKey('fv-to-summary'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FvSummaryPage(env: widget.env, visitId: v.id))),
                    child: const Text(FvStrings.toSummary)),
              ],
            ])),
        bottomNavigationBar: _footer(v));
  }
}
