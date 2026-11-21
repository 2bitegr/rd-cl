import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'exantas_strings.dart';
import 'exantas_theme.dart';

/// Outcome of one authentication attempt.
enum ExAuthResult {
  /// The user proved presence (biometric or device credential).
  success,

  /// Cancelled or not recognised: stay locked and offer a retry.
  failed,

  /// Too many attempts: stay locked, ask to wait.
  lockedOut,

  /// The device has no biometric/screen lock to ask for: nothing to gate with,
  /// so the gate opens instead of locking the user out of their own app.
  unavailable,
}

/// Pure app-lock state machine. It gates the UI only; it never touches Office
/// tokens, the outbox or any native service. Platform pieces (settings,
/// authentication, clock) are injected so it is unit-testable.
class ExAppLockController with WidgetsBindingObserver {
  ExAppLockController({
    required this.isEnabled,
    required this.authenticate,
    DateTime Function()? now,
    this.timeout = const Duration(minutes: 5),
  })  : _now = now ?? DateTime.now,
        locked = ValueNotifier<bool>(isEnabled());

  final bool Function() isEnabled;
  final Future<ExAuthResult> Function() authenticate;
  final Duration timeout;
  final DateTime Function() _now;

  /// True while the lock screen must cover the app. Starts true on a cold
  /// start when the feature is enabled so no content flashes before the prompt.
  final ValueNotifier<bool> locked;

  /// Last failure to explain on the lock screen, or null.
  final ValueNotifier<ExAuthResult?> lastFailure =
      ValueNotifier<ExAuthResult?>(null);

  bool _busy = false;
  DateTime? _backgroundedAt;

  bool get busy => _busy;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  /// Cold start: ask once if enabled.
  Future<void> start() async {
    if (!isEnabled()) {
      locked.value = false;
      return;
    }
    locked.value = true;
    await unlock();
  }

  /// Runs one prompt. Re-entrant calls while a prompt is up are ignored.
  Future<void> unlock() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await authenticate();
      if (r == ExAuthResult.success || r == ExAuthResult.unavailable) {
        lastFailure.value = null;
        locked.value = false;
      } else {
        lastFailure.value = r;
        locked.value = true;
      }
    } catch (_) {
      lastFailure.value = ExAuthResult.failed;
      locked.value = true;
    } finally {
      _busy = false;
      // The system prompt itself pauses/resumes the app; start timing fresh.
      _backgroundedAt = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy) return;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundedAt ??= _now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            isEnabled() &&
            !locked.value &&
            _now().difference(since) >= timeout) {
          locked.value = true;
          unlock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// While locked, system Back is consumed so it cannot navigate the covered
  /// app (for example into a session's disconnect sheet).
  @override
  Future<bool> didPopRoute() async => locked.value;
}

/// Covers [child] with the lock screen while [controller.locked] is true. The
/// child stays mounted (sessions and timers keep running) but is inert and
/// hidden from accessibility services.
class ExAppLockGate extends StatefulWidget {
  const ExAppLockGate(
      {super.key, required this.controller, required this.child});
  final ExAppLockController controller;
  final Widget child;

  @override
  State<ExAppLockGate> createState() => _ExAppLockGateState();
}

class _ExAppLockGateState extends State<ExAppLockGate> {
  @override
  void initState() {
    super.initState();
    // The prompt needs a resumed activity: start after the first frame.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.controller.start());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: widget.controller.locked,
      builder: (context, locked, child) => Stack(
              fit: StackFit.expand,
              textDirection: TextDirection.ltr,
              children: [
                ExcludeSemantics(
                    excluding: locked,
                    child: IgnorePointer(ignoring: locked, child: child)),
                if (locked)
                  Positioned.fill(
                      child: ExLockScreen(controller: widget.controller)),
              ]),
      child: widget.child);
}

class ExLockScreen extends StatelessWidget {
  const ExLockScreen({super.key, required this.controller});
  final ExAppLockController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Material(
      key: const ValueKey('ex-lock-screen'),
      color: t.surfaceAlt,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ExantasTokens.space6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                        child: Icon(Icons.lock_outline,
                            size: 56, color: t.accent)),
                    const SizedBox(height: ExantasTokens.space4),
                    Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(ExStrings.lockedTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    color: t.text,
                                    fontWeight: FontWeight.w700))),
                    const SizedBox(height: ExantasTokens.space2),
                    ValueListenableBuilder<ExAuthResult?>(
                        valueListenable: controller.lastFailure,
                        builder: (_, f, __) => Semantics(
                            liveRegion: true,
                            child: Text(
                                f == ExAuthResult.lockedOut
                                    ? ExStrings.unlockLockedOut
                                    : f == null
                                        ? ExStrings.lockedHint
                                        : ExStrings.unlockFailed,
                                key: const ValueKey('ex-lock-message'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: f == null
                                        ? t.textSecondary
                                        : t.danger)))),
                    const SizedBox(height: ExantasTokens.space6),
                    FilledButton.icon(
                        key: const ValueKey('ex-lock-retry'),
                        style: FilledButton.styleFrom(
                            minimumSize:
                                const Size.fromHeight(ExantasTokens.minTouch)),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text(ExStrings.unlock),
                        onPressed: controller.unlock),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}
