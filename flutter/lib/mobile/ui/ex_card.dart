import 'package:flutter/material.dart';
import 'exantas_theme.dart';

/// White card with a 1px border (theme CardTheme), optional tap and padding.
class ExCard extends StatelessWidget {
  const ExCard(
      {super.key,
      required this.child,
      this.onTap,
      this.color,
      this.padding = const EdgeInsets.all(ExantasTokens.space4)});
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap, child: Padding(padding: padding, child: child)));
}
