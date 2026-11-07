import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final s in segments)
              ButtonSegment<T>(
                  value: s.value,
                  icon: s.icon == null ? null : Icon(s.icon),
                  label: Text(s.label,
                      key: s.key, maxLines: 1, overflow: TextOverflow.ellipsis))
          ],
          selected: {selected},
          onSelectionChanged: (v) => onChanged(v.first)));
}
