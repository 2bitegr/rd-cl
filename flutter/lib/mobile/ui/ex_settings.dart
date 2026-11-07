import 'package:flutter/material.dart';
import 'exantas_theme.dart';

/// One row of an [ExSettingsSection]. Mirrors the small subset of the former
/// `settings_ui` tile API that the mobile settings page used, so the page keeps
/// its callbacks and conditions unchanged while the presentation follows the
/// Exantas tokens.
class ExSettingsTile {
  const ExSettingsTile({
    this.title,
    this.leading,
    this.trailing,
    this.value,
    this.description,
    this.onPressed,
  })  : _isSwitch = false,
        initialValue = null,
        onToggle = null;

  const ExSettingsTile.switchTile({
    required this.initialValue,
    required this.onToggle,
    this.title,
    this.leading,
    this.description,
  })  : _isSwitch = true,
        trailing = null,
        value = null,
        onPressed = null;

  final Widget? title, leading, trailing, value, description;
  final void Function(BuildContext context)? onPressed;
  final bool? initialValue;
  final Future<void> Function(bool)? onToggle;
  final bool _isSwitch;

  Widget build(BuildContext context) {
    final subtitle = description ?? value;
    if (_isSwitch) {
      return SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: ExantasTokens.space4, vertical: ExantasTokens.space1),
          secondary: leading,
          title: title,
          subtitle: subtitle,
          value: initialValue ?? false,
          onChanged: onToggle == null ? null : (v) => onToggle!(v));
    }
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ExantasTokens.space4, vertical: ExantasTokens.space1),
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing ??
            (onPressed == null
                ? null
                : const Icon(Icons.chevron_right, size: 20)),
        onTap: onPressed == null ? null : () => onPressed!(context));
  }
}

/// Section = optional header + a bordered white card of rows.
class ExSettingsSection extends StatelessWidget {
  const ExSettingsSection({super.key, this.title, required this.tiles});
  final Widget? title;
  final List<ExSettingsTile> tiles;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, color: t.border));
      rows.add(tiles[i].build(context));
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: ExantasTokens.space4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
                padding: const EdgeInsets.only(bottom: ExantasTokens.space2),
                child: Semantics(
                    header: true,
                    child: DefaultTextStyle(
                        style: Theme.of(context).textTheme.titleMedium!,
                        child: title!))),
          Card(clipBehavior: Clip.antiAlias, child: Column(children: rows)),
        ]));
  }
}

/// Free-form block (logo / powered-by) inside the settings list.
class ExCustomSettingsSection extends StatelessWidget {
  const ExCustomSettingsSection({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Scrollable list of sections on the surfaceAlt background.
class ExSettingsList extends StatelessWidget {
  const ExSettingsList({super.key, required this.sections});
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: context.ex.surfaceAlt,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(ExantasTokens.gutter,
              ExantasTokens.space4, ExantasTokens.gutter, ExantasTokens.space8),
          children: sections));
}
