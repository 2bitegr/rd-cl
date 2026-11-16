/// Read-only presentation metadata, never an enrollment or access grant.
class ExantasDeviceDisplay {
  const ExantasDeviceDisplay(
      {required this.companyName,
      required this.computerName,
      this.peerId = ''});
  final String companyName, computerName, peerId;
}

class ExantasDeviceDisplayScope {
  const ExantasDeviceDisplayScope(
      {required this.apiBase,
      required this.deviceId,
      required this.deviceToken,
      required this.peerId,
      required this.enabled});
  final String apiBase, deviceId, deviceToken, peerId;
  final bool enabled;
  bool get available =>
      enabled &&
      deviceId.isNotEmpty &&
      deviceToken.isNotEmpty &&
      RegExp(r'^\d{6,10}$').hasMatch(peerId);
  bool matches(ExantasDeviceDisplayScope other) =>
      available &&
      other.available &&
      apiBase == other.apiBase &&
      deviceId == other.deviceId &&
      deviceToken == other.deviceToken &&
      peerId == other.peerId;
}

String _displayText(dynamic value) => value is String ? value.trim() : '';

ExantasDeviceDisplay? parseExantasDeviceDisplay(
    Map<String, dynamic> response, ExantasDeviceDisplayScope scope) {
  final device = response['device'];
  if (!scope.available ||
      response['status'] != 'ok' ||
      device is! Map ||
      device['id'] != scope.deviceId ||
      device['peer_id'] != scope.peerId ||
      device['revoked_at'] != null ||
      device['status'] == 'revoked' ||
      device['activation_status'] == 'pending' ||
      (device['policy'] is Map &&
          device['policy']['office_activation_pending'] == true) ||
      _displayText(device['customer_id']).isEmpty) return null;
  final company = _displayText(device['customer_name']);
  if (company.isEmpty) return null;
  final names = ['label', 'hostname', 'device_name']
      .map((key) => _displayText(device[key]));
  return ExantasDeviceDisplay(
      companyName: company,
      peerId: scope.peerId,
      computerName:
          names.firstWhere((name) => name.isNotEmpty, orElse: () => ''));
}

Future<ExantasDeviceDisplay?> readExantasDeviceDisplay({
  required Future<ExantasDeviceDisplayScope> Function() readScope,
  required Future<Map<String, dynamic>> Function(ExantasDeviceDisplayScope)
      readPolicy,
}) async {
  final before = await readScope();
  if (!before.available) return null;
  final response =
      await readPolicy(before).timeout(const Duration(seconds: 12));
  if (!before.matches(await readScope())) return null;
  return parseExantasDeviceDisplay(response, before);
}
