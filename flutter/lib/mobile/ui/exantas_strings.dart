/// Greek UI strings for the Exantas mobile surfaces (new or changed text).
class ExStrings {
  static const navHome = 'Αρχική';
  static const navWork = 'Εργασίες';
  static const navShare = 'Κοινή χρήση';
  static const navSettings = 'Ρυθμίσεις';
  static const chat = 'Κουβέντα';
  static const back = 'Πίσω';
  static const chatEmpty = 'Δεν υπάρχουν μηνύματα ακόμη.';
  static const chatEmptyHint =
      'Γράψε ένα μήνυμα για να ξεκινήσεις τη συζήτηση.';

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

  static const copyId = 'Αντιγραφή ID';
  static const copyPassword = 'Αντιγραφή κωδικού';
  static const showPassword = 'Εμφάνιση κωδικού';
  static const hidePassword = 'Απόκρυψη κωδικού';
  static const newPassword = 'Νέος κωδικός μίας χρήσης';
  static const permOn = 'Ενεργό';
  static const permOff = 'Ανενεργό';
  static const incomingConnections = 'Εισερχόμενες συνδέσεις';
  static const noIncoming = 'Δεν υπάρχουν εισερχόμενες συνδέσεις.';
  static const noIncomingHint =
      'Όταν κάποιος συνδεθεί στη συσκευή σου, θα εμφανιστεί εδώ.';

  // Remote session
  static const keyboard = 'Πληκτρολόγιο';
  static const mouseMode = 'Λειτουργία ποντικιού/αφής';
  static const specialKeys = 'Ειδικά πλήκτρα';
  static const screens = 'Οθόνες';
  static const more = 'Περισσότερα';
  static const disconnect = 'Αποσύνδεση';
  static const stay = 'Παραμονή';
  static const hideToolbar = 'Απόκρυψη γραμμής εργαλείων';
  static const showToolbar = 'Εμφάνιση γραμμής εργαλείων';
  static const sessionToolbar = 'Εργαλεία συνεδρίας';
  static const sessionElapsedUnverified = 'Χρόνος σύνδεσης (μη επαληθευμένος)';
  static String disconnectTitle(String peer) => 'Αποσύνδεση από $peer;';
  static const disconnectMessage =
      'Η απομακρυσμένη συνεδρία θα τερματιστεί.';

  // Floating mouse / gestures
  static const mouseExpand = 'Άνοιγμα εικονικού ποντικιού';
  static const mouseCollapse = 'Σύμπτυξη εικονικού ποντικιού';
  static const joystick = 'Εικονικό joystick';
  static const mouseLeftButton = 'Αριστερό κουμπί ποντικιού';
  static const mouseRightButton = 'Δεξί κουμπί ποντικιού';
  static const mouseMiddleButton = 'Μεσαίο κουμπί ποντικιού';
  static const scrollUp = 'Κύλιση πάνω';
  static const scrollDown = 'Κύλιση κάτω';
  static const mouseWheel = 'Τροχός κύλισης';
  static const mouseDragHandle = 'Μετακίνηση ποντικιού';
  static const gestureHelp = 'Βοήθεια χειρονομιών';

  // Biometric unlock
  static const securitySection = 'Ασφάλεια';
  static const biometricUnlock = 'Ξεκλείδωμα με βιομετρικά';
  static const biometricUnlockHint =
      'Ζητά δακτυλικό αποτύπωμα, πρόσωπο ή κλείδωμα συσκευής όταν ανοίγει η '
      'εφαρμογή και μετά από 5 λεπτά στο παρασκήνιο.';
  static const biometricUnsupported =
      'Η συσκευή δεν έχει βιομετρικά ή κλείδωμα οθόνης.';
  static const biometricReason =
      'Επιβεβαιώστε την ταυτότητά σας για να ανοίξει το Exantas Support.';
  static const lockedTitle = 'Η εφαρμογή είναι κλειδωμένη';
  static const lockedHint = 'Ξεκλειδώστε για να συνεχίσετε.';
  static const unlock = 'Ξεκλείδωμα';
  static const unlockFailed = 'Η επαλήθευση δεν ολοκληρώθηκε. Δοκιμάστε ξανά.';
  static const unlockLockedOut =
      'Πολλές αποτυχημένες προσπάθειες. Δοκιμάστε ξανά σε λίγο.';
}
