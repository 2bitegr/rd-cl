import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'ex_sheet.dart';
import 'exantas_strings.dart';
import 'exantas_theme.dart';

/// One action of the floating session toolbar.
@immutable
class ExSessionAction {
  const ExSessionAction(
      {required this.id,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.danger = false});
  final String id, label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
}

/// Compact floating pill that lays out [actions] in a row. It scrolls
/// horizontally when the width cannot hold every 48dp target, so no action is
/// ever dropped. Respects safe-area insets on the sides and bottom.
class ExSessionToolbar extends StatelessWidget {
  const ExSessionToolbar({super.key, required this.actions});
  final List<ExSessionAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ExantasTokens.space2,
            ExantasTokens.space1, ExantasTokens.space2, ExantasTokens.space2),
        child: Center(
          child: Semantics(
            container: true,
            label: ExStrings.sessionToolbar,
            child: DecoratedBox(
              key: const ValueKey('ex-session-toolbar'),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(ExantasTokens.radiusPill),
                border: Border.all(color: t.border),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x29000000),
                      blurRadius: 12,
                      offset: Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ExantasTokens.radiusPill),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: ExantasTokens.space1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final a in actions)
                      Tooltip(
                        message: a.label,
                        child: Semantics(
                          button: true,
                          label: a.label,
                          excludeSemantics: true,
                          enabled: a.onPressed != null,
                          onTap: a.onPressed,
                          child: IconButton(
                            key: ValueKey('ex-session-action-${a.id}'),
                            constraints: const BoxConstraints(
                                minWidth: ExantasTokens.minTouch,
                                minHeight: ExantasTokens.minTouch),
                            color: a.danger ? t.danger : t.text,
                            disabledColor: t.textSecondary,
                            icon: Icon(a.icon),
                            onPressed: a.onPressed,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hook for the optional session context chip ("Πελάτης · Υπολογιστής").
/// Set [ExSessionContext.label] (or pass a listenable to the page) from the
/// code that knows the Office customer/machine. Null or empty hides the chip.
class ExSessionContext {
  ExSessionContext._();
  static final ValueNotifier<String?> label = ValueNotifier<String?>(null);

  static String format(String customer, String machine) =>
      '$customer · $machine';

  /// «Πελάτης · Υπολογιστής» from a fresh Office work context
  /// (GET /support-workflow/items/{id}); only call for an explicitly bound
  /// work. Falls back to the device alone when Office supplied no customer.
  static String fromWorkContext(Map<String, dynamic> context, String peer) {
    String? text(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    final item = context['item'];
    final cust = context['customer'];
    final customer = text(item is Map ? item['customer_name'] : null) ??
        text(cust is Map ? cust['company_name'] : null);
    String? device;
    for (final d in (context['devices'] as List? ?? const []).whereType<Map>()) {
      if (d['peer_id'] == peer) device = text(d['label']);
    }
    device ??= peer;
    return customer == null ? device : format(customer, device);
  }
}

class ExSessionContextChip extends StatelessWidget {
  const ExSessionContextChip({super.key, required this.listenable});
  final ValueListenable<String?> listenable;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return ValueListenableBuilder<String?>(
      valueListenable: listenable,
      builder: (ctx, value, _) {
        if (value == null || value.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: Container(
            key: const ValueKey('ex-session-chip'),
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(
                horizontal: ExantasTokens.space3, vertical: 6),
            decoration: BoxDecoration(
                color: t.surface.withOpacity(0.92),
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(ExantasTokens.radiusPill)),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }
}

/// Asks "Αποσύνδεση από <peer>;". Returns true only for explicit Αποσύνδεση;
/// dismissing or tapping Παραμονή (the default) returns false.
Future<bool> showExDisconnectSheet(BuildContext context, String peer) async {
  // Back guard and toolbar/close buttons share this entry point: never stack
  // a second sheet on top of one that is already open.
  if (_disconnectSheetOpen) return false;
  _disconnectSheetOpen = true;
  try {
    final r = await showExSheet<bool>(
        context: context,
        builder: (ctx) => ExDisconnectContent(peer: peer));
    return r == true;
  } finally {
    _disconnectSheetOpen = false;
  }
}

bool _disconnectSheetOpen = false;

class ExDisconnectContent extends StatelessWidget {
  const ExDisconnectContent({super.key, required this.peer});
  final String peer;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ExStrings.disconnectTitle(peer),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: t.text, fontWeight: FontWeight.w700)),
          const SizedBox(height: ExantasTokens.space2),
          Text(ExStrings.disconnectMessage,
              style: TextStyle(color: t.textSecondary)),
          const SizedBox(height: ExantasTokens.space4),
          FilledButton(
              key: const ValueKey('ex-disconnect-stay'),
              autofocus: true,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(ExantasTokens.minTouch)),
              onPressed: () => Navigator.pop(context, false),
              child: const Text(ExStrings.stay)),
          const SizedBox(height: ExantasTokens.space2),
          OutlinedButton(
              key: const ValueKey('ex-disconnect-confirm'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: t.danger,
                  side: BorderSide(color: t.danger),
                  minimumSize: const Size.fromHeight(ExantasTokens.minTouch)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(ExStrings.disconnect)),
        ]);
  }
}

/// Intercepts system Back: never pops directly, asks first. [onDisconnect]
/// runs only after explicit confirmation.
class ExSessionBackGuard extends StatelessWidget {
  const ExSessionBackGuard(
      {super.key,
      required this.peer,
      required this.onDisconnect,
      required this.child});
  final String peer;
  final VoidCallback onDisconnect;
  final Widget child;

  Future<void> requestDisconnect(BuildContext context) async {
    if (await showExDisconnectSheet(context, peer)) onDisconnect();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) requestDisconnect(context);
      },
      // Remote/terminal canvases rely on fixed sizes: keep system text scale
      // at 1.0 inside a session; every other mobile page honours up to 1.3.
      child: ExFixedTextScale(child: child));
}

/// Pins the text scale to 1.0 for the subtree (session canvases only).
class ExFixedTextScale extends StatelessWidget {
  const ExFixedTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child);
}
