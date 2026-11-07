import 'package:flutter/material.dart';

class ExSearchField extends StatelessWidget {
  const ExSearchField(
      {super.key,
      required this.controller,
      required this.label,
      this.onSubmitted,
      this.enabled = true});
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: onSubmitted == null
              ? null
              : IconButton(
                  tooltip: label,
                  onPressed: enabled ? () => onSubmitted!(controller.text) : null,
                  icon: const Icon(Icons.arrow_forward))));
}
