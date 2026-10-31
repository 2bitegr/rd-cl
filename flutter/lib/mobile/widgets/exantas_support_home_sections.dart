import 'package:flutter/material.dart';

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
            borderRadius: BorderRadius.circular(20),
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
                          const SizedBox(height: 3),
                          Text(
                              nativeRecoveryRequired
                                  ? 'Εκκρεμεί σύνδεση RustDesk'
                                  : 'Συνδεδεμένος στο Office',
                              style: text.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant)),
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
    final colors = Theme.of(context).colorScheme;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Νέα σύνδεση',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              TextField(
                  key: const ValueKey('support-connect-field'),
                  controller: controller,
                  enabled: !busy,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                      labelText: 'RustDesk ID υπολογιστή',
                      hintText: 'Πληκτρολόγησε το ID',
                      prefixIcon: Icon(Icons.computer_outlined)),
                  onSubmitted: busy ? null : (_) => connect(context)),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      key: const ValueKey('support-connect-button'),
                      onPressed: busy ? null : () => connect(context),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: const Text('Σύνδεση'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))))),
              const SizedBox(height: 10),
              Text('Για σύνδεση με επιλεγμένη εργασία, άνοιξε «Πελάτες».',
                  style:
                      text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ])));
  }
}

@immutable
class ExantasRecentDevice {
  const ExantasRecentDevice(
      {required this.id,
      required this.label,
      required this.platform,
      required this.online});
  final String id, label, platform;
  final bool online;
}

/// Reads existing native recent peers; availability is not session evidence.
class ExantasRecentDevices extends StatelessWidget {
  const ExantasRecentDevices(
      {super.key,
      required this.devices,
      required this.busy,
      required this.onConnect});
  final List<ExantasRecentDevice> devices;
  final bool busy;
  final ValueChanged<String> onConnect;

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
      return Card(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(children: [
                Icon(Icons.history_rounded,
                    size: 30, color: colors.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text('Δεν υπάρχουν πρόσφατες συνδέσεις.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('Οι υπολογιστές σου θα εμφανίζονται εδώ μετά τη σύνδεση.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ])));
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
                      color: colors.outline.withOpacity(.1)),
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
                            color: colors.primary.withOpacity(.07),
                            borderRadius: BorderRadius.circular(12)),
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
                              ? 'Διαθέσιμος'
                              : 'Μη επιβεβαιωμένη διαθεσιμότητα',
                          child: Icon(
                              devices[index].online
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 8,
                              color: devices[index].online
                                  ? colors.primary
                                  : colors.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right,
                          color: colors.onSurfaceVariant, size: 20),
                    ]),
                    onTap: busy ? null : () => onConnect(devices[index].id)),
              ],
            ])));
  }
}

/// Presentation only. Office authority, renewal and financial decisions stay in
/// the controller. An expired native lease is renewed before a remote connection.
class ExantasSupportHome extends StatefulWidget {
  const ExantasSupportHome(
      {super.key,
      required this.account,
      required this.signedIn,
      required this.busy,
      required this.controller,
      required this.devices,
      required this.customerPanel,
      required this.pendingPanel,
      required this.pendingCount,
      required this.onConnect,
      required this.onRefresh,
      required this.onConfirmNative,
      this.nativeRecoveryRequired = false,
      this.error});
  final Widget account, customerPanel, pendingPanel;
  final bool signedIn, nativeRecoveryRequired, busy;
  final TextEditingController controller;
  final List<ExantasRecentDevice> devices;
  final int pendingCount;
  final ValueChanged<String> onConnect;
  final VoidCallback onRefresh, onConfirmNative;
  final String? error;
  @override
  State<ExantasSupportHome> createState() => _ExantasSupportHomeState();
}

class _ExantasSupportHomeState extends State<ExantasSupportHome> {
  String section = 'recent';
  bool showAllRecent = false;

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final colors = parent.colorScheme;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outline.withOpacity(.3)));
    final theme = parent.copyWith(
      cardTheme: CardTheme(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colors.outline.withOpacity(.12)))),
      inputDecorationTheme: parent.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.onSurface.withOpacity(.025),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
              borderSide: BorderSide(color: colors.primary, width: 1.5))),
    );
    return Theme(
        data: theme,
        child: ColoredBox(
            color: colors.onSurface.withOpacity(.025),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  widget.account,
                  if (widget.busy)
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2)),
                  if (widget.error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Card(
                            color: colors.errorContainer,
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                    widget.error!.replaceFirst(
                                        RegExp(r'^(Exception|Bad state):\s*'),
                                        ''),
                                    style: TextStyle(
                                        color: colors.onErrorContainer))))),
                  if (widget.signedIn) ...[
                    if (widget.nativeRecoveryRequired)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                            'Η προηγούμενη σύνδεση RustDesk δεν επιβεβαιώθηκε.'),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                            key: const ValueKey(
                                                'support-native-retry'),
                                            onPressed: widget.busy
                                                ? null
                                                : widget.onConfirmNative,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text(
                                                'Επανάληψη σύνδεσης RustDesk')),
                                      ])))),
                    const SizedBox(height: 14),
                    ExantasQuickConnect(
                        controller: widget.controller,
                        busy: widget.busy,
                        onConnect: () =>
                            widget.onConnect(widget.controller.text)),
                    const SizedBox(height: 18),
                    DecoratedBox(
                        decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Row(children: [
                              for (final item in [
                                ('recent', Icons.history_rounded, 'Πρόσφατα'),
                                (
                                  'customers',
                                  Icons.business_outlined,
                                  'Πελάτες'
                                ),
                                (
                                  'pending',
                                  Icons.pending_actions_outlined,
                                  'Εκκρεμή'
                                ),
                              ])
                                Expanded(
                                    child: Semantics(
                                        selected: section == item.$1,
                                        label: item.$1 == 'pending'
                                            ? 'Εκκρεμή (${widget.pendingCount})'
                                            : item.$3,
                                        child: TextButton(
                                            key: ValueKey(
                                                'support-tab-${item.$1}'),
                                            onPressed: () => setState(
                                                () => section = item.$1),
                                            style: TextButton.styleFrom(
                                                minimumSize: const Size(0, 58),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                        vertical: 8),
                                                backgroundColor:
                                                    section == item.$1
                                                        ? colors.primary
                                                            .withOpacity(.1)
                                                        : null,
                                                foregroundColor: section ==
                                                        item.$1
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12))),
                                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                              Badge.count(
                                                  count: widget.pendingCount,
                                                  isLabelVisible: item.$1 ==
                                                          'pending' &&
                                                      widget.pendingCount > 0,
                                                  child:
                                                      Icon(item.$2, size: 21)),
                                              const SizedBox(height: 5),
                                              Text(item.$3,
                                                  textAlign: TextAlign.center,
                                                  style: parent
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          fontWeight: section ==
                                                                  item.$1
                                                              ? FontWeight.w600
                                                              : FontWeight
                                                                  .w400)),
                                            ])))),
                            ]))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(2, 12, 0, 4),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  section == 'recent'
                                      ? 'Πρόσφατες συνδέσεις'
                                      : section == 'customers'
                                          ? 'Πελάτες και εργασίες'
                                          : 'Εκκρεμείς αποφάσεις',
                                  style: parent.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600))),
                          IconButton(
                              tooltip: 'Ανανέωση',
                              onPressed: widget.busy ? null : widget.onRefresh,
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: Icon(Icons.refresh_rounded,
                                  size: 21, color: colors.onSurfaceVariant)),
                        ])),
                    if (section == 'recent') ...[
                      ExantasRecentDevices(
                          devices: showAllRecent
                              ? widget.devices
                              : widget.devices.take(8).toList(),
                          busy: widget.busy,
                          onConnect: widget.onConnect),
                      if (widget.devices.length > 8)
                        TextButton(
                            onPressed: () =>
                                setState(() => showAllRecent = !showAllRecent),
                            child: Text(showAllRecent
                                ? 'Λιγότερες συσκευές'
                                : 'Όλες οι πρόσφατες (${widget.devices.length})')),
                    ],
                    if (section == 'customers') widget.customerPanel,
                    if (section == 'pending') widget.pendingPanel,
                  ],
                ])));
  }
}
