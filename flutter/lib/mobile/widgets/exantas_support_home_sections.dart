import 'package:flutter/material.dart';

/// Compact account and native RustDesk readiness summary for the support home.
class ExantasAccountSummary extends StatelessWidget {
  const ExantasAccountSummary({
    super.key,
    required this.name,
    required this.nativeReady,
    required this.sourceId,
    required this.onAccount,
    required this.onCopyId,
  });

  final String name;
  final bool nativeReady;
  final String sourceId;
  final VoidCallback onAccount;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSourceId = sourceId.trim().isNotEmpty;
    return Card(
        child: InkWell(
            onTap: onAccount,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(Icons.support_agent,
                              color: colors.primary, size: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name.isEmpty ? 'Λογαριασμός Office' : name,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                                nativeReady
                                    ? 'RustDesk: έτοιμο'
                                    : 'Εκκρεμεί επιβεβαίωση RustDesk',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: nativeReady
                                            ? colors.primary
                                            : colors.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            SelectableText(
                                hasSourceId
                                    ? 'Το ID μου: $sourceId'
                                    : 'Το RustDesk ID ετοιμάζεται…',
                                style: Theme.of(context).textTheme.bodyMedium),
                          ])),
                      IconButton(
                          key: const ValueKey('support-copy-id'),
                          tooltip: 'Αντιγραφή RustDesk ID',
                          onPressed: hasSourceId ? onCopyId : null,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: const Icon(Icons.copy)),
                    ]))));
  }
}

/// Manual RustDesk ID entry. Connection policy stays in [onConnect].
class ExantasQuickConnect extends StatelessWidget {
  const ExantasQuickConnect({
    super.key,
    required this.controller,
    required this.busy,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect;

  void connect(BuildContext context) {
    FocusScope.of(context).unfocus();
    onConnect();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('support-connect-field'),
              controller: controller,
              enabled: !busy,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Σύνδεση με ID',
                prefixIcon: Icon(Icons.computer),
                border: OutlineInputBorder(),
              ),
              onSubmitted: busy ? null : (_) => connect(context),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('support-connect-button'),
                onPressed: busy ? null : () => connect(context),
                icon: const Icon(Icons.link),
                label: const Text('Σύνδεση'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Η σύνδεση δεν αντιστοιχίζεται αυτόματα σε εργασία.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class ExantasRecentDevice {
  const ExantasRecentDevice({
    required this.id,
    required this.label,
    required this.platform,
    required this.online,
  });

  final String id;
  final String label;
  final String platform;
  final bool online;
}

/// RustDesk recent peers displayed as compact, tappable Material list tiles.
class ExantasRecentDevices extends StatelessWidget {
  const ExantasRecentDevices({
    super.key,
    required this.devices,
    required this.busy,
    required this.onConnect,
  });

  final List<ExantasRecentDevice> devices;
  final bool busy;
  final ValueChanged<String> onConnect;

  IconData _platformIcon(String platform) {
    final value = platform.toLowerCase();
    if (value.contains('android')) return Icons.phone_android;
    if (value.contains('windows')) return Icons.desktop_windows;
    if (value.contains('mac') || value.contains('ios')) {
      return Icons.laptop_mac;
    }
    if (value.contains('linux')) return Icons.computer;
    return Icons.devices_other;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Πρόσφατες συνδέσεις',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text('Δεν υπάρχουν πρόσφατες συνδέσεις.'),
              )
            else
              for (final device in devices)
                ListTile(
                  key: ValueKey('recent-${device.id}'),
                  minVerticalPadding: 8,
                  enabled: !busy,
                  leading: Icon(
                    _platformIcon(device.platform),
                    color: colors.primary,
                  ),
                  title: Text(
                    device.label.isEmpty ? device.id : device.label,
                    maxLines: device.label.isEmpty ? null : 1,
                    overflow:
                        device.label.isEmpty ? null : TextOverflow.ellipsis,
                  ),
                  subtitle: device.label.isEmpty
                      ? null
                      : Text(device.id, softWrap: true),
                  trailing: Icon(
                    device.online ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: device.online
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    semanticLabel: device.online
                        ? 'Διαθέσιμος'
                        : 'Η διαθεσιμότητα δεν έχει επιβεβαιωθεί',
                  ),
                  onTap: busy ? null : () => onConnect(device.id),
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child:
                  Text('Η σύνδεση απαιτεί τρέχουσα επιβεβαίωση από το Office.'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout only: current Office authority, requests and session decisions stay in
/// the support page/controller. Recent peers are supplied by RustDesk's model.
class ExantasSupportHome extends StatefulWidget {
  const ExantasSupportHome(
      {super.key,
      required this.account,
      required this.signedIn,
      required this.nativeReady,
      required this.busy,
      required this.controller,
      required this.devices,
      required this.customerPanel,
      required this.pendingPanel,
      required this.pendingCount,
      required this.onConnect,
      required this.onRefresh,
      required this.onConfirmNative,
      this.error});
  final Widget account, customerPanel, pendingPanel;
  final bool signedIn, nativeReady, busy;
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
    final colors = Theme.of(context).colorScheme;
    return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          widget.account,
          if (widget.busy)
            const Padding(
                padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          if (widget.error != null)
            Card(
                color: colors.errorContainer,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(widget.error!,
                        style: TextStyle(color: colors.onErrorContainer)))),
          if (widget.signedIn) ...[
            if (!widget.nativeReady)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'Επιβεβαιώστε τη σύνδεση RustDesk πριν ξεκινήσετε υποστήριξη.'),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                                onPressed:
                                    widget.busy ? null : widget.onConfirmNative,
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text('Επιβεβαίωση σύνδεσης')),
                          ]))),
            ExantasQuickConnect(
                controller: widget.controller,
                busy: widget.busy,
                onConnect: () => widget.onConnect(widget.controller.text)),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Row(children: [
                  for (final item in [
                    ('recent', Icons.history, 'Πρόσφατα'),
                    ('customers', Icons.business_outlined, 'Πελάτες'),
                    ('pending', Icons.pending_actions_outlined, 'Εκκρεμή')
                  ])
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Semantics(
                                selected: section == item.$1,
                                label: item.$1 == 'pending'
                                    ? 'Εκκρεμή (${widget.pendingCount})'
                                    : item.$3,
                                child: TextButton(
                                    key: ValueKey('support-tab-${item.$1}'),
                                    onPressed: () =>
                                        setState(() => section = item.$1),
                                    style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 64),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 8),
                                        backgroundColor: section == item.$1
                                            ? colors.primaryContainer
                                            : null,
                                        foregroundColor: section == item.$1
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12))),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Badge.count(
                                              count: widget.pendingCount,
                                              isLabelVisible:
                                                  item.$1 == 'pending' &&
                                                      widget.pendingCount > 0,
                                              child: Icon(item.$2, size: 22)),
                                          const SizedBox(height: 4),
                                          Text(item.$3,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        ]))))),
                  IconButton(
                      tooltip: 'Ανανέωση',
                      onPressed: widget.busy ? null : widget.onRefresh,
                      icon: const Icon(Icons.refresh)),
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
        ]);
  }
}
