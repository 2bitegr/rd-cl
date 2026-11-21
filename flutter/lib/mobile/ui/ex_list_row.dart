import 'package:flutter/material.dart';
import 'exantas_theme.dart';

/// Tappable list row with a rounded icon tile, >=48dp high.
class ExListRow extends StatelessWidget {
  const ExListRow(
      {super.key,
      required this.title,
      this.subtitle,
      this.icon,
      this.trailing,
      this.onTap,
      this.selected = false});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return ListTile(
        enabled: onTap != null,
        selected: selected,
        selectedTileColor: t.accentSoft,
        selectedColor: t.accent,
        minTileHeight: ExantasTokens.minTouch,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ExantasTokens.space4, vertical: ExantasTokens.space1),
        leading: icon == null
            ? null
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(ExantasTokens.radiusMd)),
                child: Icon(icon, size: 22, color: t.accent)),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
        trailing: trailing ??
            (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
        onTap: onTap);
  }
}
