/// Greek UI strings for the Exantas mobile surfaces (new or changed text).
class ExStrings {
  static const navHome = 'Αρχική';
  static const navWork = 'Εργασίες';
  static const navShare = 'Κοινή χρήση';
  static const navSettings = 'Ρυθμίσεις';
  static const chat = 'Κουβέντα';
  static const back = 'Πίσω';

  static const newConnection = 'Νέα σύνδεση';
  static const connect = 'Σύνδεση';
  static const remoteIdLabel = 'RustDesk ID υπολογιστή';
  static const remoteIdHint = 'Πληκτρολόγησε το ID';
  static const searchCustomer = 'Αναζήτηση πελάτη';
  static const customers = 'Πελάτες';
  static const today = 'Σήμερα';
  static const openWork = 'Ανοιχτές';
  static const pending = 'Εκκρεμή';
  static const pendingDecisions = 'Εκκρεμείς αποφάσεις';
  static const recent = 'Πρόσφατοι υπολογιστές';
  static const allRecent = 'Όλοι οι πρόσφατοι';
  static const fewerRecent = 'Λιγότεροι υπολογιστές';
  static const noRecent = 'Δεν υπάρχουν πρόσφατες συνδέσεις.';
  static const noRecentHint =
      'Οι υπολογιστές σου θα εμφανίζονται εδώ μετά τη σύνδεση.';
  static const customersAndWork = 'Πελάτες και εργασίες';
  static const refresh = 'Ανανέωση';
  static const available = 'Διαθέσιμος';
  static const availabilityUnconfirmed = 'Μη επιβεβαιωμένη διαθεσιμότητα';
  static const signInForWork = 'Συνδέσου στο Office για να δεις εργασίες.';
  static const offline = 'Χωρίς σύνδεση στο διαδίκτυο';
  static const cancel = 'Άκυρο';
  static const confirm = 'Επιβεβαίωση';

  static String pendingCount(int n) => 'Εκκρεμή ($n)';
  static String pendingHint(int n) => n == 0
      ? 'Δεν υπάρχουν εκκρεμείς αποφάσεις συνεδριών.'
      : 'Συνεδρίες που περιμένουν απόφαση ή αντιστοίχιση.';
  static String allRecentCount(int n) => 'Όλοι οι πρόσφατοι ($n)';
}
