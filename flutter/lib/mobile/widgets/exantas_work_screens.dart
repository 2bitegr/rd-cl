import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/exantas_office_work.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_list_row.dart';
import '../ui/ex_offline_banner.dart';
import '../ui/ex_search_field.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_segmented.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_theme.dart';
import 'exantas_support_home_sections.dart' show ExantasErrorCard;

class ExWork {
  static const today = 'Σήμερα';
  static const open = 'Ανοιχτές';
  static const noToday = 'Δεν υπάρχουν εργασίες για σήμερα.';
  static const noTodayHint =
      'Εμφανίζονται εργασίες όπου συμμετέχεις και έχουν δραστηριότητα σήμερα.';
  static const noOpen = 'Δεν έχεις ανοιχτές εργασίες.';
  static const noCustomers = 'Δεν βρέθηκαν πελάτες.';
  static const searchHint = 'Πληκτρολόγησε για αναζήτηση πελάτη.';
  static const accountChanged =
      'Ο λογαριασμός Office άλλαξε. Γύρισε πίσω και άνοιξε ξανά.';
  static const retry = 'Δοκιμή ξανά';
  static const loadMore = 'Περισσότερες εργασίες';
  static const truncated = 'Εμφανίζονται οι πρώτες 200 εργασίες.';
  static const pendingDecision = 'Εκκρεμεί απόφαση';
  static const otherTechnician = 'Άλλου τεχνικού';
  static const askToJoin = 'Ζήτα από τον υπεύθυνο να σε προσθέσει στην εργασία';
  static const newWork = 'Νέα εργασία';
  static const computers = 'Υπολογιστές';
  static const openWork = 'Ανοιχτές εργασίες';
  static const summary = 'Σύνοψη';
  static const timeline = 'Χρονολόγιο';
  static const noComputers = 'Δεν υπάρχουν διαθέσιμοι υπολογιστές.';
  static const noTimeline = 'Δεν υπάρχουν καταγεγραμμένες δραστηριότητες.';
  static const unverified = 'Αναμονή επαλήθευσης διάρκειας';
  static const cannotConnect = 'Μη διαθέσιμος για σύνδεση';
  static const readOnly =
      'Δεν έχεις δικαίωμα επεξεργασίας αυτής της εργασίας. Η σύνδεση δεν είναι διαθέσιμη.';
  static const customerComputers = 'Εξουσιοδοτημένοι υπολογιστές';
  static const connectViaWork =
      'Η σύνδεση γίνεται μέσα από μια εργασία του πελάτη.';

  static (String, ExStatus) state(String s) => switch (s) {
        'draft' => ('Πρόχειρη', ExStatus.info),
        'review' => ('Προς έλεγχο', ExStatus.warning),
        'finalized' => ('Ολοκληρωμένη', ExStatus.success),
        'ignored' => ('Αγνοήθηκε', ExStatus.neutral),
        _ => (s.isEmpty ? 'Άγνωστη κατάσταση' : s, ExStatus.neutral),
      };
  static String nextAction(String s) => switch (s) {
        'draft' => 'Συνέχεια εργασίας',
        'review' => 'Έλεγχος και ολοκλήρωση',
        _ => 'Προβολή εργασίας',
      };
}

class OfficeWorkCardTile extends StatelessWidget {
  const OfficeWorkCardTile(
      {super.key, required this.card, required this.onTap, this.pending = false});
  final OfficeWorkCard card;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final (label, status) = ExWork.state(card.supportState);
    final place = [card.customerName, card.branchName]
        .where((e) => e.isNotEmpty)
        .join(' · ');
    final readOnly = !card.isParticipant;
    return ExCard(
        onTap: readOnly ? null : onTap,
        child: Opacity(
            opacity: readOnly ? 0.6 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(card.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          if (place.isNotEmpty) ...[
            const SizedBox(height: ExantasTokens.space1),
            Text(place,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium),
          ],
          const SizedBox(height: ExantasTokens.space2),
          Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space1, children: [
            ExStatusPill(label, status: status),
            if (pending)
              const ExStatusPill(ExWork.pendingDecision, status: ExStatus.warning),
            if (readOnly)
              const ExStatusPill(ExWork.otherTechnician, status: ExStatus.info),
          ]),
          const SizedBox(height: ExantasTokens.space2),
          if (readOnly)
            Text(ExWork.askToJoin,
                style: text.bodySmall?.copyWith(color: t.textSecondary))
          else
          Row(children: [
            Expanded(
                child: Text('Ενημερώθηκε ${formatAthens(card.updatedAt)}',
                    style: text.bodySmall?.copyWith(color: t.textSecondary))),
            Flexible(
                child: Text(ExWork.nextAction(card.supportState),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(color: t.accent))),
            Icon(Icons.chevron_right, size: 18, color: t.accent),
          ]),
        ])));
  }
}

/// Loading / error / offline / empty frame shared by the three feeds.
class OfficeFeedBody<T> extends StatelessWidget {
  const OfficeFeedBody(
      {super.key,
      required this.feed,
      required this.itemBuilder,
      required this.emptyIcon,
      required this.emptyTitle,
      required this.onRetry,
      this.emptyMessage,
      this.onMore});
  final OfficeFeed<T> feed;
  final Widget Function(T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final VoidCallback onRetry;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final loading = feed.state == OfficeLoad.loading;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (feed.offline) const ExOfflineBanner(),
      if (feed.state == OfficeLoad.error) ...[
        ExantasErrorCard(feed.error),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                key: const ValueKey('office-feed-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text(ExWork.retry))),
      ],
      if (loading && feed.items.isEmpty)
        const Padding(
            key: ValueKey('office-feed-loading'),
            padding: EdgeInsets.all(ExantasTokens.space6),
            child: Center(child: CircularProgressIndicator())),
      if (feed.state == OfficeLoad.ready && feed.items.isEmpty)
        ExEmptyState(
            key: const ValueKey('office-feed-empty'),
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage),
      for (final item in feed.items) ...[
        itemBuilder(item),
        const SizedBox(height: ExantasTokens.space2),
      ],
      if (feed.truncated)
        Padding(
            padding: const EdgeInsets.all(ExantasTokens.space2),
            child: Text(ExWork.truncated,
                style: Theme.of(context).textTheme.bodySmall)),
      if (onMore != null)
        TextButton(
            key: const ValueKey('office-feed-more'),
            onPressed: loading ? null : onMore,
            child: const Text(ExWork.loadMore)),
    ]);
  }
}

class OfficeWorkFeedPanel extends StatelessWidget {
  const OfficeWorkFeedPanel(
      {super.key,
      required this.feed,
      required this.pendingWorkIds,
      required this.onOpen,
      required this.onRetry,
      required this.emptyTitle,
      this.emptyMessage,
      this.onMore});
  final OfficeFeed<OfficeWorkCard> feed;
  final Set<String> pendingWorkIds;
  final ValueChanged<OfficeWorkCard> onOpen;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String? emptyMessage;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => OfficeFeedBody<OfficeWorkCard>(
      feed: feed,
      emptyIcon: Icons.assignment_outlined,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      onRetry: onRetry,
      onMore: feed.nextPage == null ? null : onMore,
      itemBuilder: (c) => OfficeWorkCardTile(
          key: ValueKey('work-card-${c.id}'),
          card: c,
          pending: pendingWorkIds.contains(c.id),
          onTap: () => onOpen(c)));
}

/// Debounced customer search. Stale responses are discarded by the controller.
class OfficeCustomersPanel extends StatefulWidget {
  const OfficeCustomersPanel(
      {super.key,
      required this.controller,
      required this.feed,
      required this.onSearch,
      required this.onOpen,
      this.debounce = const Duration(milliseconds: 350)});
  final TextEditingController controller;
  final OfficeFeed<Map<String, dynamic>> feed;
  final ValueChanged<String> onSearch;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Duration debounce;
  @override
  State<OfficeCustomersPanel> createState() => _OfficeCustomersPanelState();
}

class _OfficeCustomersPanelState extends State<OfficeCustomersPanel> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void changed(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onSearch(value));
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ExSearchField(
            key: const ValueKey('support-customer-search'),
            controller: widget.controller,
            label: 'Αναζήτηση πελάτη',
            onChanged: changed,
            onSubmitted: (v) {
              _timer?.cancel();
              widget.onSearch(v);
            }),
        const SizedBox(height: ExantasTokens.space3),
        OfficeFeedBody<Map<String, dynamic>>(
            feed: widget.feed,
            emptyIcon: Icons.business_outlined,
            emptyTitle: ExWork.noCustomers,
            onRetry: () => widget.onSearch(widget.controller.text),
            itemBuilder: (c) => ExCard(
                key: ValueKey('customer-row-${c['id']}'),
                padding: EdgeInsets.zero,
                child: ExListRow(
                    icon: Icons.business_outlined,
                    title: '${c['company_name'] ?? ''}',
                    subtitle: [
                      if ('${c['afm'] ?? ''}'.isNotEmpty) 'ΑΦΜ ${c['afm']}',
                      if ('${c['external_code'] ?? ''}'.isNotEmpty)
                        '${c['external_code']}',
                    ].join(' · '),
                    onTap: () => widget.onOpen(c)))),
      ]);
}

/// Customer page: authorized computers, open work and "Νέα εργασία".
class OfficeCustomerPage extends StatefulWidget {
  const OfficeCustomerPage(
      {super.key,
      required this.customer,
      required this.office,
      required this.pendingWorkIds,
      required this.onOpenWork,
      required this.onNewWork});
  final Map<String, dynamic> customer;
  final ExantasOfficeWork office;
  final Set<String> pendingWorkIds;
  final void Function(OfficeWorkCard) onOpenWork;

  /// Runs the existing creation flow; returns the created work card or null.
  final Future<OfficeWorkCard?> Function(Map<String, dynamic> customer) onNewWork;
  @override
  State<OfficeCustomerPage> createState() => _OfficeCustomerPageState();
}

class _OfficeCustomerPageState extends State<OfficeCustomerPage> {
  CustomerDetail? data;
  String? error;
  bool loading = true, offline = false, creating = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final epoch = widget.office.epoch;
      final next = await widget.office.loadCustomer('${widget.customer['id']}');
      if (!mounted) return;
      if (next == null) {
        if (epoch != widget.office.epoch) {
          setState(() {
            error = ExWork.accountChanged;
            loading = false;
          });
        }
        return;
      }
      setState(() {
        data = next;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = describeOfficeError(e);
        offline = isOfflineError(e);
        loading = false;
      });
    }
  }

  Future<void> newWork() async {
    setState(() => creating = true);
    try {
      final card = await widget.onNewWork(widget.customer);
      if (!mounted) return;
      setState(() => creating = false);
      if (card != null) {
        unawaited(load());
        widget.onOpenWork(card);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        creating = false;
        error = describeOfficeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final d = data;
    return Scaffold(
        appBar: AppBar(title: Text('${widget.customer['company_name'] ?? ''}')),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                children: [
                  if (offline) const ExOfflineBanner(),
                  ExantasErrorCard(error),
                  if (loading)
                    const Padding(
                        padding: EdgeInsets.all(ExantasTokens.space6),
                        child: Center(child: CircularProgressIndicator())),
                  if (error != null && d == null)
                    TextButton.icon(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        label: const Text(ExWork.retry)),
                  const SizedBox(height: ExantasTokens.space3),
                  FilledButton.icon(
                      key: const ValueKey('customer-new-work'),
                      onPressed: creating ? null : newWork,
                      icon: const Icon(Icons.add),
                      label: const Text(ExWork.newWork)),
                  if (d != null) ...[
                    const SizedBox(height: ExantasTokens.space4),
                    const ExSectionHeader(ExWork.openWork),
                    const SizedBox(height: ExantasTokens.space2),
                    if (d.works.isEmpty)
                      const ExEmptyState(
                          icon: Icons.assignment_outlined,
                          title: 'Δεν υπάρχουν ανοιχτές εργασίες.'),
                    for (final c in d.works) ...[
                      OfficeWorkCardTile(
                          key: ValueKey('work-card-${c.id}'),
                          card: c,
                          pending: widget.pendingWorkIds.contains(c.id),
                          onTap: () => widget.onOpenWork(c)),
                      const SizedBox(height: ExantasTokens.space2),
                    ],
                    const SizedBox(height: ExantasTokens.space4),
                    const ExSectionHeader(ExWork.customerComputers),
                    const SizedBox(height: ExantasTokens.space2),
                    if (d.devices.isEmpty)
                      const ExEmptyState(
                          icon: Icons.computer_outlined,
                          title: ExWork.noComputers),
                    if (d.devices.isNotEmpty)
                      ExCard(
                          padding: EdgeInsets.zero,
                          child: Column(children: [
                            for (final dev in d.devices)
                              ExListRow(
                                  key: ValueKey('customer-device-${dev['id']}'),
                                  icon: Icons.computer_outlined,
                                  title: '${dev['label'] ?? dev['peer_id']}',
                                  subtitle: '${dev['peer_id']}'),
                          ])),
                    const SizedBox(height: ExantasTokens.space2),
                    Text(ExWork.connectViaWork,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ])));
  }
}

enum WorkDetailSection { summary, computers, timeline }

/// Work detail from supportV2Context. Connection is delegated to [onConnect]
/// (the existing page connection path); this widget never opens sessions.
class OfficeWorkDetailPage extends StatefulWidget {
  const OfficeWorkDetailPage(
      {super.key,
      required this.card,
      required this.office,
      required this.onConnect,
      this.pending = false});
  final OfficeWorkCard card;
  final ExantasOfficeWork office;
  final bool pending;
  final Future<void> Function(WorkDetail work, WorkDevice device) onConnect;
  @override
  State<OfficeWorkDetailPage> createState() => _OfficeWorkDetailPageState();
}

class _OfficeWorkDetailPageState extends State<OfficeWorkDetailPage> {
  WorkDetail? detail;
  String? error;
  bool loading = true, offline = false, connecting = false;
  WorkDetailSection section = WorkDetailSection.summary;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final epoch = widget.office.epoch;
      final next = await widget.office.loadDetail(widget.card.id);
      if (!mounted) return;
      if (next == null) {
        if (epoch != widget.office.epoch) {
          setState(() {
            error = ExWork.accountChanged;
            loading = false;
          });
        }
        return;
      }
      setState(() {
        detail = next;
        loading = false;
        offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = describeOfficeError(e);
        offline = isOfflineError(e);
        loading = false;
      });
    }
  }

  Future<void> connect(WorkDetail work, WorkDevice device) async {
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      await widget.onConnect(work, device);
    } catch (e) {
      if (mounted) setState(() => error = describeOfficeError(e));
    } finally {
      if (mounted) setState(() => connecting = false);
    }
    if (mounted) unawaited(load());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    final d = detail;
    final title = d?.title ?? widget.card.title;
    final state = d?.supportState ?? widget.card.supportState;
    final (stateLabel, stateStatus) = ExWork.state(state);
    final customer = d?.customerName ?? widget.card.customerName;
    final branch = d?.branchName ?? widget.card.branchName;
    return Scaffold(
        appBar: AppBar(title: const Text('Εργασία')),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                children: [
                  Text(title, style: text.titleLarge),
                  const SizedBox(height: ExantasTokens.space2),
                  Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space1, children: [
                    ExStatusPill(stateLabel, status: stateStatus),
                    if (widget.pending)
                      const ExStatusPill(ExWork.pendingDecision,
                          status: ExStatus.warning),
                  ]),
                  const SizedBox(height: ExantasTokens.space2),
                  Text([customer, branch].where((e) => e.isNotEmpty).join(' · '),
                      style: text.bodyMedium),
                  if (offline) const ExOfflineBanner(),
                  ExantasErrorCard(error),
                  if (error != null && d == null)
                    TextButton.icon(
                        key: const ValueKey('work-detail-retry'),
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        label: const Text(ExWork.retry)),
                  if (loading && d == null)
                    const Padding(
                        padding: EdgeInsets.all(ExantasTokens.space6),
                        child: Center(child: CircularProgressIndicator())),
                  if (d != null) ...[
                    const SizedBox(height: ExantasTokens.space3),
                    ExSegmented<WorkDetailSection>(
                        segments: const [
                          ExSegment(WorkDetailSection.summary, ExWork.summary,
                              key: ValueKey('work-tab-summary')),
                          ExSegment(WorkDetailSection.computers, ExWork.computers,
                              key: ValueKey('work-tab-computers')),
                          ExSegment(WorkDetailSection.timeline, ExWork.timeline,
                              key: ValueKey('work-tab-timeline')),
                        ],
                        selected: section,
                        onChanged: (v) => setState(() => section = v)),
                    const SizedBox(height: ExantasTokens.space3),
                    if (section == WorkDetailSection.summary) summary(d),
                    if (section == WorkDetailSection.computers) computers(d),
                    if (section == WorkDetailSection.timeline) WorkTimeline(d.timeline),
                  ],
                ])));
  }

  Widget summary(WorkDetail d) => ExCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.description.isEmpty ? 'Χωρίς περιγραφή.' : d.description),
        const SizedBox(height: ExantasTokens.space3),
        Text('Υπολογιστές: ${d.devices.length}  ·  Δραστηριότητες: ${d.timeline.length}',
            style: Theme.of(context).textTheme.bodySmall),
      ]));

  Widget computers(WorkDetail d) {
    if (d.devices.isEmpty) {
      return const ExEmptyState(
          icon: Icons.computer_outlined, title: ExWork.noComputers);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!d.canEdit)
        const Padding(
            padding: EdgeInsets.only(bottom: ExantasTokens.space2),
            child: Text(ExWork.readOnly)),
      ExCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final dev in d.devices)
              ExListRow(
                  key: ValueKey('work-device-${dev.id}'),
                  icon: Icons.computer_outlined,
                  title: dev.label,
                  subtitle: dev.canConnect ? dev.peerId : '${dev.peerId} · ${ExWork.cannotConnect}',
                  onTap: dev.canConnect && d.canEdit && !connecting
                      ? () => connect(d, dev)
                      : null),
          ])),
    ]);
  }
}

class WorkTimeline extends StatelessWidget {
  const WorkTimeline(this.entries, {super.key});
  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const ExEmptyState(
          icon: Icons.history_rounded, title: ExWork.noTimeline);
    }
    final text = Theme.of(context).textTheme;
    final t = context.ex;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in entries) ...[
        ExCard(
            key: ValueKey('timeline-${e.kind.name}-${e.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  e.kind == TimelineKind.call
                      ? (e.callLabel.isEmpty ? 'Κλήση' : e.callLabel)
                      : 'Συνεδρία απομακρυσμένης υποστήριξης',
                  style: text.titleSmall),
              const SizedBox(height: ExantasTokens.space1),
              Text(formatAthens(e.start, time: false), style: text.bodyMedium),
              Text(
                  e.end == null
                      ? 'Έναρξη ${formatAthens(e.start, date: false)}'
                      : '${formatAthens(e.start, date: false)} – ${formatAthens(e.end, date: false)}',
                  style: text.bodyMedium),
              if (e.technician.isNotEmpty)
                Text('Τεχνικός: ${e.technician}',
                    style: text.bodySmall?.copyWith(color: t.textSecondary)),
              if (e.computer.isNotEmpty)
                Text('Υπολογιστής: ${e.computer}',
                    style: text.bodySmall?.copyWith(color: t.textSecondary)),
              if (e.kind == TimelineKind.session) ...[
                const SizedBox(height: ExantasTokens.space2),
                if (e.verified && e.durationSeconds != null)
                  ExStatusPill(
                      'Διάρκεια ${formatDurationSeconds(e.durationSeconds!)}',
                      status: ExStatus.success)
                else
                  const ExStatusPill(ExWork.unverified, status: ExStatus.warning),
              ],
            ])),
        const SizedBox(height: ExantasTokens.space2),
      ],
    ]);
  }
}
