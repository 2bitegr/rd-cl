import 'package:flutter/material.dart';

/// Closing or accepting the default returns no financial instruction.
class ExantasSessionDecisionDialog extends StatefulWidget {
  const ExantasSessionDecisionDialog({super.key, required this.peerId, required this.note});
  final String peerId;
  final TextEditingController note;
  @override State<ExantasSessionDecisionDialog> createState() => _DecisionState();
}
class _DecisionState extends State<ExantasSessionDecisionDialog> {
  String selected = 'later';
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ολοκλήρωση συνεδρίας'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('RustDesk ${widget.peerId}'),
      const Text('Η λήξη σύνδεσης δεν ολοκληρώνει αυτόματα την εργασία.'),
      for (final entry in const {'automatic': 'Κανονική χρέωση', 'free': 'Χωρίς χρέωση', 'later': 'Αργότερα', 'ignore': 'Εξαίρεση'}.entries)
        RadioListTile<String>(value: entry.key, groupValue: selected, title: Text(entry.value),
          onChanged: (value) => setState(() => selected = value!)),
      const Text('Η συνέχεια επιβεβαιώνει τη δική σας περιγραφή και την επιλεγμένη απόφαση για προεπισκόπηση Office.'),
      TextField(controller: widget.note, maxLines: 3, decoration: const InputDecoration(labelText: 'Περιγραφή εργασίας')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Κλείσιμο')),
      TextButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Συνέχεια'))],
  );
}
