import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/exantas_device_display.dart';

class ExantasCustomerComputer extends StatelessWidget {
  const ExantasCustomerComputer(
      {super.key, required this.display, this.compact = false});
  final ExantasDeviceDisplay? display;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final identity = display;
    final style = compact
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    if (identity == null) {
      return Text('Στοιχεία πελάτη και υπολογιστή μη διαθέσιμα.', style: style);
    }
    final computer = identity.computerName.isEmpty
        ? 'Δεν έχει οριστεί όνομα υπολογιστή.'
        : identity.computerName;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Πελάτης', style: style),
      Text(identity.companyName,
          softWrap: true, style: style?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Υπολογιστής', style: style),
      Text(
          identity.peerId.isEmpty ? computer : '$computer · ${identity.peerId}',
          softWrap: true,
          style: style),
    ]);
  }
}
