import 'package:flutter/material.dart';

import '../../models/exantas_field_visit_sync.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';

/// Form for a customer that does not exist in Office yet. The visit proceeds
/// at once; an admin approves (or links) the draft later.
class FvDraftCustomerPage extends StatefulWidget {
  const FvDraftCustomerPage({super.key, this.initialName = ''});
  final String initialName;
  @override
  State<FvDraftCustomerPage> createState() => _FvDraftCustomerPageState();
}

class _FvDraftCustomerPageState extends State<FvDraftCustomerPage> {
  late final name = TextEditingController(text: widget.initialName);
  final afm = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      contact = TextEditingController(),
      address = TextEditingController(),
      notes = TextEditingController();
  String? nameError, emailError;

  @override
  void dispose() {
    for (final c in [name, afm, phone, email, contact, address, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final emailText = email.text.trim();
    setState(() {
      nameError = name.text.trim().isEmpty ? FvStrings.draftNameRequired : null;
      emailError = emailText.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailText)
          ? FvStrings.draftEmailInvalid
          : null;
    });
    if (nameError != null || emailError != null) return;
    Navigator.of(context).pop(FvDraftCustomerInput(
        companyName: name.text,
        afm: afm.text,
        phone: phone.text,
        email: emailText,
        contactName: contact.text,
        address: address.text,
        notes: notes.text));
  }

  Widget _field(TextEditingController c, String label,
          {String? error, TextInputType? type, int maxLines = 1, Key? key}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
          child: TextField(
              key: key,
              controller: c,
              keyboardType: type,
              maxLines: maxLines,
              decoration: InputDecoration(labelText: label, errorText: error)));

  @override
  Widget build(BuildContext context) {
    final t = context.ex;
    return Scaffold(
        appBar: AppBar(title: const Text(FvStrings.draftCustomerTitle)),
        body: ColoredBox(
            color: t.surfaceAlt,
            child: ListView(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                children: [
                  Text(FvStrings.draftCustomerHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.textSecondary)),
                  const SizedBox(height: ExantasTokens.space3),
                  _field(name, FvStrings.draftCompany, error: nameError, key: const ValueKey('fv-draft-name')),
                  _field(afm, FvStrings.draftAfm, type: TextInputType.number),
                  _field(phone, FvStrings.draftPhone, type: TextInputType.phone),
                  _field(email, FvStrings.draftEmail, error: emailError, type: TextInputType.emailAddress),
                  _field(contact, FvStrings.draftContact),
                  _field(address, FvStrings.draftAddress),
                  _field(notes, FvStrings.draftNotes, maxLines: 3),
                ])),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(ExantasTokens.gutter),
                child: FilledButton(
                    key: const ValueKey('fv-draft-save'),
                    onPressed: _submit,
                    child: const Text(FvStrings.draftContinue)))));
  }
}
