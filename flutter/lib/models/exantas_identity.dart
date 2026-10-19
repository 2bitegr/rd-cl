class ExantasIdentityAccess {
  const ExantasIdentityAccess(
      {required this.apiBase,
      required this.officeUserId,
      required this.companionToken,
      required this.currentId});
  final String apiBase;
  final String officeUserId;
  final String companionToken;
  final String currentId;
}

class ExantasIdentityResult {
  const ExantasIdentityResult(
      {required this.success,
      required this.code,
      required this.officeSignedOut,
      this.newId = '',
      this.backupPath = ''});
  final bool success;
  final String code;
  final bool officeSignedOut;
  final String newId;
  final String backupPath;

  String get message {
    switch (code) {
      case 'id_generated':
        return 'Το νέο ID δημιουργήθηκε. Περιμένετε την ένδειξη «Έτοιμο» και συνδεθείτε ξανά στο Office. Το ιστορικό και οι αντιστοιχίσεις πελατών δεν αλλάζουν αυτόματα.';
      case 'operation_in_progress':
        return 'Υπάρχει ήδη αλλαγή ID σε εξέλιξη. Περιμένετε την ολοκλήρωσή της, χωρίς νέα προσπάθεια.';
      case 'local_report_check_failed':
        return 'Δεν ήταν δυνατός ο έλεγχος των τοπικών αναφορών. Το ID δεν άλλαξε. Ελέγξτε τις «Συνεδρίες υποστήριξης».';
      case 'pending_reports':
        return 'Υπάρχουν εκκρεμείς τοπικές αναφορές. Ελέγξτε τις «Συνεδρίες υποστήριξης» πριν αλλάξετε το ID.';
      case 'active_sessions':
        return 'Κλείστε τις ενεργές απομακρυσμένες συνδέσεις πριν αλλάξετε το ID.';
      case 'office_login_required':
        return 'Απαιτείται ενεργή σύνδεση τεχνικού στο Office. Συνδεθείτε ξανά.';
      case 'office_unavailable':
        return 'Δεν ήταν δυνατή η επιβεβαίωση του τεχνικού στο Office. Το ID δεν άλλαξε.';
      case 'id_changed':
        return 'Το ID άλλαξε όσο ήταν ανοικτή η επιβεβαίωση. Ελέγξτε το τρέχον ID.';
      case 'installed_service_required':
        return 'Απαιτείται η εγκατεστημένη εφαρμογή και η υπηρεσία του rd-cl στην ίδια έκδοση.';
      case 'logout_unconfirmed':
      case 'result_unconfirmed':
        return 'Το αποτέλεσμα δεν επιβεβαιώθηκε. Μην επαναλάβετε την ενέργεια. Ελέγξτε το ID στην αρχική οθόνη και συνδεθείτε ξανά στο Office.';
      case 'config_write_failed':
        return 'Η αποθήκευση του νέου ID απέτυχε. Χρειάζεται έλεγχος των ρυθμίσεων και νέα σύνδεση στο Office πριν από άλλη προσπάθεια.';
      default:
        return 'Η αλλαγή δεν ολοκληρώθηκε. Ελέγξτε το ID και τη σύνδεση Office πριν από νέα προσπάθεια.';
    }
  }
}

abstract class ExantasIdentityActions {
  Future<ExantasIdentityAccess?> authorizeIdentityReset();
  Future<bool> identitySessionMatches(ExantasIdentityAccess access);
  Future<ExantasIdentityResult> regenerateIdentity(
      ExantasIdentityAccess access);
}
