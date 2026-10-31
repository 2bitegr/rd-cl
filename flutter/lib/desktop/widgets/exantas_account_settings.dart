import 'dart:async';
import 'package:flutter/material.dart';

class ExantasAccountStatus {
  const ExantasAccountStatus({
    required this.signedIn,
    required this.name,
    required this.role,
    required this.nativeReady,
    required this.legacySignedIn,
    this.nativeRecoveryRequired,
  });

  final bool signedIn;
  final String name;
  final String role;
  final bool nativeReady;
  final bool legacySignedIn;
  // Android distinguishes an ambiguous issuance from ordinary lease expiry.
  // Unspecified preserves the existing Windows account presentation.
  final bool? nativeRecoveryRequired;
  bool get needsNativeRetry => nativeRecoveryRequired ?? !nativeReady;
}

/// One Office sign-in surface. Native authentication remains service-owned.
class ExantasAccountSettings extends StatefulWidget {
  const ExantasAccountSettings({super.key,
    required this.loadStatus,
    required this.login,
    required this.logout,
    required this.confirmNative,
    required this.logoutLegacy,
    required this.nativeRequired,
  });

  final Future<ExantasAccountStatus> Function() loadStatus;
  final Future<void> Function(String, String) login;
  final Future<void> Function() logout;
  final Future<void> Function() confirmNative;
  final Future<void> Function() logoutLegacy;
  final bool nativeRequired;

  @override
  State<ExantasAccountSettings> createState() => _ExantasAccountSettingsState();
}

class _ExantasAccountSettingsState extends State<ExantasAccountSettings> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  ExantasAccountStatus? _status;
  String? _error;
  bool _busy = false;
  Future<void>? _refreshPending;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    if (!mounted) return Future.value();
    return _refreshPending ??= _load().whenComplete(() => _refreshPending = null);
  }

  Future<void> _load() async {
    final recovering = _status == null;
    try {
      final status = await widget.loadStatus();
      if (mounted) setState(() {
        _status = status;
        if (recovering) _error = null;
      });
    } catch (_) {
      // Do not allow sign-in while the local identity state is unknown.
      if (mounted) setState(() {
        _status = null;
        _error = 'Δεν ήταν δυνατός ο έλεγχος του λογαριασμού. Δοκιμάστε ξανά.';
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _refreshPending;
      if (!mounted) return;
      if (_status == null) {
        throw StateError('Δεν επιβεβαιώθηκε η τοπική κατάσταση του λογαριασμού.');
      }
      await action();
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');
      });
    } finally {
      if (mounted) _password.clear();
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = !_busy && status != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Exantas Office'),
        const SizedBox(height: 8),
        const Text('Συνδεθείτε με τον λογαριασμό Office. '
            'Η πρόσβαση απομακρυσμένης υποστήριξης ελέγχεται από τα δικαιώματά σας.'),
        if ((status == null && _error == null) || _busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (status?.legacySignedIn == true) ...[
          const SizedBox(height: 12),
          const Text('Υπάρχει ξεχωριστή σύνδεση RustDesk σε αυτόν τον υπολογιστή. '
              'Αποσυνδεθείτε πρώτα για να συνεχίσετε με το Office. '
              'Ο χρήστης και το ID δεν διαγράφονται.'),
          OutlinedButton(
            onPressed: enabled ? () => _run(widget.logoutLegacy) : null,
            child: const Text('Αποσύνδεση παλιού λογαριασμού RustDesk'),
          ),
        ] else if (status?.signedIn == true) ...[
          const SizedBox(height: 12),
          Text(status!.name),
          Text(status.role == 'technician' ? 'Τεχνικός υποστήριξης'
              : status.role == 'admin' ? 'Διαχειριστής' : 'Χρήστης Office'),
          if (widget.nativeRequired)
            Text(status.nativeReady ? 'RustDesk: έτοιμο για σύνδεση'
                : status.nativeRecoveryRequired == false
                    ? 'RustDesk: αυτόματη ανανέωση κατά τη σύνδεση'
                    : 'RustDesk: η σύνδεση δεν έχει επιβεβαιωθεί'),
          if (widget.nativeRequired && status.needsNativeRetry)
            OutlinedButton(
              onPressed: enabled ? () => _run(widget.confirmNative) : null,
              child: Text(status.nativeRecoveryRequired == true
                  ? 'Επανάληψη σύνδεσης RustDesk' : 'Επιβεβαίωση σύνδεσης'),
            ),
          OutlinedButton(
            onPressed: enabled ? () => _run(widget.logout) : null,
            child: const Text('Αποσύνδεση από το Office'),
          ),
        ] else if (status != null) ...[
          TextField(
            controller: _email,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email Office'),
          ),
          TextField(
            controller: _password,
            enabled: enabled,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Κωδικός Office'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: enabled ? () => _run(() async {
              if (_email.text.trim().isEmpty || _password.text.isEmpty) {
                throw StateError('Συμπληρώστε email και κωδικό Office.');
              }
              await widget.login(_email.text, _password.text);
            }) : null,
            child: const Text('Σύνδεση'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, semanticsLabel: 'Σφάλμα: $_error'),
          if (status == null)
            TextButton(onPressed: _busy ? null : _refresh,
                child: const Text('Επανάληψη ελέγχου')),
        ],
      ],
    );
  }
}
