import 'package:flutter/material.dart';
import 'exantas_theme.dart';

class ExEmptyState extends StatelessWidget {
  const ExEmptyState(
      {super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ExantasTokens.space6, vertical: ExantasTokens.space8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 32, color: t.textSecondary),
          const SizedBox(height: ExantasTokens.space3),
          Text(title, textAlign: TextAlign.center, style: text.bodyMedium),
          if (message != null) ...[
            const SizedBox(height: ExantasTokens.space1),
            Text(message!, textAlign: TextAlign.center, style: text.bodySmall),
          ],
        ]));
  }
}
