import 'package:flutter/material.dart';
import 'exantas_theme.dart';

/// Compact page header (title + optional actions) over a scrollable body on
/// the surfaceAlt background. Use `scrollable: false` for bodies that scroll
/// themselves.
class ExScaffold extends StatelessWidget {
  const ExScaffold(
      {super.key,
      required this.title,
      required this.children,
      this.actions = const [],
      this.banner,
      this.scrollable = true});
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? banner;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return ColoredBox(
        color: t.surfaceAlt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExPageHeader(title: title, actions: actions),
          if (banner != null) banner!,
          Expanded(
              child: scrollable
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(
                          ExantasTokens.gutter,
                          ExantasTokens.space4,
                          ExantasTokens.gutter,
                          ExantasTokens.space8),
                      children: children)
                  : Column(children: children)),
        ]));
  }
}

class ExPageHeader extends StatelessWidget {
  const ExPageHeader({super.key, required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minHeight: ExantasTokens.minTouch),
      padding: const EdgeInsets.only(left: ExantasTokens.gutter, right: ExantasTokens.space2),
      child: Row(children: [
        Expanded(
            child: Semantics(
                header: true,
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge))),
        ...actions,
      ]));
}
