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
  static const officeLogout = 'Αποσύνδεση από Office';
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
      'Επιβεβαίωσε την ταυτότητά σου για να ανοίξει το Exantas Support.';
  static const lockedTitle = 'Η εφαρμογή είναι κλειδωμένη';
  static const lockedHint = 'Ξεκλείδωσε για να συνεχίσεις.';
  static const unlock = 'Ξεκλείδωμα';
  static const unlockFailed = 'Η επαλήθευση δεν ολοκληρώθηκε. Δοκίμασε ξανά.';
  static const unlockLockedOut =
      'Πολλές αποτυχημένες προσπάθειες. Δοκίμασε ξανά σε λίγο.';
}


/// Greek copy for the technician report (δελτίο τεχνικού). Informal singular
/// imperatives, like the rest of the mobile surfaces.
class FvStrings {
  // Entry points
  static const visitsToday = 'Επισκέψεις σήμερα';
  static const newVisit = 'Νέα επίσκεψη';
  static const newAppointment = 'Νέο ραντεβού';
  static const calendar = 'Ημερολόγιο';
  static const noVisitsToday = 'Δεν έχεις επισκέψεις σήμερα.';
  static const noVisitsTodayHint = 'Με το «Νέα επίσκεψη» ξεκινάς χωρίς ραντεβού.';
  static const noAppointments = 'Δεν έχεις ραντεβού αυτή την ημέρα.';
  static const calendarHint = 'Ραντεβού κλείνουν ο admin και ο τεχνικός. Βλέπεις μόνο τα δικά σου.';
  static const offlineWorking = 'Χωρίς σύνδεση: δείχνονται οι επισκέψεις που έχεις στο κινητό.';
  static const prevWeek = 'Προηγούμενη εβδομάδα';
  static const nextWeek = 'Επόμενη εβδομάδα';
  static const bookAppointment = 'Κλείσε ραντεβού';
  static const appointmentNote = 'Σημείωση (προαιρετικά)';
  static const whenStep = 'Πότε';
  static const openVisit = 'Άνοιγμα';
  static const syncNow = 'Συγχρονισμός τώρα';
  static const dismiss = 'Απόκρυψη';

  // Badges
  static const badgeRejected = 'Δεν έγινε δεκτό';
  static const badgeCancelled = 'Ακυρώθηκε';
  static const badgeUnsynced = 'Δεν έχει συγχρονίσει';
  static const badgeClosed = 'Έκλεισε';
  static const badgeAwaiting = 'Περιμένει συναδέλφους';
  static const badgeClosing = 'Κλείνει';
  static const badgeInProgress = 'Σε εξέλιξη';
  static const badgeScheduled = 'Ραντεβού';
  static const customerPendingApproval = 'Αναμονή έγκρισης πελάτη';
  static String withOthers(String names) => 'Εσύ + $names';

  // Start
  static const customerStep = 'Πελάτης';
  static const jobTypeStep = 'Τύπος εργασίας';
  static const workStep = 'Εργασία (προαιρετικά)';
  static const helpersStep = 'Άλλοι τεχνικοί';
  static const noWork = 'Χωρίς εργασία';
  static const searchCustomer = 'Αναζήτηση πελάτη';
  static const recentCustomers = 'Πρόσφατοι πελάτες';
  static const newCustomer = 'Νέος πελάτης';
  static const change = 'Αλλαγή';
  static const startVisit = 'Ξεκίνα την επίσκεψη';
  static const noJobTypes =
      'Δεν έχουν φορτωθεί οι τύποι εργασίας. Συνδέσου στο διαδίκτυο μία φορά και ξαναδοκίμασε.';
  static const visitMissing = 'Η επίσκεψη δεν βρέθηκε σε αυτή τη συσκευή.';

  // Draft customer
  static const draftCustomerTitle = 'Νέος πελάτης';
  static const draftCustomerHint =
      'Η επίσκεψη προχωρά κανονικά. Ο admin εγκρίνει τον πελάτη αργότερα και μέχρι τότε η χρέωση και το email περιμένουν.';
  static const draftCompany = 'Επωνυμία';
  static const draftAfm = 'ΑΦΜ';
  static const draftPhone = 'Τηλέφωνο';
  static const draftEmail = 'Email';
  static const draftContact = 'Υπεύθυνος επικοινωνίας';
  static const draftAddress = 'Διεύθυνση';
  static const draftNotes = 'Σημειώσεις';
  static const draftContinue = 'Συνέχεια';
  static const draftNameRequired = 'Γράψε την επωνυμία.';
  static const draftEmailInvalid = 'Το email δεν είναι έγκυρο.';

  // Arrival and attendance
  static const visitCard = 'Επίσκεψη';
  static const technicians = 'Τεχνικοί';
  static const you = 'Εσύ';
  static const notArrived = 'Δεν έφτασε';
  static const attendance = 'Παρουσία';
  static const arrive = 'Άφιξη';
  static const pause = 'Παύση';
  static const resume = 'Συνέχεια';
  static const depart = 'Αναχώρηση';
  static const onPause = 'Σε παύση';
  static const noGps = 'Χωρίς GPS';
  static const arrivalHint =
      'Με την άφιξη καταγράφεται η ώρα και η θέση σου εκείνη τη στιγμή. Τη θέση τη βλέπει μόνο ο admin.';
  static const notArrivedHint = 'Πάτα «Άφιξη» όταν φτάσεις στον πελάτη.';
  static const elapsedLabel = 'Χρόνος επίσκεψης';
  static String arrivedAt(String hm) => 'Εκεί από $hm';
  static String thereSince(String hm) => 'Εκεί από $hm';
  static String leftAt(String hm) => 'Έφυγε $hm';
  static String workedMinutes(String t) => 'Χρόνος: $t';
  static String workLine(String title) => 'Εργασία: $title';
  static String scheduledLine(String hm) => 'Ραντεβού στις $hm';

  // Work screen
  static String reportTitle(String customer) => 'Δελτίο · $customer';
  static const jobType = 'Τύπος εργασίας';
  static String checklistTitle(String type) => 'Λίστα ελέγχου · $type';
  static const description = 'Περιγραφή';
  static const descriptionHint = 'Τι έκανες; Το βλέπει ο πελάτης.';
  static const equipmentTitle = 'Εξοπλισμός και φωτογραφίες';
  static String equipmentCounts(int lines, int photos) => '$lines συσκευές · $photos φωτογραφίες';
  static const toSummary = 'Συνέχεια στη σύνοψη';
  static String notLeadHint(String lead) => lead.isEmpty
      ? 'Το δελτίο κλείνει ο υπεύθυνος τεχνικός. Εσύ καταγράφεις μόνο την παρουσία σου.'
      : 'Το δελτίο κλείνει ο $lead. Εσύ καταγράφεις μόνο την παρουσία σου.';

  // Equipment
  static const scan = 'Σάρωση';
  static const scanTitle = 'Σάρωση barcode ή QR';
  static const scanHint = 'Στόχευσε το barcode ή το QR της συσκευής. Η κάμερα ανοίγει μόνο εδώ.';
  static const cameraDenied = 'Δεν υπάρχει άδεια κάμερας.';
  static const cameraDeniedHint = 'Γράψε τον κωδικό με το χέρι ή δώσε άδεια στις ρυθμίσεις.';
  static const typeBarcode = 'Κωδικός barcode';
  static const useCode = 'Χρήση κωδικού';
  static const newEquipment = 'Νέος εξοπλισμός';
  static const equipmentKind = 'Τύπος συσκευής';
  static const equipmentBrand = 'Μάρκα / μοντέλο';
  static const equipmentSerial = 'Σειριακός αριθμός';
  static const equipmentBarcode = 'Barcode';
  static const equipmentNotes = 'Σημειώσεις';
  static const equipmentKindRequired = 'Γράψε τον τύπο της συσκευής.';
  static const saveToRegister = 'Καταχώριση στο μητρώο';
  static const equipmentLines = 'Εξοπλισμός επίσκεψης';
  static const noEquipment = 'Δεν έχεις προσθέσει εξοπλισμό.';
  static const unknownEquipment = 'Άγνωστη συσκευή';
  static const inRegisterShort = 'Στο μητρώο';
  static const newInRegister = 'Νέο στο μητρώο';
  static String inRegister(String title) => 'Βρέθηκε στο μητρώο: $title';
  static const remove = 'Αφαίρεση';
  static const add = 'Προσθήκη';
  static String equipmentAction(String a) => switch (a) {
        'installed' => 'Εγκαταστάθηκε',
        'serviced' => 'Συντηρήθηκε',
        'removed' => 'Αφαιρέθηκε',
        _ => 'Υπάρχει',
      };
  static const defectiveTitle = 'Παραλαβή ελαττωματικού';
  static const defectiveDescription = 'Τι παρέλαβες';
  static const defectiveCondition = 'Κατάσταση / βλάβη';
  static const defectiveDescriptionRequired = 'Περιέγραψε τι παρέλαβες.';
  static const defectiveSave = 'Καταχώριση παραλαβής';
  static const defectiveStatus = 'Προς επισκευή';
  static const noDefective = 'Καμία παραλαβή. Η παραλαβή μπαίνει ως απόδειξη στο δελτίο.';
  static const photosTitle = 'Φωτογραφίες';
  static const photosInternal = 'Μόνο εσωτερικά. Δεν φτάνουν στον πελάτη.';
  static String photoState(String s) => s == 'ready' ? 'Φωτογραφία αποθηκευμένη' : 'Φωτογραφία σε αναμονή αποστολής';
  static const internalNote = 'Εσωτερική σημείωση';
  static const internalNoteHint = 'Δεν φτάνει ποτέ στον πελάτη.';

  // Summary
  static const summaryTitle = 'Σύνοψη';
  static const timeCard = 'Χρόνος';
  static const total = 'Σύνολο';
  static String pauseSuffix(int minutes) => ", παύση $minutes'";
  static const chargeCard = 'Χρέωση';
  static const previewHint = 'Πάτα «Ενημέρωση εκτίμησης» για να δεις τι υπολογίζει το Office.';
  static const previewNotSynced = 'Η χρέωση υπολογίζεται από το Office μόλις συγχρονίσει το δελτίο.';
  static const previewOffline = 'Χωρίς σύνδεση. Η χρέωση θα υπολογιστεί από το Office μόλις συγχρονίσει.';
  static const previewDisclaimer = 'Εκτίμηση από το Office. Η τελική χρέωση γίνεται όταν κλείσει το δελτίο.';
  static const refreshPreview = 'Ενημέρωση εκτίμησης';
  static const subtotal = 'Αξία πριν την έκπτωση';
  static String discountLine(String pct) => 'Έκπτωση $pct%';
  static const netValue = 'Καθαρή αξία';
  static const chargeFrom = 'Χρέωση από';
  static const sourcePrepaid = 'Υπόλοιπο';
  static const sourceInvoice = 'Τιμολόγηση';
  static const pickChargeSource = 'Διάλεξε από πού γίνεται η χρέωση.';
  static const showPrices = 'Τιμές στον πελάτη';
  static const showPricesHint = 'Το PDF και το portal δείχνουν τα ποσά.';
  static String discountLabel(int pct, int limit) => 'Έκπτωση $pct% (όριο σου $limit%)';
  static const discountNone = 'Έκπτωση 0%';
  static const discountLimitZero = 'Δεν έχεις δικαίωμα έκπτωσης. Το όριο το ορίζει ο admin.';
  static String discountPercent(int pct) => '$pct τοις εκατό';
  static const discountReason = 'Λόγος έκπτωσης (εσωτερικά)';
  static const outcome = 'Αποτέλεσμα';
  static String outcomeLabel(String wire) => switch (wire) {
        'done' => 'Ολοκληρώθηκε',
        'pending' => 'Εκκρεμεί',
        _ => 'Νέα επίσκεψη',
      };
  static const outcomeNote = 'Τι μένει να γίνει';
  static const followUpPick = 'Διάλεξε ημερομηνία νέας επίσκεψης';
  static String followUpAt(String when) => 'Νέα επίσκεψη: $when';
  static const toSignature = 'Συνέχεια στην υπογραφή';

  // Signature
  static const signatureTitle = 'Υπογραφή πελάτη';
  static const signerName = 'Ονοματεπώνυμο';
  static const signHint = 'Υπόγραψε με το δάχτυλο';
  static const signaturePadLabel = 'Πεδίο υπογραφής. Σύρε το δάχτυλο για να υπογράψεις.';
  static const clear = 'Καθαρισμός';
  static const noSignature = 'Χωρίς υπογραφή';
  static const noSignatureTitle = 'Κλείσιμο χωρίς υπογραφή;';
  static const noSignatureMessage =
      'Το δελτίο κλείνει κανονικά και η χρέωση γίνεται όπως πάντα. Στο δελτίο θα γράφει «Χωρίς υπογραφή».';
  static const signAndClose = 'Υπογραφή και κλείσιμο';

  // Closed
  static const closedTitle = 'Δελτίο έκλεισε';
  static const cancelledTitle = 'Δελτίο ακυρώθηκε';
  static const cancelledMessage = 'Η επίσκεψη ακυρώθηκε.';
  static const savedMessage = 'Το δελτίο αποθηκεύτηκε';
  static const waitingSyncBanner =
      'Χωρίς σήμα. Η χρέωση, το email και το portal θα γίνουν μόλις συγχρονίσει.';
  static const awaitingColleagues =
      'Περιμένουμε να καταγράψουν αναχώρηση και οι άλλοι τεχνικοί. Μετά γίνονται η χρέωση και η αποστολή.';
  static const closeUnresolved =
      'Δεν επιβεβαιώθηκε αν το Office πήρε το κλείσιμο. Δεν θα σταλεί ξανά αυτόματα, ώστε να μη διπλοχρεωθεί.';
  static const checkRequest = 'Έλεγχος αιτήματος';
  static const recoverStillUnknown = 'Το Office δεν έχει ακόμη απάντηση. Δοκίμασε ξανά σε λίγο.';
  static const abandonTitle = 'Ακύρωση εκκρεμούς αιτήματος';
  static const abandonMessage =
      'Το Office δεν έχει καταγράψει το αίτημα. Θα αφαιρεθεί μόνο η τοπική εκκρεμότητα και το κλείσιμο θα γίνει ξανά με νέο κλειδί. Το παλιό αίτημα δεν θα σταλεί ξανά.';
  static const abandonConfirm = 'Ακύρωση αιτήματος';
  static const abandonAnswered = 'Το Office απάντησε για το αίτημα. Δεν ακυρώθηκε.';
  static String chargeState(String s) => switch (s) {
        'posted' => 'Η χρέωση έγινε',
        'invoice_pending' => 'Για τιμολόγηση',
        'held' => 'Η χρέωση περιμένει τον admin',
        'zero' => 'Χωρίς χρέωση',
        _ => 'Χρέωση',
      };
  static const paymentTitle = 'Είσπραξη (προαιρετικά)';
  static const cash = 'Μετρητά';
  static const bankDeposit = 'Τραπεζική κατάθεση';
  static const paymentAmount = 'Ποσό σε €';
  static const paymentReference = 'Αναφορά (προαιρετικά)';
  static const paymentHint = 'Καταγράφεται για το λογιστήριο. Δεν αλλάζει το υπόλοιπο.';
  static const paymentSave = 'Καταγραφή είσπραξης';
  static const paymentSaved = 'Η είσπραξη αποθηκεύτηκε.';
  static const paymentAmountInvalid = 'Γράψε ένα έγκυρο ποσό, π.χ. 50,00.';
  static const voided = 'ακυρώθηκε';
  static const pdfToContact = 'PDF στην κύρια επαφή';
  static String emailStateLabel(String? s) => switch (s) {
        'provider_accepted' => 'Στάλθηκε',
        'queued' || 'sending' => 'Στέλνεται',
        'retryable_failure' || 'delivery_unknown' => 'Έλεγχος αποστολής',
        'permanent_failure' => 'Απέτυχε',
        _ => 'Σε αναμονή',
      };
  static const backToToday = 'Πίσω στο Σήμερα';

  // Pending
  static const pendingTitle = 'Δελτία τεχνικού';
  static const pendingCloseUnresolved = 'Έλεγχος προηγούμενου αιτήματος';
  static String pendingWaiting(int n) => n == 1 ? 'Περιμένει συγχρονισμό (1 ενέργεια)' : 'Περιμένει συγχρονισμό ($n ενέργειες)';

  // Dates
  static const _days = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
  static const _months = ['Ιανουάριος', 'Φεβρουάριος', 'Μάρτιος', 'Απρίλιος', 'Μάιος', 'Ιούνιος', 'Ιούλιος', 'Αύγουστος', 'Σεπτέμβριος', 'Οκτώβριος', 'Νοέμβριος', 'Δεκέμβριος'];
  static String dayChip(DateTime d) => '${_days[d.weekday - 1]} ${d.day}';
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  /// Greek text for local error ids and Office rejection codes.
  static String rejection(String? code, String fallback, {int? limitBps}) {
    switch (code) {
      case 'discount_exceeds_limit':
        return limitBps == null || limitBps <= 0
            ? 'Η έκπτωση ξεπερνά το όριό σου. Μείωσέ την και κλείσε ξανά.'
            : 'Η έκπτωση ξεπερνά το όριό σου (${limitBps ~/ 100}%). Μείωσέ την και κλείσε ξανά.';
      case 'close_requires_arrival':
        return 'Δεν έχει καταγραφεί άφιξη. Πάτησε «Άφιξη» και κλείσε ξανά.';
      case 'outcome_required':
        return 'Διάλεξε αποτέλεσμα για να κλείσεις το δελτίο.';
      case 'charge_source_required':
        return 'Διάλεξε από πού γίνεται η χρέωση.';
      case 'signature_invalid':
        return 'Η υπογραφή δεν έγινε δεκτή. Υπόγραψε ξανά ή κλείσε χωρίς υπογραφή.';
      case 'visit_closed':
        return 'Το δελτίο έχει κλείσει — επικοινωνήστε με διαχειριστή.';
      case 'field_visit_lead_required':
        return 'Μόνο ο υπεύθυνος τεχνικός αλλάζει το περιεχόμενο του δελτίου.';
      case 'field_visit_participant_required':
        return 'Δεν συμμετέχεις σε αυτή την επίσκεψη.';
      case 'visit_started':
        return 'Η επίσκεψη έχει ήδη ξεκινήσει.';
      case 'visit_not_cancellable':
        return 'Η επίσκεψη δεν ακυρώνεται πια.';
      case 'time_in_future':
        return 'Η ώρα που καταγράφηκε είναι στο μέλλον. Έλεγξε την ώρα του κινητού.';
      case 'equipment_duplicate':
        return 'Ο εξοπλισμός υπάρχει ήδη στο μητρώο του πελάτη.';
      case 'field_visits_unavailable':
        return 'Η λειτουργία δελτίων δεν είναι ενεργή στο Office.';
    }
    return fallback;
  }

  /// Local validation ids (see `fvCloseBlockers`, `fvValidateAttendance`).
  static String errorFor(String id) => switch (id) {
        'not_lead' => 'Μόνο ο υπεύθυνος τεχνικός κλείνει το δελτίο.',
        'signature_required' => 'Υπόγραψε ή πάτα «Χωρίς υπογραφή».',
        'signer_required' => 'Γράψε το ονοματεπώνυμο αυτού που υπογράφει.',
        'open_pause' => 'Τελείωσε πρώτα την παύση.',
        'job_type_required' => 'Διάλεξε τύπο εργασίας.',
        'already_arrived' => 'Έχεις ήδη καταγράψει άφιξη.',
        'pause_invalid' || 'open_pause_invalid' || 'pause_overlap' || 'pause_outside' => 'Η παύση δεν είναι έγκυρη.',
        'departure_invalid' => 'Δεν υπάρχει ανοιχτή παρουσία για αναχώρηση.',
        'departure_before_arrival' => 'Η αναχώρηση πρέπει να είναι μετά την άφιξη.',
        'span_too_long' => 'Η παρουσία ξεπερνά τις 24 ώρες. Επικοινώνησε με τον admin.',
        'arrival_required' => 'Πάτα πρώτα «Άφιξη».',
        'signature_too_large' => 'Η υπογραφή είναι πολύ μεγάλη. Καθάρισε και υπόγραψε ξανά.',
        'visit_not_cancellable' => 'Η επίσκεψη δεν ακυρώνεται πια.',
        _ => rejection(id, id),
      };
}
