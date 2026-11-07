import 'package:flutter/material.dart';
import 'exantas_strings.dart';
import 'exantas_theme.dart';

/// Warning banner (icon + text) shown while the device has no connectivity.
class ExOfflineBanner extends StatelessWidget {
  const ExOfflineBanner({super.key, this.message = ExStrings.offline});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Semantics(
        liveRegion: true,
        child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: ExantasTokens.gutter, vertical: ExantasTokens.space3),
            color: t.warningSoft,
            child: Row(children: [
              Icon(Icons.cloud_off_outlined, size: 20, color: t.warning),
              const SizedBox(width: ExantasTokens.space2),
              Expanded(
                  child: Text(message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: t.warning))),
            ])));
  }
}
