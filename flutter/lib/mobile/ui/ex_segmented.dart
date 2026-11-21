import 'package:flutter/material.dart';
import 'exantas_theme.dart';

class ExSegment<T> {
  const ExSegment(this.value, this.label, {this.icon, this.key});
  final T value;
  final String label;
  final IconData? icon;
  final Key? key;
}

/// Full-width M3 SegmentedButton (single selection).
class ExSegmented<T> extends StatelessWidget {
  const ExSegmented(
      {super.key,
      required this.segments,
      required this.selected,
      required this.onChanged});
  final List<ExSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    // Large text cannot fit one row of segments: wrap them as choice chips so
    // every label stays fully readable and a 48dp target.
    if (MediaQuery.textScalerOf(context).scale(14) >= 20) {
      return Semantics(
        container: true,
        child: Wrap(spacing: ExantasTokens.space2, runSpacing: ExantasTokens.space2, children: [
          for (final s in segments)
            ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: ExantasTokens.minTouch),
                child: ChoiceChip(
                    showCheckmark: false,
                    selected: s.value == selected,
                    avatar: s.icon == null ? null : Icon(s.icon, size: 18),
                    label: Text(s.label, key: s.key),
                    onSelected: (_) => onChanged(s.value))),
        ]),
      );
    }
    return _row();
  }

  Widget _row() => SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final s in segments)
              ButtonSegment<T>(
                  value: s.value,
                  icon: s.icon == null ? null : Icon(s.icon),
                  label: Text(s.label,
                      key: s.key, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis))
          ],
          selected: {selected},
          onSelectionChanged: (v) => onChanged(v.first)));
}
