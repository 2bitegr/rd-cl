import 'package:flutter/material.dart';
import 'exantas_theme.dart';

class ExSectionHeader extends StatelessWidget {
  const ExSectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: ExantasTokens.space2),
      child: Row(children: [
        Expanded(
            child: Semantics(
                header: true,
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium))),
        if (action != null) action!,
      ]));
}
