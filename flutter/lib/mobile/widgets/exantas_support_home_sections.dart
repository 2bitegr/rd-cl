import 'package:flutter/material.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_search_field.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_segmented.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';

/// Office sign-in survives short native-lease expiry. Show recovery only for an
/// explicitly unconfirmed issuance, never infer logout from native readiness.
class ExantasAccountSummary extends StatelessWidget {
  const ExantasAccountSummary(
      {super.key,
      required this.name,
      required this.sourceId,
      required this.onAccount,
      required this.onCopyId,
      this.nativeRecoveryRequired = false});
  final String name, sourceId;
  final bool nativeRecoveryRequired;
  final VoidCallback onAccount, onCopyId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
        child: InkWell(
            onTap: onAccount,
            borderRadius: BorderRadius.circular(ExantasTokens.radiusLg),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Column(children: [
                  Row(children: [
                    CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.primary.withOpacity(.09),
                        child: Icon(Icons.support_agent,
                            color: colors.primary, size: 23)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: nativeRecoveryRequired
                                  ? const ExStatusPill(
                                      'Εκκρεμεί σύνδεση RustDesk',
                                      status: ExStatus.warning)
                                  : const ExStatusPill(
                                      'Συνδεδεμένος στο Office',
                                      status: ExStatus.success)),
                        ])),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: colors.onSurfaceVariant, size: 22),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const SizedBox(width: 2),
                    Icon(Icons.smartphone_outlined,
                        size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            sourceId.isEmpty
                                ? 'Το ID ετοιμάζεται…'
                                : 'Το ID μου: $sourceId',
                            style: text.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant))),
                    IconButton(
                        key: const ValueKey('support-copy-id'),
                        tooltip: 'Αντιγραφή RustDesk ID',
                        onPressed: sourceId.isEmpty ? null : onCopyId,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: const Icon(Icons.copy_outlined, size: 19)),
                  ]),
                ]))));
  }
}

/// Manual entry retains the existing connection and exact-association policy.
class ExantasQuickConnect extends StatelessWidget {
  const ExantasQuickConnect(
      {super.key,
      required this.controller,
      required this.busy,
      required this.onConnect});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect;

  void connect(BuildContext context) {
    FocusScope.of(context).unfocus();
    onConnect();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ExCard(
        padding: const EdgeInsets.all(ExantasTokens.space4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ExStrings.newConnection, style: text.titleMedium),
          const SizedBox(height: ExantasTokens.space3),
          TextField(
              key: const ValueKey('support-connect-field'),
              controller: controller,
              enabled: !busy,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: ExStrings.remoteIdLabel,
                  hintText: ExStrings.remoteIdHint,
                  prefixIcon: Icon(Icons.computer_outlined)),
              onSubmitted: busy ? null : (_) => connect(context)),
          const SizedBox(height: ExantasTokens.space3),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  key: const ValueKey('support-connect-button'),
                  onPressed: busy ? null : () => connect(context),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: const Text(ExStrings.connect))),
          const SizedBox(height: ExantasTokens.space2),
          Text('Θα επιλέξεις αν η σύνδεση γίνεται με ή χωρίς εργασία.',
              style: text.bodySmall),
        ]));
  }
}

@immutable
class ExantasRecentDevice {
  const ExantasRecentDevice(
      {required this.id,
      required this.label,
      required this.platform,
      required this.online,
      this.pinned = false});
  final String id, label, platform;
  final bool online, pinned;
}

/// Reads existing native recent peers; availability is not session evidence.
class ExantasRecentDevices extends StatelessWidget {
  const ExantasRecentDevices(
      {super.key,
      required this.devices,
      required this.busy,
      required this.onConnect,
      this.onTogglePin});
  final List<ExantasRecentDevice> devices;
  final bool busy;
  final ValueChanged<String> onConnect;
  final ValueChanged<String>? onTogglePin;

  IconData _platformIcon(String platform) {
    final value = platform.toLowerCase();
    if (value.contains('android')) return Icons.phone_android;
    if (value.contains('windows')) return Icons.desktop_windows_outlined;
    if (value.contains('mac') || value.contains('ios')) return Icons.laptop_mac;
    if (value.contains('linux')) return Icons.computer;
    return Icons.devices_other;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (devices.isEmpty) {
      return const ExCard(
          padding: EdgeInsets.zero,
          child: ExEmptyState(
              icon: Icons.history_rounded,
              title: ExStrings.noRecent,
              message: ExStrings.noRecentHint));
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (var index = 0; index < devices.length; index++) ...[
                if (index > 0)
                  Divider(
                      height: 1,
                      indent: 74,
                      endIndent: 16,
                      color: colors.outlineVariant),
                ListTile(
                    key: ValueKey('recent-${devices[index].id}'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    minVerticalPadding: 10,
                    enabled: !busy,
                    leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(ExantasTokens.radiusMd)),
                        child: Icon(_platformIcon(devices[index].platform),
                            size: 23, color: colors.primary)),
                    title: Text(
                        devices[index].label.isEmpty
                            ? devices[index].id
                            : devices[index].label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    subtitle: Text(devices[index].id,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Semantics(
                          label: devices[index].online
                              ? ExStrings.available
                              : ExStrings.availabilityUnconfirmed,
                          child: Icon(
                              devices[index].online
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 8,
                              color: devices[index].online
                                  ? colors.primary
                                  : colors.onSurfaceVariant)),
                      if (onTogglePin != null)
                        IconButton(
                            key: ValueKey('pin-${devices[index].id}'),
                            tooltip: devices[index].pinned
                                ? 'Ξεκαρφίτσωμα'
                                : 'Καρφίτσωμα',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            onPressed: busy
                                ? null
                                : () => onTogglePin!(devices[index].id),
                            icon: Icon(
                                devices[index].pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 20,
                                color: devices[index].pinned
                                    ? colors.primary
                                    : colors.onSurfaceVariant))
                      else
                        const SizedBox(width: 8),
                      Icon(Icons.chevron_right,
                          color: colors.onSurfaceVariant, size: 20),
                    ]),
                    onTap: busy ? null : () => onConnect(devices[index].id)),
              ],
            ])));
  }
}

/// Home: account/readiness, connect by ID, customer search, pending, recent.
/// Presentation only. Office authority, renewal and financial decisions stay in
/// the controller. An expired native lease is renewed before a remote connection.
class ExantasSupportHome extends StatefulWidget {
  const ExantasSupportHome(
      {super.key,
      required this.account,
      required this.signedIn,
      required this.busy,
      required this.controller,
      required this.searchController,
      required this.devices,
      required this.pendingCount,
      required this.onConnect,
      required this.onSearchCustomers,
      required this.onOpenPending,
      required this.onRefresh,
      required this.onConfirmNative,
      this.nativeRecoveryRequired = false,
      this.pendingSummary = '',
      this.pinnedIds = const {},
      this.onTogglePin,
      this.error});
  final Widget account;
  final bool signedIn, nativeRecoveryRequired, busy;
  final TextEditingController controller, searchController;
  final List<ExantasRecentDevice> devices;
  final int pendingCount;
  final ValueChanged<String> onConnect, onSearchCustomers;
  final VoidCallback onOpenPending, onRefresh, onConfirmNative;
  final String? error;
  final String pendingSummary;
  final Set<String> pinnedIds;
  final ValueChanged<String>? onTogglePin;
  @override
  State<ExantasSupportHome> createState() => _ExantasSupportHomeState();
}

class _ExantasSupportHomeState extends State<ExantasSupportHome> {
  bool showAllRecent = false;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    const gap = SizedBox(height: ExantasTokens.space4);
    // Pinned (RustDesk favorites) first; recents keep their native order.
    final sorted = [
      ...widget.devices.where((d) => widget.pinnedIds.contains(d.id)),
      ...widget.devices.where((d) => !widget.pinnedIds.contains(d.id)),
    ].map((d) => d.pinned == widget.pinnedIds.contains(d.id)
        ? d
        : ExantasRecentDevice(
            id: d.id,
            label: d.label,
            platform: d.platform,
            online: d.online,
            pinned: widget.pinnedIds.contains(d.id))).toList();
    return ColoredBox(
        color: t.surfaceAlt,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(
                ExantasTokens.gutter, ExantasTokens.space3, ExantasTokens.gutter, 28),
            children: [
              widget.account,
              if (widget.busy)
                const Padding(
                    padding: EdgeInsets.only(top: ExantasTokens.space2),
                    child: LinearProgressIndicator(minHeight: 2)),
              ExantasErrorCard(widget.error),
              if (widget.signedIn) ...[
                if (widget.nativeRecoveryRequired)
                  Padding(
                      padding: const EdgeInsets.only(top: ExantasTokens.space3),
                      child: ExCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text(
                                'Η προηγούμενη σύνδεση RustDesk δεν επιβεβαιώθηκε.'),
                            const SizedBox(height: ExantasTokens.space2),
                            OutlinedButton.icon(
                                key: const ValueKey('support-native-retry'),
                                onPressed:
                                    widget.busy ? null : widget.onConfirmNative,
                                icon: const Icon(Icons.refresh),
                                label: const Text(
                                    'Επανάληψη σύνδεσης RustDesk')),
                          ]))),
                gap,
                ExantasQuickConnect(
                    controller: widget.controller,
                    busy: widget.busy,
                    onConnect: () => widget.onConnect(widget.controller.text)),
                gap,
                ExSearchField(
                    key: const ValueKey('support-home-search'),
                    controller: widget.searchController,
                    label: ExStrings.searchCustomer,
                    enabled: !widget.busy,
                    onSubmitted: widget.onSearchCustomers),
                gap,
                ExCard(
                    key: const ValueKey('support-pending-card'),
                    onTap: widget.onOpenPending,
                    child: Row(children: [
                      Icon(Icons.pending_actions_outlined, color: t.accent),
                      const SizedBox(width: ExantasTokens.space3),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(ExStrings.pendingCount(widget.pendingCount),
                                style: Theme.of(context).textTheme.titleSmall),
                            Text(
                                widget.pendingSummary.isNotEmpty
                                    ? widget.pendingSummary
                                    : ExStrings.pendingHint(widget.pendingCount),
                                style: Theme.of(context).textTheme.bodySmall),
                          ])),
                      Icon(Icons.chevron_right, color: t.textSecondary),
                    ])),
                gap,
                ExSectionHeader(ExStrings.recent,
                    action: IconButton(
                        tooltip: ExStrings.refresh,
                        onPressed: widget.busy ? null : widget.onRefresh,
                        icon: Icon(Icons.refresh_rounded,
                            size: 21, color: t.textSecondary))),
                const SizedBox(height: ExantasTokens.space2),
                ExantasRecentDevices(
                    devices: showAllRecent ? sorted : sorted.take(8).toList(),
                    busy: widget.busy,
                    onConnect: widget.onConnect,
                    onTogglePin: widget.onTogglePin),
                if (widget.devices.length > 8)
                  TextButton(
                      onPressed: () =>
                          setState(() => showAllRecent = !showAllRecent),
                      child: Text(showAllRecent
                          ? ExStrings.fewerRecent
                          : ExStrings.allRecentCount(widget.devices.length))),
              ],
            ]));
  }
}

/// Shared inline error card (Office/native errors from the controller).
class ExantasErrorCard extends StatelessWidget {
  const ExantasErrorCard(this.error, {super.key});
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    final t = context.ex;
    return Padding(
        padding: const EdgeInsets.only(top: ExantasTokens.space3),
        child: ExCard(
            color: t.dangerSoft,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, size: 20, color: t.danger),
              const SizedBox(width: ExantasTokens.space2),
              Expanded(
                  child: Text(
                      error!.replaceFirst(
                          RegExp(r'^(Exception|Bad state):\s*'), ''),
                      style: TextStyle(color: t.danger))),
            ])));
  }
}

enum ExantasWorkSection { today, open, customers, pending }

/// Work tab: Σήμερα | Ανοιχτές | Πελάτες | Εκκρεμή. Panels are supplied by the
/// controller; this widget only lays out the segments.
class ExantasWorkView extends StatelessWidget {
  const ExantasWorkView(
      {super.key,
      required this.signedIn,
      required this.busy,
      required this.section,
      required this.onSection,
      required this.customerPanel,
      required this.pendingPanel,
      required this.pendingCount,
      required this.onRefresh,
      this.todayPanel = const SizedBox.shrink(),
      this.openPanel = const SizedBox.shrink(),
      this.error});
  final Widget todayPanel, openPanel;
  final bool signedIn, busy;
  final ExantasWorkSection section;
  final ValueChanged<ExantasWorkSection> onSection;
  final Widget customerPanel, pendingPanel;
  final int pendingCount;
  final VoidCallback onRefresh;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return ColoredBox(
        color: t.surfaceAlt,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(
                ExantasTokens.gutter, ExantasTokens.space3, ExantasTokens.gutter, 28),
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              ExantasErrorCard(error),
              if (!signedIn)
                const ExEmptyState(
                    icon: Icons.lock_outline, title: ExStrings.signInForWork)
              else ...[
                const SizedBox(height: ExantasTokens.space3),
                Row(children: [
                  Expanded(
                      child: ExSegmented<ExantasWorkSection>(
                          segments: [
                            const ExSegment(ExantasWorkSection.today, ExStrings.today,
                                key: ValueKey('support-tab-today')),
                            const ExSegment(ExantasWorkSection.open, ExStrings.openWork,
                                key: ValueKey('support-tab-open')),
                            const ExSegment(ExantasWorkSection.customers,
                                ExStrings.customers,
                                key: ValueKey('support-tab-customers')),
                            ExSegment(ExantasWorkSection.pending,
                                pendingCount == 0
                                    ? ExStrings.pending
                                    : ExStrings.pendingCount(pendingCount),
                                key: const ValueKey('support-tab-pending')),
                          ],
                          selected: section,
                          onChanged: onSection)),
                  IconButton(
                      tooltip: ExStrings.refresh,
                      onPressed: busy ? null : onRefresh,
                      icon: Icon(Icons.refresh_rounded, color: t.textSecondary)),
                ]),
                const SizedBox(height: ExantasTokens.space3),
                if (section == ExantasWorkSection.today) todayPanel,
                if (section == ExantasWorkSection.open) openPanel,
                if (section == ExantasWorkSection.customers) customerPanel,
                if (section == ExantasWorkSection.pending) pendingPanel,
              ],
            ]));
  }
}
