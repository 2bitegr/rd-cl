import 'dart:async';
import '../../common.dart' show gFFI;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/exantas_android_support.dart';
import '../../models/exantas_companion_model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../../desktop/widgets/exantas_account_settings.dart';
import 'home_page.dart';
import 'remote_page.dart';
import '../widgets/exantas_session_decision.dart';
import '../widgets/exantas_support_home_sections.dart';

class ExantasSupportPage extends StatefulWidget implements PageShape {
  const ExantasSupportPage({super.key});
  @override
  final title = 'Υποστήριξη';
  @override
  final icon = const Icon(Icons.support_agent);
  @override
  final List<Widget> appBarActions = const [];
  @override
  State<ExantasSupportPage> createState() => _ExantasSupportPageState();
}

class _ExantasSupportPageState extends State<ExantasSupportPage>
    with WidgetsBindingObserver {
  final support = ExantasAndroidSupport();
  final search = TextEditingController();
  final manual = TextEditingController();
  ExantasCompanionStatus? status;
  List<Map<String, dynamic>> customers = [],
      works = [],
      devices = [],
      pending = [];
  Map<String, dynamic>? customer, work;
  bool busy = false;
  String sourceId = '';
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gFFI.recentPeersModel.addListener(recentChanged);
    unawaited(run(refresh));
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!busy && mounted && ModalRoute.of(context)?.isCurrent == true)
        unawaited(run(refresh));
    });
  }

  @override
  void dispose() {
    gFFI.recentPeersModel.removeListener(recentChanged);
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    manual.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) unawaited(run(refresh));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    if (mounted)
      setState(() {
        busy = true;
        error = null;
      });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void recentChanged() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    sourceId = (await bind.mainGetMyId()).trim();
    await bind.mainLoadRecentPeers();
    final next = await support.service.loadStatus();
    if (next.officeUserId != status?.officeUserId ||
        next.companionToken != status?.companionToken ||
        next.apiBase != status?.apiBase) {
      customer = null;
      work = null;
      customers = [];
      works = [];
      devices = [];
      pending = [];
    }
    status = next;
    if (!next.technicianLoggedIn) return;
    try {
      await support.refresh();
    } finally {
      pending = await support.rows();
    }
  }

  Future<void> findCustomers() async {
    final result = await support.get(
        '/rustdesk-reports/customers?status=active&page_size=50&search=${Uri.encodeQueryComponent(search.text.trim())}');
    customers = maps(result['items']);
  }

  List<Map<String, dynamic>> maps(dynamic rows) => (rows as List? ?? [])
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  Future<void> selectCustomer(Map<String, dynamic> c) async {
    customer = c;
    work = null;
    devices = [];
    works = maps((await support
            .get('/support-workflow/items?customer_id=${c['id']}'))['items'])
        .where((w) => ['draft', 'review'].contains(w['support_state']))
        .toList();
  }

  Future<void> selectWork(Map<String, dynamic> w) async {
    final result = await support.get('/support-workflow/items/${w['id']}');
    if (result['permissions']?['can_edit'] != true)
      throw StateError('Δεν επιτρέπεται αλλαγή εργασίας.');
    work = Map<String, dynamic>.from(result['item'] as Map);
    devices =
        maps(result['devices']).where((d) => d['can_connect'] == true).toList();
  }

  Future<void> createWork() async {
    final c = customer;
    if (c == null) return;
    final title = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Νέα εργασία'),
                content: TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Περιγραφή')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Άκυρο')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, title.text.trim()),
                      child: const Text('Δημιουργία'))
                ]));
    title.dispose();
    if (value == null || value.isEmpty) return;
    final item = await support.createWork(c['id'] as String, value);
    // Recovery may return the original customer/work, never silently switch it.
    if (item['customer_id'] != c['id'])
      throw StateError(
          'Ανακτήθηκε η προηγούμενη εργασία. Ανοίξτε τον αρχικό πελάτη.');
    await selectCustomer(c);
    await selectWork(item);
  }

  Future<void> connectPeer(String peer, {Map<String, dynamic>? device}) async {
    FocusScope.of(context).unfocus();
    peer = normalizeAndroidPeerId(peer);
    await support.journal.load();
    await support.service.ensureNativeReady();
    final current = await support.service.loadStatus();
    if (!current.technicianLoggedIn || !current.nativeReady)
      throw StateError('Απαιτείται επιβεβαίωση RustDesk.');
    Map<String, dynamic>? selection;
    if (device != null) {
      final selected = work;
      if (selected == null) throw StateError('Επιλέξτε εργασία.');
      await selectWork(selected);
      if (!devices.any((d) => d['id'] == device['id'] && d['peer_id'] == peer))
        throw StateError('Ο υπολογιστής άλλαξε.');
      selection = {
        'peer_id': peer,
        'work_item_id': work!['id'],
        'revision': work!['revision'],
        'owner': current.officeUserId,
        'api': current.apiBase
      };
    }
    support.journal.mobileWork = selection;
    if (!mounted) return;
    final from = (await bind.mainGetMyId()).trim();
    Map<String, dynamic>? closure;
    stateGlobal.isInMainPage = false;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RemotePage(
              id: peer,
              onOfficeClosed: (event) {
                closure = {
                  ...event,
                  'owner': current.officeUserId,
                  'api': current.apiBase,
                  'from_peer': from
                };
              })));
    } finally {
      support.journal.mobileWork = null;
      stateGlobal.isInMainPage = true;
    }
    await refresh();
    if (mounted) {
      final candidates =
          pending.where((r) => androidClosureMatches(r, closure)).toList();
      // Missing native identity stays in the pending list, never target/time matching.
      if (candidates.length == 1) await completion(candidates.single);
    }
  }

  Future<void> associate(Map<String, dynamic> row) async {
    final w = work;
    if (w == null)
      throw StateError('Επιλέξτε πρώτα την κατάλληλη εργασία και υπολογιστή.');
    final context = await support.get('/support-workflow/items/${w['id']}');
    final candidates = maps(context['candidate_sessions']);
    if (!candidates.any((s) =>
        s['id'] == row['remote_session_id'] &&
        s['rustdesk_session_id'] == row['rustdesk_session_id'])) {
      throw StateError(
          'Δεν επιβεβαιώθηκε η ταυτότητα πελάτη. Αντιστοιχίστε τον υπολογιστή στο Office.');
    }
    final confirmed = await showDialog<bool>(
        context: this.context,
        builder: (ctx) => AlertDialog(
                title: const Text('Σύνδεση συνεδρίας με εργασία'),
                content: Text('${row['peer_id']} → ${w['title']}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Άκυρο')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Επιβεβαίωση'))
                ]));
    if (confirmed != true) return;
    await support.save(row, {
      'mobile_work': {
        'work_item_id': w['id'],
        'revision': context['item']['revision']
      }
    });
    await refresh();
  }

  Future<void> completion(Map<String, dynamic> row) async {
    final note =
        TextEditingController(text: row['draft_note'] as String? ?? '');
    final choice = await showDialog<String>(
        context: context,
        builder: (_) => ExantasSessionDecisionDialog(
            peerId: '${row['peer_id']}', note: note));
    final text = note.text.trim();
    note.dispose();
    await support.save(row, {'draft_note': text});
    if (choice == null || choice == 'later') {
      await support.later(row);
      return;
    }
    if (choice == 'ignore' && row['work_item_id'] == null) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Εξαίρεση πηγής από Office'),
                  content: Text(
                      'Απαιτείται διαχειριστής και αιτιολογία. Εξαιρούνται οι συνδέσεις από αυτό το τηλέφωνο προς ${row['peer_id']}, περιλαμβανομένων μελλοντικών συνδέσεων. Το audit διατηρείται.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Άκυρο')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Επιβεβαίωση εξαίρεσης πηγής'))
                  ]));
      if (confirmed == true) await support.excludeUnassigned(row, text);
      await refresh();
      return;
    }
    final reviewed = await support.preview(row, choice, text);
    final preview = reviewed['preview'] as Map;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Προεπισκόπηση Office'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${preview['body'] ?? ''}'),
                      Text(
                          'Πραγματικός χρόνος: ${preview['connection_seconds'] ?? 'εκκρεμεί'} δευτερόλεπτα'),
                      Text(
                          'Χρεώσιμος χρόνος: ${preview['billable_minutes'] ?? 'εκκρεμεί'} λεπτά'),
                      Text(
                          'Καθαρό: ${money(preview['net_minor'])}   ΦΠΑ: ${money(preview['vat_minor'])}'),
                      Text('Σύνολο: ${money(preview['gross_minor'])}'),
                      const Text(
                          'Η επιβεβαίωση αφορά ολόκληρη την εργασία και τις συνδεδεμένες συνεδρίες της. Δεν αποστέλλεται email.'),
                      if (preview['can_finalize'] != true)
                        const Text(
                            'Απαιτείται έλεγχος προειδοποιήσεων στο Office.'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Άκυρο')),
                  TextButton(
                      onPressed: preview['can_finalize'] == true
                          ? () => Navigator.pop(ctx, true)
                          : null,
                      child: const Text('Ρητή επιβεβαίωση ολοκλήρωσης'))
                ]));
    if (confirmed == true) await support.finalize(row, reviewed);
    await refresh();
  }

  String money(dynamic minor) {
    final n = num.tryParse('$minor');
    return n == null ? 'εκκρεμεί' : '${(n / 100).toStringAsFixed(2)} €';
  }

  Widget accountSettings() => ExantasAccountSettings(
      nativeRequired: true,
      loadStatus: () async {
        final s = await support.service.loadStatus();
        return ExantasAccountStatus(
            signedIn: s.technicianLoggedIn,
            name: s.technicianName,
            role: s.supportRole,
            nativeReady: s.nativeReady,
            legacySignedIn:
                bind.mainGetLocalOption(key: 'access_token').isNotEmpty);
      },
      login: (e, p) async {
        await support.service.loginTechnician(e, p);
        await run(refresh);
      },
      logout: () async {
        await support.service.logoutTechnician();
        await run(refresh);
      },
      confirmNative: () async {
        await support.service.ensureNativeReady(force: true);
        await run(refresh);
      },
      logoutLegacy: () =>
          gFFI.userModel.logOut(requireServerConfirmation: true));

  Future<void> openAccount() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
                child: accountSettings())));
    if (mounted) await run(refresh);
  }

  void copySourceId() {
    if (sourceId.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: sourceId)));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Το RustDesk ID αντιγράφηκε.')));
  }

  Widget customerPanel() => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Πελάτης και εργασία',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                onSubmitted: busy ? null : (_) => run(findCustomers),
                decoration: InputDecoration(
                    labelText: 'Αναζήτηση πελάτη',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.business_outlined),
                    suffixIcon: IconButton(
                        tooltip: 'Αναζήτηση πελάτη',
                        onPressed: busy ? null : () => run(findCustomers),
                        icon: const Icon(Icons.search)))),
            for (final c in customers)
              ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text('${c['company_name']}'),
                  selected: c['id'] == customer?['id'],
                  onTap: busy ? null : () => run(() => selectCustomer(c))),
            if (customer != null) ...[
              const SizedBox(height: 12),
              Text('Πελάτης: ${customer!['company_name']}'),
              TextButton.icon(
                  onPressed: busy ? null : () => run(createWork),
                  icon: const Icon(Icons.add),
                  label: const Text('Νέα εργασία')),
              for (final w in works)
                ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text('${w['title']}'),
                    subtitle: Text('${w['branch_name'] ?? ''}'),
                    selected: w['id'] == work?['id'],
                    onTap: busy ? null : () => run(() => selectWork(w))),
              if (work != null && devices.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'Δεν υπάρχουν διαθέσιμοι υπολογιστές για αυτή την εργασία.')),
            ],
            for (final d in devices)
              ListTile(
                  leading: const Icon(Icons.computer),
                  title: Text('${d['label'] ?? d['peer_id']}'),
                  subtitle: Text('${d['peer_id']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () =>
                          run(() => connectPeer('${d['peer_id']}', device: d))),
          ])));

  Widget pendingPanel() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pending.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Δεν υπάρχουν εκκρεμείς αποφάσεις συνεδριών.'))),
        for (final r in pending)
          Card(
              child: Column(children: [
            ListTile(
                leading: const Icon(Icons.pending_actions_outlined),
                title: Text('RustDesk ${r['peer_id']}'),
                subtitle: Text(r['work_item_id'] == null
                    ? 'Εκκρεμεί αντιστοίχιση ή audit'
                    : 'Εκκρεμεί απόφαση εργασίας'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => run(() => completion(r))),
            if (r['work_item_id'] == null)
              TextButton(
                  onPressed: busy ? null : () => run(() => associate(r)),
                  child: const Text('Σύνδεση με επιλεγμένη εργασία')),
            if (r['financial_operation'] != null)
              TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final recovered = await support.recover(r);
                            await refresh();
                            if (!recovered)
                              throw StateError(
                                  'Το προηγούμενο αίτημα παραμένει ανεπιβεβαίωτο. Δεν επαναλήφθηκε χρέωση.');
                          }),
                  child: const Text('Έλεγχος προηγούμενου αιτήματος')),
          ])),
      ]);

  @override
  Widget build(BuildContext context) {
    final signedIn = status?.technicianLoggedIn == true;
    final recent = gFFI.recentPeersModel.peers
        .where((p) {
          if (p.sameServer == false) return false;
          try {
            normalizeAndroidPeerId(p.id);
            return true;
          } on FormatException {
            return false;
          }
        })
        .map((p) => ExantasRecentDevice(
            id: p.id,
            label: p.alias.isNotEmpty ? p.alias : p.hostname,
            platform: p.platform,
            online: p.online))
        .toList();
    return ExantasSupportHome(
        key: ValueKey('${status?.officeUserId}:${status?.apiBase}'),
        account: signedIn
            ? ExantasAccountSummary(
                name: status!.technicianName,
                nativeReady: status!.nativeReady,
                sourceId: sourceId,
                onAccount: () => openAccount(),
                onCopyId: copySourceId)
            : Column(children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: accountSettings())),
                ListTile(
                    title: Text(sourceId.isEmpty
                        ? 'Το ID μου ετοιμάζεται…'
                        : 'Το ID μου: $sourceId'),
                    trailing: IconButton(
                        tooltip: 'Αντιγραφή RustDesk ID',
                        onPressed: sourceId.isEmpty ? null : copySourceId,
                        icon: const Icon(Icons.copy)))
              ]),
        signedIn: signedIn,
        nativeReady: status?.nativeReady == true,
        busy: busy,
        controller: manual,
        devices: recent,
        customerPanel: customerPanel(),
        pendingPanel: pendingPanel(),
        pendingCount: pending.length,
        error: [
          if (error != null) error!,
          if (support.journal.error != null) support.journal.error!
        ].join('\n').isEmpty
            ? null
            : [
                if (error != null) error!,
                if (support.journal.error != null) support.journal.error!
              ].join('\n'),
        onConnect: (id) => run(() => connectPeer(id)),
        onRefresh: () => run(refresh),
        onConfirmNative: () => run(() async {
              await support.service.ensureNativeReady(force: true);
              await refresh();
            }));
  }
}
