import 'package:flutter/material.dart';
import 'exantas_theme.dart';

enum ExStatus { neutral, info, success, warning, danger }

/// Status is always icon + text, never color alone.
class ExStatusPill extends StatelessWidget {
  const ExStatusPill(this.label,
      {super.key, this.status = ExStatus.neutral, this.icon});
  final String label;
  final ExStatus status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final (Color fg, Color bg, IconData ic) = switch (status) {
      ExStatus.success => (t.success, t.successSoft, Icons.check_circle_outline),
      ExStatus.warning => (t.warning, t.warningSoft, Icons.warning_amber_rounded),
      ExStatus.danger => (t.danger, t.dangerSoft, Icons.error_outline),
      ExStatus.info => (t.accent, t.accentSoft, Icons.info_outline),
      ExStatus.neutral => (t.textSecondary, t.surfaceAlt, Icons.circle_outlined),
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ExantasTokens.radiusPill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon ?? ic, size: 16, color: fg),
          const SizedBox(width: 4),
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: fg))),
        ]));
  }
}
