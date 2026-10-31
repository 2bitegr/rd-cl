/// Public enrollment preview, separate from staff authentication and tokens.
class ExantasDeviceEnrollmentStatus {
  const ExantasDeviceEnrollmentStatus({required this.enrolled,
    required this.staffSignedIn, required this.customerName,
    this.pending = false});
  final bool enrolled, staffSignedIn, pending;
  final String customerName;
}

class ExantasDeviceEnrollmentPreview {
  const ExantasDeviceEnrollmentPreview({required this.code,
    required this.enrollmentId, required this.customerId,
    required this.customerName, required this.unattended, this.automatic = false, this.expectedPeerId, this.apiBase});
  final String code, enrollmentId, customerId, customerName;
  final bool unattended;
  final bool automatic;
  final String? expectedPeerId;
  final String? apiBase;

  factory ExantasDeviceEnrollmentPreview.parse(String raw,
      Map<String, dynamic> response, {String? apiBase}) {
    final code = raw.trim().toUpperCase();
    final installation = response['installation'];
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');
    if (!RegExp(r'^EXA-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(code)
        || response['status'] != 'ok' || response['contract_version'] != 1
        || installation is! Map<String, dynamic>
        || installation['enrollment_id'] is! String
        || !uuid.hasMatch(installation['enrollment_id'])
        || installation['customer_id'] is! String
        || !uuid.hasMatch(installation['customer_id'])
        || installation['customer_name'] is! String
        || (installation['customer_name'] as String).trim().isEmpty
        || installation['unattended_enabled'] is! bool
        || (installation['automatic_enrollment'] == true &&
            (installation['expected_peer_id'] is! String || !RegExp(r'^\d{6,10}$').hasMatch(installation['expected_peer_id'])))) {
      throw const FormatException('Δεν επιβεβαιώθηκε ο πελάτης της εγκατάστασης.');
    }
    return ExantasDeviceEnrollmentPreview(code: code,
      enrollmentId: installation['enrollment_id'],
      customerId: installation['customer_id'],
      customerName: installation['customer_name'],
      unattended: installation['unattended_enabled'],
      automatic: installation['automatic_enrollment'] == true,
      expectedPeerId: installation['expected_peer_id'] is String ? installation['expected_peer_id'] : null, apiBase: apiBase);
  }
}

/// The browser transfers the existing installation capability, never staff auth.
String? enrollmentCodeFromLink(Uri uri) {
  try {
  if (uri.scheme != 'exantas-support-enroll' || uri.authority != 'install' ||
      (uri.path.isNotEmpty && uri.path != '/') || uri.fragment.isNotEmpty ||
      uri.queryParametersAll.length != 1 || uri.queryParametersAll['code']?.length != 1) return null;
  final code = uri.queryParameters['code']?.trim().toUpperCase() ?? '';
  return RegExp(r'^EXA-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(code) ? code : null;
  } on FormatException { return null; }
}

class ExantasEnrollmentFailure implements Exception {
  const ExantasEnrollmentFailure(this.message);
  final String message;
}

void requireEnrollmentPeer(ExantasDeviceEnrollmentPreview preview, String peerId) {
  if (preview.expectedPeerId != null && preview.expectedPeerId != peerId) {
    throw const ExantasEnrollmentFailure('Το ID αυτού του υπολογιστή δεν ταιριάζει με την επαφή. Ελέγξτε την αντιστοίχιση στο Office και κάντε νέα λήψη.');
  }
}
