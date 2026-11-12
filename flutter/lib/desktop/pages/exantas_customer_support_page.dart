import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../models/exantas_customer_ticket.dart';

String _text(Map row, String key) => row[key]?.toString() ?? '';
String _stamp(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  final day = two(date.day), month = two(date.month), year = date.year;
  final hour = two(date.hour),
      minute = two(date.minute),
      zone = date.timeZoneName;
  return '$day/$month/$year $hour:$minute $zone';
}

class ExantasCustomerSupportPage extends StatefulWidget {
  const ExantasCustomerSupportPage(
      {super.key,
      required this.client,
      required this.pickFiles,
      required this.captureScreenshot,
      required this.previewLocal,
      required this.openMedia,
      this.identityChanges});
  final ExantasCustomerTicketClient client;
  final Future<List<String>> Function() pickFiles;
  final Future<String?> Function() captureScreenshot;
  final Future<void> Function(String) previewLocal;
  final Future<void> Function(Uri) openMedia;
  final Listenable? identityChanges;
  @override
  State<ExantasCustomerSupportPage> createState() => _CustomerSupportState();
}

class _CustomerSupportState extends State<ExantasCustomerSupportPage> {
  final _subject = TextEditingController(),
      _description = TextEditingController(),
      _name = TextEditingController(),
      _phone = TextEditingController(),
      _reply = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _items = [], _files = [];
  Map<String, dynamic>? _detail;
  String _category = 'problem', _priority = 'normal', _error = '', _notice = '';
  String? _next, _eventsNext, _selected;
  bool _loading = true,
      _running = false,
      _composing = false,
      _dirty = false,
      _allowClose = false,
      _identityBlocked = false;
  int _sent = 0, _total = 0, _uploadIndex = 0;
  String _stage = '';
  int _identityGeneration = 0;
  ExantasCustomerTicketClient get client => widget.client;

  @override
  void initState() {
    super.initState();
    widget.identityChanges?.addListener(_accountChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    widget.identityChanges?.removeListener(_accountChanged);
    for (final controller in [_subject, _description, _name, _phone, _reply]) {
      controller.dispose();
    }
    unawaited(client.dispose());
    super.dispose();
  }

  void _accountChanged() {
    final generation = ++_identityGeneration;
    setState(() => _identityBlocked = true);
    unawaited(_recheckAccount(generation));
  }

  Future<void> _recheckAccount(int generation) async {
    final previous = ticketMap(client.capabilities?['context'] ?? {});
    try {
      await client.checkIdentity();
      await client.refreshCapabilities();
      final next = ticketMap(client.capabilities?['context'] ?? {});
      if (previous.isNotEmpty &&
          (previous['customer_id'] != next['customer_id'] ||
              previous['branch_id'] != next['branch_id'])) {
        throw const ExantasTicketFailure('ticket_device_scope_changed');
      }
      if (mounted && generation == _identityGeneration) {
        setState(() => _identityBlocked = false);
      }
    } catch (error) {
      if (mounted && generation == _identityGeneration) {
        setState(() => _recordError(error));
      }
    }
  }

  Future<void> _initialize() async {
    try {
      await client.load();
      if (!mounted) return;
      _restoreDraft();
      await client.refreshCapabilities();
      if (!mounted) return;
      if (client.capabilities?['enabled'] == true) {
        await _list();
        final row = client.draft;
        if (row?['request_id'] != null) {
          await _detailFor(row!['request_id']);
        } else if (client.pendingReply != null) {
          await _detailFor(client.pendingReply!['ticket_id']);
        }
      }
    } catch (error) {
      _recordError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _restoreDraft() {
    final row = client.draft;
    if (row == null) return;
    _files = ((row['files'] as List?) ?? []).map(ticketMap).toList();
    if (row['input'] != null) {
      final input = ticketMap(row['input']);
      _subject.text = _text(input, 'subject');
      _description.text = _text(input, 'details');
      _name.text = _text(input, 'contact_name');
      _phone.text = _text(input, 'contact_phone');
      _category = _text(input, 'category');
      _priority = _text(input, 'priority');
      _composing = row['request_id'] == null;
    }
  }

  void _recordError(Object error) {
    if (error is ExantasTicketFailure &&
        (error.code == 'ticket_identity_changed' ||
            error.code == 'ticket_device_scope_changed' ||
            error.status == 401 ||
            error.status == 403)) {
      _identityBlocked = true;
      _items = [];
      _detail = null;
    }
    _error = ticketFailureMessage(error);
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = '';
      _notice = '';
      _stage = '';
      _sent = 0;
      _total = 0;
    });
    try {
      await operation();
    } catch (error) {
      _recordError(error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _list({bool more = false}) async {
    final response = await client.request('', query: {
      'status': 'all',
      if (more && _next != null) 'before': _next!,
    });
    if (!mounted) return;
    final rows = (response['items'] as List).map(ticketMap).toList();
    _items = more ? [..._items, ...rows] : rows;
    _next = response['next_cursor'];
  }

  Future<void> _detailFor(String id, {bool more = false}) async {
    final response = await client.request('/$id', query: {
      if (more && _eventsNext != null) 'events_before': _eventsNext!,
    });
    if (!mounted) return;
    if (more && _selected == id && _detail != null) {
      response['events'] = [
        ...response['events'] as List,
        ..._detail!['events'] as List
      ];
    }
    if (_selected != id) {
      _reply.text = client.pendingReply?['ticket_id'] == id
          ? _text(client.pendingReply!, 'body')
          : '';
    }
    _detail = response;
    _selected = id;
    _eventsNext = response['events_next_cursor'];
    _composing = false;
  }

  Map<String, dynamic> _input() => {
        'category': _category,
        'priority': _priority,
        'subject': _subject.text,
        'details': _description.text,
        'contact_name': _name.text,
        'contact_phone': _phone.text,
      };
  bool get _frozen => client.draft?['attempted'] == true;
  Future<void> _save() async {
    if (_frozen || !_composing) return;
    await client.saveDraft(_input(), _files);
    _dirty = false;
    _notice =
        'Το πρόχειρο αποθηκεύτηκε προστατευμένα σε αυτόν τον υπολογιστή. Δεν στάλθηκε.';
  }

  Future<bool> _leaveCurrent() async {
    if (_running) return false;
    if (_dirty && _composing) await _save();
    if (_reply.text.isNotEmpty && client.pendingReply == null) {
      return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Μη αποσταλμένη απάντηση'),
                    content: const Text(
                        'Η απάντηση δεν έχει σταλεί. Να φύγετε από αυτή την προβολή;'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Παραμονή')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Έξοδος χωρίς αποστολή')),
                    ],
                  )) ??
          false;
    }
    return true;
  }

  Future<void> _close() async {
    if (_running || _loading) {
      setState(() => _notice =
          'Περιμένετε να ολοκληρωθεί ή να διακοπεί η τρέχουσα ενέργεια.');
      return;
    }
    try {
      if (!_identityBlocked && !await _leaveCurrent() || !mounted) return;
      setState(() => _allowClose = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _recordError(error));
    }
  }

  Future<void> _new() async {
    if (client.draft != null) {
      _restoreDraft();
      final id = client.draft!['request_id'];
      if (id != null) await _detailFor(id);
      _notice =
          'Συνεχίστε πρώτα το ήδη αποθηκευμένο πρόχειρο ή τα εκκρεμή συνημμένα.';
      return;
    }
    _subject.clear();
    _description.clear();
    _name.clear();
    _phone.clear();
    _reply.clear();
    _files = [];
    _detail = null;
    _selected = null;
    _dirty = false;
    _category = 'problem';
    _priority = 'normal';
    _composing = true;
  }

  Future<void> _acceptCreated(Map<String, dynamic> ticket) async {
    final id = ticket['id'] ?? ticket['request_id'];
    if (!ticketUuid.hasMatch(id?.toString() ?? '')) {
      throw const ExantasTicketFailure('ticket_contract');
    }
    _composing = false;
    _dirty = false;
    _notice = 'Το αίτημα καταχωρίστηκε. Δεν ξεκίνησε σύνδεση ή χρέωση.';
    await _detailFor(id);
    await _list();
    if (((client.draft?['files'] as List?) ?? []).isNotEmpty) {
      await _upload();
    } else {
      await client.finishDraft();
    }
  }

  Future<void> _submit() async {
    if (!_frozen && !(_form.currentState?.validate() ?? false)) return;
    await _save();
    await _acceptCreated(await client.submit());
  }

  Future<void> _recover() async {
    final ticket = await client.recoverCreate();
    if (ticket == null) {
      _notice =
          'Δεν βρέθηκε ακόμη επιβεβαίωση. Επαναλάβετε την ίδια υποβολή, με τον ίδιο αριθμό.';
    } else {
      await _acceptCreated(ticket);
    }
  }

  Future<void> _add(List<String> paths) async {
    if (paths.isEmpty) return;
    final selected = <Map<String, dynamic>>[];
    for (final path in paths) {
      selected.add(await inspectTicketFile(path));
    }
    if (_composing) {
      final combined = [..._files, ...selected];
      checkTicketFileQuota(combined);
      _files = combined;
      _dirty = true;
      await _save();
    } else {
      if (_selected == null) return;
      await client.stageFiles(_selected!, selected);
      _notice =
          'Τα συνημμένα αποθηκεύτηκαν για συνέχεια. Πατήστε «Μεταφόρτωση συνημμένων» για αποστολή.';
    }
  }

  Future<void> _capture() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Screenshot κύριας οθόνης'),
              content: const Text(
                  'Κρύψτε κωδικούς και άσχετα προσωπικά στοιχεία. Επιλέξτε πού θα αποθηκευτεί το αρχείο. Το rd-cl θα ελαχιστοποιηθεί και η λήψη θα γίνει μετά από 3 δευτερόλεπτα. Θα δείτε το αρχείο πριν από την αποστολή.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Άκυρο')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Λήψη screenshot')),
              ],
            ));
    if (confirmed != true) return;
    if (!mounted) return;
    await _run(() async {
      _stage = 'Προετοιμασία screenshot…';
      if (mounted) setState(() {});
      final path = await widget.captureScreenshot();
      if (path != null) await _add([path]);
      _stage = '';
    });
  }

  Future<void> _upload() async {
    await client.uploadPending(progress: (index, stage, sent, total) {
      if (mounted) {
        setState(() {
          _uploadIndex = index;
          _stage = stage;
          _sent = sent;
          _total = total;
        });
      }
    });
    await client.finishDraft();
    _files = [];
    _stage = '';
    _notice =
        'Τα συνημμένα επισυνάφθηκαν. Τα αρχικά αρχεία παραμένουν στον υπολογιστή σας.';
    if (_selected != null) await _detailFor(_selected!);
  }

  Future<void> _replyNow() async {
    if (_selected == null || _reply.text.trim().isEmpty) return;
    await client.reply(_selected!, _reply.text);
    _reply.clear();
    await _detailFor(_selected!);
    _notice = 'Η απάντηση καταχωρίστηκε στο ίδιο ιστορικό.';
  }

  Future<void> _stopPendingFiles() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Διακοπή εκκρεμών μεταφορτώσεων'),
                content: const Text(
                    'Το αίτημα και όσα συνημμένα έχουν ήδη σταλεί παραμένουν στο Office. Τα πρωτότυπα αρχεία στον υπολογιστή σας δεν διαγράφονται. Θα αφαιρεθεί μόνο η τοπική εκκρεμότητα αποστολής.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Παραμονή')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Διακοπή μεταφορτώσεων'))
                ]));
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await client.discardDraft();
      _notice =
          'Οι εκκρεμείς μεταφορτώσεις σταμάτησαν. Το αίτημα και τα πρωτότυπα αρχεία διατηρούνται.';
      if (_selected != null) await _detailFor(_selected!);
    });
  }

  Widget _field(String label, TextEditingController controller,
          {int max = 200, int lines = 1, bool required = false}) =>
      TextFormField(
          controller: controller,
          maxLength: max,
          minLines: lines,
          maxLines: lines,
          enabled: !_running && !_frozen,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() => _dirty = true),
          validator: (text) => required && (text?.trim().length ?? 0) < 3
              ? 'Συμπληρώστε τουλάχιστον 3 χαρακτήρες.'
              : null);
  Widget _localFile(Map<String, dynamic> file,
      {int? index, VoidCallback? remove}) {
    final name = _text(file, 'filename'), path = _text(file, 'path');
    final bytes = file['byte_size'] as int;
    final size = (bytes / 1000000).toStringAsFixed(1);
    final video = _text(file, 'media_type').startsWith('video/');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · $size MB',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!video && path.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Image.file(File(path),
                          height: 140,
                          cacheWidth: 600,
                          semanticLabel: 'Προεπισκόπηση $name',
                          errorBuilder: (_, __, ___) => const Text(
                              'Η εικόνα δεν είναι διαθέσιμη. Επιλέξτε το αρχικό αρχείο.'))),
                if (video)
                  TextButton.icon(
                      onPressed: _running
                          ? null
                          : () => _run(() => widget.previewLocal(path)),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Προεπισκόπηση στον τοπικό player')),
                Text(file['ready'] == true
                    ? 'Επισυνάφθηκε'
                    : 'Εκκρεμεί αποστολή'),
                if (remove != null)
                  TextButton(
                      onPressed: _running ? null : remove,
                      child: const Text('Αφαίρεση από το πρόχειρο')),
                if (index != null)
                  TextButton(
                      onPressed: _running
                          ? null
                          : () => _run(() async {
                                final paths = await widget.pickFiles();
                                if (paths.length == 1) {
                                  await client.reselectFile(
                                      index, paths.single);
                                }
                              }),
                      child:
                          const Text('Επιλογή αρχικού αρχείου για συνέχεια')),
              ],
            )));
  }

  Widget _fileActions() => Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: _running || _frozen && _composing
                ? null
                : () => _run(() async => _add(await widget.pickFiles())),
            icon: const Icon(Icons.attach_file),
            label: const Text('Επιλογή εικόνων ή βίντεο')),
        OutlinedButton.icon(
            onPressed: _running || _frozen && _composing ? null : _capture,
            icon: const Icon(Icons.screenshot_monitor),
            label: const Text('Νέο screenshot')),
      ]);
  Widget _composer() => Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Νέο αίτημα υποστήριξης',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Τύπος αιτήματος'),
            items: ticketCategories.entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: _running || _frozen
                ? null
                : (value) => setState(() {
                      _category = value!;
                      _dirty = true;
                    })),
        DropdownButtonFormField<String>(
            value: _priority,
            decoration: const InputDecoration(labelText: 'Προτεραιότητα'),
            items: ticketPriorities.entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: _running || _frozen
                ? null
                : (value) => setState(() {
                      _priority = value!;
                      _dirty = true;
                    })),
        const SizedBox(height: 16),
        _field('Θέμα αιτήματος', _subject, required: true),
        const SizedBox(height: 12),
        _field('Περιγραφή προβλήματος', _description,
            max: 4000, lines: 5, required: true),
        const SizedBox(height: 12),
        _field('Όνομα επικοινωνίας (προαιρετικό)', _name),
        const SizedBox(height: 12),
        _field('Τηλέφωνο επικοινωνίας (προαιρετικό)', _phone, max: 50),
        const SizedBox(height: 12),
        _fileActions(),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                'PNG/JPEG έως 10 MB · MP4/WebM έως 100 MB. Έως 5 αρχεία και 200 MB συνολικά. Δεν γίνεται αυτόματη καταγραφή.')),
        ..._files.asMap().entries.map((entry) => _localFile(entry.value,
            remove: _frozen
                ? null
                : () => _run(() async {
                      _files.removeAt(entry.key);
                      _dirty = true;
                      await _save();
                    }))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
              onPressed: _running || client.capabilities?['enabled'] != true
                  ? null
                  : () => _run(_submit),
              child: Text(
                  _frozen ? 'Επανάληψη ίδιας υποβολής' : 'Υποβολή αιτήματος')),
          if (_frozen)
            OutlinedButton(
                onPressed: _running ? null : () => _run(_recover),
                child: const Text('Έλεγχος υποβολής'))
          else
            OutlinedButton(
                onPressed: _running ? null : () => _run(_save),
                child: const Text('Αποθήκευση τοπικού προχείρου')),
          if (!_frozen)
            TextButton(
                onPressed: _running
                    ? null
                    : () => _run(() async {
                          await client.discardDraft();
                          _files = [];
                          _dirty = false;
                          _composing = false;
                        }),
                child: const Text('Απόρριψη προχείρου')),
        ]),
      ]));
  Widget _pendingFiles() {
    final row = client.draft;
    if (row?['request_id'] == null) return const SizedBox.shrink();
    final files = (row!['files'] as List).map(ticketMap).toList();
    final id = row['request_id'] as String;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Συνέχεια εκκρεμών συνημμένων',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                ...files
                    .asMap()
                    .entries
                    .map((entry) => _localFile(entry.value, index: entry.key)),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                      onPressed: _running ? null : () => _run(_upload),
                      child: const Text('Μεταφόρτωση συνημμένων')),
                  TextButton(
                      onPressed:
                          _running ? null : () => _run(() => _detailFor(id)),
                      child: const Text('Προβολή αντίστοιχου αιτήματος')),
                  TextButton(
                      onPressed: _running ? null : _stopPendingFiles,
                      child: const Text('Διακοπή εκκρεμών μεταφορτώσεων')),
                ]),
              ],
            )));
  }

  Widget _ticketDetails() {
    final data = _detail!,
        ticket = ticketMap(data['ticket']),
        id = _text(ticket, 'id');
    final closed = ['resolved', 'dismissed'].contains(ticket['status']);
    final events = (data['events'] as List).map(ticketMap);
    final files = (data['files'] as List).map(ticketMap);
    final reports = ((data['reports'] as List?) ?? []).map(ticketMap);
    final subject = _text(ticket, 'subject'),
        reference = _text(ticket, 'reference');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(reference, style: Theme.of(context).textTheme.labelLarge),
      Text(subject, style: Theme.of(context).textTheme.headlineSmall),
      Text(ticketStates[ticket['status']] ?? 'Άγνωστη κατάσταση'),
      const SizedBox(height: 12),
      SelectableText(_text(ticket, 'details')),
      const Divider(height: 32),
      const Text('Ιστορικό και απαντήσεις',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      if (_eventsNext != null)
        TextButton(
            onPressed:
                _running ? null : () => _run(() => _detailFor(id, more: true)),
            child: const Text('Παλαιότερη δραστηριότητα')),
      ...events.map((event) {
        final author = event['actor'] == 'support'
            ? 'Υποστήριξη'
            : event['actor'] == 'system'
                ? 'Ενημέρωση'
                : 'Πελάτης';
        final time = _stamp(event['created_at']);
        final body = _text(event, 'body');
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$author · $time',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      SelectableText(
                          body.isNotEmpty ? body : 'Ενημέρωση αιτήματος.'),
                      if (event['status'] != null)
                        Text(ticketStates[event['status']] ?? ''),
                    ])));
      }),
      if (files.isNotEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Συνημμένα',
                style: TextStyle(fontWeight: FontWeight.w600))),
      ...files.map((file) {
        final fileId = _text(file, 'id'), name = _text(file, 'filename');
        final expired = ['expired', 'removed'].contains(file['state']) ||
            file['expires_at'] != null &&
                (DateTime.tryParse(file['expires_at'])
                        ?.isBefore(DateTime.now()) ??
                    true);
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name),
                      Text(expired
                          ? 'Δεν είναι πλέον διαθέσιμο'
                          : file['state'] == 'ready'
                              ? 'Επιβεβαιωμένο συνημμένο'
                              : 'Εκκρεμεί μεταφόρτωση'),
                      if (file['expires_at'] != null)
                        Text('Διατήρηση έως ${_stamp(file['expires_at'])}'),
                      if (!expired && file['state'] == 'ready')
                        TextButton(
                            onPressed: _running
                                ? null
                                : () => _run(() async {
                                      final response = await client
                                          .request('/$id/files/$fileId');
                                      await widget.openMedia(
                                          checkedTicketMediaUrl(ticketMap(
                                                  response['signed_download'])[
                                              'url']));
                                    }),
                            child: const Text('Προεπισκόπηση / λήψη')),
                    ])));
      }),
      if (!closed) ...[const SizedBox(height: 12), _fileActions()],
      ...reports.map((report) => Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_text(report, 'title'),
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                        'Έκδοση ${_text(report, 'version')} · ${_stamp(report['created_at'])}'),
                    const SizedBox(height: 8),
                    SelectableText(_text(report, 'body')),
                    if (report['public_correction_reason'] != null)
                      Text(
                          'Διόρθωση: ${_text(report, 'public_correction_reason')}'),
                    ...((report['calls'] as List?) ?? []).map(ticketMap).map(
                        (call) => Text(
                            'Κλήση: ${_stamp(call['answered_at'])} → ${_stamp(call['ended_at'])}')),
                    ...((report['sessions'] as List?) ?? []).map(ticketMap).map(
                        (session) => Text(
                            'Συνεδρία: ${_stamp(session['started_at'])} → ${_stamp(session['ended_at'])}')),
                  ])))),
      const Divider(height: 32),
      if (closed)
        const Text('Το αίτημα έκλεισε. Το ιστορικό παραμένει διαθέσιμο.')
      else ...[
        TextField(
            controller: _reply,
            minLines: 3,
            maxLines: 5,
            maxLength: 4000,
            enabled: !_running && client.pendingReply == null,
            decoration: const InputDecoration(
                labelText: 'Νέα απάντηση', border: OutlineInputBorder())),
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
                onPressed: _running ? null : () => _run(_replyNow),
                child: Text(client.pendingReply == null
                    ? 'Αποστολή απάντησης'
                    : 'Επανάληψη ίδιας απάντησης'))),
      ],
    ]);
  }

  Widget _queue() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Τα αιτήματά σας',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          const Text('Δεν υπάρχουν αιτήματα σε αυτή την προβολή.'),
        SizedBox(
            height: 350,
            child: ListView(
                children: _items.map((item) {
              final id = _text(item, 'id'),
                  subject = _text(item, 'subject'),
                  reference = _text(item, 'reference');
              return ListTile(
                  selected: _selected == id && !_composing,
                  title: Text(subject),
                  subtitle: Text(
                      '$reference · ${ticketStates[item['status']] ?? ''}'),
                  onTap: _running
                      ? null
                      : () async {
                          try {
                            if (await _leaveCurrent() && mounted) {
                              await _run(() => _detailFor(id));
                            }
                          } catch (error) {
                            if (mounted) setState(() => _recordError(error));
                          }
                        });
            }).toList())),
        if (_next != null)
          TextButton(
              onPressed: _running ? null : () => _run(() => _list(more: true)),
              child: const Text('Περισσότερα αιτήματα')),
      ]);

  @override
  Widget build(BuildContext context) {
    final enabled = client.capabilities?['enabled'] == true;
    final contextInfo = client.capabilities?['context'] is Map
        ? ticketMap(client.capabilities!['context'])
        : <String, dynamic>{};
    final company = _text(contextInfo, 'customer_name'),
        site = _text(contextInfo, 'branch_name');
    return PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Exantas · Υποστήριξη'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                  onPressed: _close,
                  tooltip: 'Κλείσιμο υποστήριξης',
                  icon: const Icon(Icons.close)),
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (company.isNotEmpty && !_identityBlocked)
                        Text(site.isEmpty ? company : '$company · $site',
                            style: Theme.of(context).textTheme.titleMedium),
                      const Text(
                          'Περιγράψτε το πρόβλημα χωρίς τηλεφώνημα. Η υποβολή δεν ξεκινά απομακρυσμένη σύνδεση ή χρέωση.'),
                      const SizedBox(height: 12),
                      if (_error.isNotEmpty)
                        Semantics(
                            liveRegion: true,
                            child: Card(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_error)))),
                      if (_notice.isNotEmpty)
                        Semantics(
                            liveRegion: true,
                            child: Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_notice)))),
                      if (_running) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                            value: _total > 0 ? _sent / _total : null),
                        if (_stage.isNotEmpty)
                          Text('$_stage · Αρχείο ${_uploadIndex + 1}'),
                        if (_total > 0)
                          TextButton(
                              onPressed: () {
                                client.cancelled = true;
                              },
                              child: const Text('Διακοπή μεταφοράς')),
                      ],
                      if (!_identityBlocked) ...[
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                              onPressed: _running
                                  ? null
                                  : () async {
                                      try {
                                        if (await _leaveCurrent() && mounted) {
                                          await _run(_new);
                                        }
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() => _recordError(error));
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.add),
                              label: const Text('Νέο αίτημα')),
                          OutlinedButton.icon(
                              onPressed: _running
                                  ? null
                                  : () => _run(() async {
                                        await client.refreshCapabilities();
                                        if (client.capabilities?['enabled'] ==
                                            true) {
                                          await _list();
                                          if (_selected != null) {
                                            await _detailFor(_selected!);
                                          }
                                        }
                                      }),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Ανανέωση')),
                        ]),
                        if (!enabled)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                  'Η υπηρεσία δεν έχει επιβεβαιωθεί διαθέσιμη. Μπορείτε να κρατήσετε προστατευμένο τοπικό πρόχειρο. Η υποβολή απαιτεί σύνδεση με το Office.')),
                        if (enabled &&
                            client.capabilities?['notifications_enabled'] !=
                                true)
                          const Text(
                              'Οι ενημερώσεις email δεν είναι ενεργές. Το αίτημα και το ιστορικό παραμένουν διαθέσιμα.'),
                        if (client.pendingReply != null)
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                          'Εκκρεμεί επιβεβαίωση απάντησης. Η επανάληψη χρησιμοποιεί το ίδιο κείμενο και αριθμό.'),
                                      TextButton(
                                          onPressed: _running
                                              ? null
                                              : () => _run(() async {
                                                    final pending =
                                                        client.pendingReply!;
                                                    await client.reply(
                                                        pending['ticket_id'],
                                                        pending['body']);
                                                    await _detailFor(
                                                        pending['ticket_id']);
                                                  }),
                                          child: const Text(
                                              'Συνέχεια εκκρεμούς απάντησης')),
                                    ],
                                  ))),
                        _pendingFiles(),
                        const SizedBox(height: 20),
                        LayoutBuilder(builder: (context, constraints) {
                          final content = _composing
                              ? _composer()
                              : _detail != null
                                  ? _ticketDetails()
                                  : const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                          'Επιλέξτε προηγούμενο αίτημα ή δημιουργήστε νέο.'));
                          return constraints.maxWidth >= 850
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      SizedBox(width: 260, child: _queue()),
                                      const SizedBox(width: 24),
                                      Expanded(child: content)
                                    ])
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                      _queue(),
                                      const SizedBox(height: 20),
                                      content
                                    ]);
                        }),
                        const SizedBox(height: 20),
                        const Text(
                            'Τα πρωτότυπα παραμένουν στον υπολογιστή σας. Τα ιδιωτικά αντίγραφα διατηρούνται μετά το κλείσιμο: screenshots 12 μήνες, βίντεο 90 ημέρες. Το κείμενο και το ιστορικό παραμένουν χωριστά.'),
                      ],
                    ]),
              ),
      ),
    );
  }
}
