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
    required this.customerName, required this.unattended});
  final String code, enrollmentId, customerId, customerName;
  final bool unattended;

  factory ExantasDeviceEnrollmentPreview.parse(String raw,
      Map<String, dynamic> response) {
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
        || installation['unattended_enabled'] is! bool) {
      throw const FormatException('Δεν επιβεβαιώθηκε ο πελάτης της εγκατάστασης.');
    }
    return ExantasDeviceEnrollmentPreview(code: code,
      enrollmentId: installation['enrollment_id'],
      customerId: installation['customer_id'],
      customerName: installation['customer_name'],
      unattended: installation['unattended_enabled']);
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
