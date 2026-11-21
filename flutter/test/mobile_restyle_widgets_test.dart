import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/ui/ex_settings.dart';
import 'package:flutter_hbb/mobile/ui/exantas_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
    theme: ExantasTheme.light(),
    home: Scaffold(
        body: ColoredBox(
            color: ExantasTokens.light.surfaceAlt,
            child: Padding(padding: const EdgeInsets.all(16), child: child))));

void main() {
  testWidgets('ExSettingsSection keeps callbacks and disabled switches',
      (tester) async {
    var pressed = 0;
    bool? toggled;
    await tester
        .pumpWidget(_host(ExSettingsSection(title: const Text('Group'), tiles: [
      ExSettingsTile(
          title: const Text('Open'),
          leading: const Icon(Icons.cloud),
          onPressed: (_) => pressed++),
      ExSettingsTile.switchTile(
          title: const Text('Flag'),
          initialValue: false,
          onToggle: (v) async => toggled = v),
      const ExSettingsTile.switchTile(
          title: Text('Fixed'), initialValue: true, onToggle: null),
    ])));
    await tester.tap(find.text('Open'));
    expect(pressed, 1);
    await tester.tap(find.text('Flag'));
    expect(toggled, true);
    final fixed = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Fixed'));
    expect(fixed.onChanged, isNull);
  });
}
