import 'package:flutter/material.dart';
import 'exantas_strings.dart';
import 'exantas_theme.dart';

/// Returns true only on explicit confirmation.
Future<bool> showExConfirmDialog(BuildContext context,
    {required String title,
    required String message,
    String confirmLabel = ExStrings.confirm,
    String cancelLabel = ExStrings.cancel,
    bool destructive = false}) async {
  final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ExConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive));
  return result == true;
}

class ExConfirmDialog extends StatelessWidget {
  const ExConfirmDialog(
      {super.key,
      required this.title,
      required this.message,
      this.confirmLabel = ExStrings.confirm,
      this.cancelLabel = ExStrings.cancel,
      this.destructive = false});
  final String title, message, confirmLabel, cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelLabel)),
            FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: context.ex.danger)
                    : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel)),
          ]);
}
