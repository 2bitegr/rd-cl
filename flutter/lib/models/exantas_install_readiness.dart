import 'dart:async';
import 'dart:convert';
import 'dart:io';

class InstallReadinessCheck {
  const InstallReadinessCheck(this.code, this.status, this.action);
  final String code, status;
  final String? action;
}

class InstallReadinessReport {
  InstallReadinessReport(this.checks, this.checkedAt, this.fingerprint,
      this.officeState, this.officeReasons, this.targetVersion, this.installedVersion, this.repairTarget);
  final List<InstallReadinessCheck> checks;
  final DateTime checkedAt;
  final String? fingerprint, targetVersion, installedVersion, repairTarget;
  final String officeState;
  final List<String> officeReasons;

  factory InstallReadinessReport.decode(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map || raw['schema'] != 1 || raw['checks'] is! List ||
        (raw['checks'] as List).isEmpty) {
      throw const FormatException('readiness_unconfirmed');
    }
    const states = {'ok', 'blocked', 'pending', 'unsupported', 'unknown'};
    const actions = {'windows_update', 'start_service', 'automatic_service'};
    final checks = (raw['checks'] as List).map((entry) {
      if (entry is! Map || entry['code'] is! String ||
          !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(entry['code']) ||
          !states.contains(entry['status'])) {
        throw const FormatException('readiness_unconfirmed');
      }
      return InstallReadinessCheck(entry['code'], entry['status'],
          actions.contains(entry['action']) ? entry['action'] as String : null);
    }).toList(growable: false);
    final at = DateTime.tryParse('${raw['checked_at']}');
    if (at == null || DateTime.now().difference(at).inSeconds > 120 ||
        at.difference(DateTime.now()).inSeconds > 60) {
      throw const FormatException('readiness_stale');
    }
    final office = raw['office'];
    final officeValid = office is Map && office['schema'] == 1 &&
        {'ready', 'waiting', 'blocked', 'unknown'}.contains(office['state']);
    final officeTime = officeValid ? DateTime.tryParse('${office['checked_at']}') : null;
    final clockValid = officeTime != null && DateTime.now().difference(officeTime).inSeconds <= 120 &&
        officeTime.difference(DateTime.now()).inSeconds <= 60;
    final reasonsValid = officeValid && office['reasons'] is List && (office['reasons'] as List).length <= 64 &&
        (office['reasons'] as List).every((s) => s is String && RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(s));
    final reasons = reasonsValid
        ? (office['reasons'] as List).whereType<String>().where((s) => RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(s)).toList()
        : ['office_unconfirmed'];
    if (officeValid && office['state'] == 'ready' && !clockValid) reasons.add('clock_unconfirmed');
    String? version(dynamic value) => value is String &&
        RegExp(r'^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$').hasMatch(value) ? value : null;
    final fingerprint = raw['repair_fingerprint'];
    return InstallReadinessReport(checks, at,
        fingerprint is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ? fingerprint : null,
        officeValid && reasonsValid && (office['state'] != 'ready' || clockValid) ? office['state'] : 'unknown',
        reasons,
        officeValid ? version(office['target_version']) : null,
        version(raw['installed_version']), raw['repair_target'] is String && (raw['repair_target'] as String).length < 1024 ? raw['repair_target'] as String : null);
  }

  bool get unsupported => checks.any((c) => c.status == 'unsupported');
  bool get ready => checks.every((c) => c.status == 'ok') && officeState == 'ready' &&
      officeReasons.isEmpty && installedVersion != null && targetVersion != null &&
      const {'windows_x64', 'exe_installation', 'minimum_space', 'restart_clear',
        'installation_protected', 'service_running', 'service_automatic', 'runtime_idle', 'runtime_identity', 'runtime_installation'}
          .every((code) => checks.any((check) => check.code == code && check.status == 'ok'));
  bool get hasLocalBlockers => checks.any((c) => c.status == 'blocked');
}

typedef InstallReadinessRunner = Future<String> Function(List<String> arguments);

/// Executes only the bundled native helper. No shell, credentials or downloaded scripts.
class InstallReadinessClient {
  InstallReadinessClient({InstallReadinessRunner? runner}) : _runner = runner ?? _native;
  final InstallReadinessRunner _runner;

  Future<InstallReadinessReport> check(String target) async =>
      InstallReadinessReport.decode(await _runner(['--office-install-readiness', target]));

  Future<void> repair(String action, String fingerprint) async {
    if (!{'start_service', 'automatic_service'}.contains(action) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw ArgumentError('invalid_repair');
    }
    final reply = jsonDecode(await _runner(['--office-install-repair', action, fingerprint]));
    if (reply is! Map || reply['schema'] != 1 || reply['applied'] != true) {
      throw const FormatException('repair_unconfirmed');
    }
  }

  static Future<String> _native(List<String> arguments) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows installer only');
    final process = await Process.start(Platform.resolvedExecutable, arguments,
        runInShell: false, mode: ProcessStartMode.normal);
    await process.stdin.close();
    var count = 0;
    Future<List<int>> read(Stream<List<int>> stream) async {
      final bytes = <int>[];
      await for (final chunk in stream) {
        count += chunk.length;
        if (count > 65536) { process.kill(); throw const FormatException('readiness_output_too_large'); }
        bytes.addAll(chunk);
      }
      return bytes;
    }
    try {
      final values = await Future.wait<dynamic>([
        read(process.stdout), read(process.stderr), process.exitCode,
      ]).timeout(const Duration(seconds: 75));
      if (values[2] != 0) throw const FormatException('readiness_unconfirmed');
      return utf8.decode(values[0] as List<int>).trim();
    } catch (_) {
      process.kill();
      rethrow;
    }
  }
}

const installReadinessLabels = <String, String>{
  'windows_x64': 'Συμβατά Windows x64',
  'exe_installation': 'Εγκατάσταση EXE — η διαχείριση MSI παραμένει ξεχωριστή',
  'installation_mode_unconfirmed': 'Δεν επιβεβαιώθηκε ο τύπος της εγκατάστασης',
  'minimum_space': 'Τουλάχιστον 1 GB διαθέσιμο — κάθε ενημέρωση επανελέγχει τον απαιτούμενο χώρο',
  'space_unconfirmed': 'Δεν επιβεβαιώθηκε ο διαθέσιμος τοπικός χώρος',
  'windows_servicing_restart': 'Η συντήρηση Windows ζητά επανεκκίνηση',
  'windows_update_restart': 'Το Windows Update ζητά επανεκκίνηση',
  'pending_file_operations': 'Υπάρχουν εκκρεμείς ενέργειες αρχείων. Απαιτείται διάγνωση· δεν αφαιρούνται αυτόματα',
  'restart_clear': 'Δεν εντοπίστηκε εκκρεμής επανεκκίνηση',
  'restart_unconfirmed': 'Δεν επιβεβαιώθηκε η κατάσταση επανεκκίνησης',
  'service_missing': 'Δεν βρέθηκε η υπηρεσία rd-cl — απαιτείται εγκατάσταση/επιδιόρθωση',
  'service_running': 'Η υπηρεσία rd-cl λειτουργεί',
  'service_stopped': 'Η υπηρεσία rd-cl είναι σταματημένη',
  'service_automatic': 'Η υπηρεσία ξεκινά αυτόματα με τα Windows',
  'service_not_automatic': 'Η υπηρεσία δεν έχει αυτόματη εκκίνηση',
  'service_configuration_changed': 'Η διαδρομή ή ο λογαριασμός υπηρεσίας χρειάζεται έλεγχο',
  'service_transitioning': 'Η υπηρεσία ξεκινά ή σταματά — επαναλάβετε τον έλεγχο',
  'service_after_install': 'Η υπηρεσία θα ελεγχθεί μετά την εγκατάσταση',
  'service_unconfirmed': 'Δεν επιβεβαιώθηκε η υπηρεσία',
  'installation_protected': 'Επιβεβαιώθηκαν οι προστατευμένες άδειες της εγκατάστασης',
  'installation_protection_unconfirmed': 'Δεν επιβεβαιώθηκαν οι άδειες εγκατάστασης — δεν προσφέρεται αυτόματη επιδιόρθωση',
  'runtime_idle': 'Απουσία ενεργών συνδέσεων κατά τον τελευταίο έλεγχο',
  'runtime_identity': 'Η ταυτότητα του ενεργού rd-cl συμφωνεί με την υπηρεσία',
  'runtime_installation': 'Επιβεβαιώθηκαν ο ενεργός πυρήνας και η εγκατάσταση EXE',
  'runtime_unconfirmed': 'Δεν επιβεβαιώθηκε η κατάσταση συνδέσεων από την υπηρεσία',
  'readiness_unconfirmed': 'Ο έλεγχος δεν ολοκληρώθηκε',
  'office_unconfirmed': 'Δεν επιβεβαιώθηκε η επικοινωνία/ετοιμότητα στο Office',
  'clock_unconfirmed': 'Δεν επιβεβαιώθηκε ο συγχρονισμός ώρας με το Office — ελέγξτε την ημερομηνία και ώρα των Windows',
  'post_install_check_required': 'Απαιτείται έλεγχος μετά την εγκατάσταση και τη σύνδεση στο Office',
  'registration_required': 'Δεν έχει ολοκληρωθεί η εγγραφή ενημερώσεων της συσκευής πελάτη. Η είσοδος τεχνικού δεν δημιουργεί αυτή την εγγραφή',
  'awaiting_worker': 'Αναμονή της πρώτης αναφοράς από τον εγκατεστημένο updater',
  'worker_offline': 'Δεν υπάρχει πρόσφατη αναφορά updater — απαιτείται επανέλεγχος επικοινωνίας',
  'worker_not_ready': 'Ο τελευταίος έλεγχος updater δεν επιβεβαιώνει ετοιμότητα',
  'worker_version_unconfirmed': 'Αναμονή επιβεβαίωσης της εγκατεστημένης έκδοσης από τον updater',
  'pending_restart': 'Ο updater αναφέρει εκκρεμή επανεκκίνηση Windows',
  'device_busy': 'Ο υπολογιστής χρησιμοποιείται — η ενημέρωση περιμένει να ολοκληρωθούν οι συνδέσεις',
  'updater_upgrade_required': 'Ο μηχανισμός ενημερώσεων χρειάζεται αρχική αναβάθμιση',
  'registration_binding_unconfirmed': 'Η εγγραφή updater δεν συμφωνεί με την τρέχουσα συσκευή — χρειάζεται διάγνωση',
  'updater_stopped': 'Υπάρχει αίτημα διακοπής updater — χρειάζεται έλεγχος',
  'updates_disabled': 'Οι αυτόματες ενημερώσεις είναι απενεργοποιημένες στο Office',
  'distribution_disabled': 'Η διανομή είναι απενεργοποιημένη',
  'distribution_paused': 'Η διανομή είναι σε παύση',
  'device_excluded': 'Ο υπολογιστής εξαιρείται από τη διανομή',
  'release_unconfirmed': 'Δεν επιβεβαιώθηκε διαθέσιμη υπογεγραμμένη έκδοση',
  'release_author_unconfirmed': 'Δεν επιβεβαιώθηκε ενεργός υπεύθυνος για τη διαθέσιμη έκδοση στο Office',
  'update_signer_not_pinned': 'Το κλειδί της έκδοσης δεν είναι στα έμπιστα κλειδιά αυτού του υπολογιστή',
  'recovery_pending': 'Εκκρεμεί επιβεβαίωση ανάκαμψης εγκατάστασης',
  'fleet_slot_busy': 'Ενημερώνεται άλλος υπολογιστής',
  'update_in_progress': 'Υπάρχει ήδη ενημέρωση σε εξέλιξη — περιμένετε την ολοκλήρωσή της',
  'pilot_required': 'Δεν έχει οριστεί πιλότος',
  'pilot_pending': 'Αναμονή επιβεβαίωσης και παρακολούθησης πιλότου',
  'outside_maintenance': 'Εκτός επιλεγμένου ωραρίου διανομής',
  'policy_unconfirmed': 'Το πρόγραμμα διανομής χρειάζεται έλεγχο',
  'release_revoked': 'Η διαθέσιμη έκδοση έχει ανακληθεί',
  'attempt_budget_exhausted': 'Εξαντλήθηκαν οι αυτόματες προσπάθειες — χρειάζεται τεχνικός',
};
