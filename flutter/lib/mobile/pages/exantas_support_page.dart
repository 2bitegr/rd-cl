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
import '../widgets/exantas_billing_preview.dart';
import '../widgets/exantas_connect_sheet.dart';
import '../widgets/exantas_pending_center.dart';
import '../../models/exantas_connect.dart';
import '../../models/exantas_pending.dart';
import '../ui/ex_confirm_dialog.dart';
import '../ui/ex_session_toolbar.dart';
import '../ui/ex_sheet.dart';
import '../ui/ex_list_row.dart';
import '../ui/exantas_theme.dart';
import '../widgets/exantas_support_home_sections.dart';
import '../widgets/exantas_work_screens.dart';
import '../../models/exantas_office_work.dart';

enum ExantasSupportView { home, work }

/// One controller serves both the Home and Work destinations: HomePage swaps
/// [view] on the same element, so Office state survives switching between them.
class ExantasSupportPage extends StatefulWidget implements PageShape {
  const ExantasSupportPage(
      {super.key, this.view = ExantasSupportView.home, this.onOpenWork});
  final ExantasSupportView view;
  final VoidCallback? onOpenWork;
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
  List<Map<String, dynamic>> works = [], devices = [], pending = [];
  late final ExantasOfficeWork office =
      ExantasOfficeWork((path) => support.get(path));
  Map<String, dynamic>? customer, work;
  bool busy = false;
  String sourceId = '';
  String? error;
  Timer? timer;
  ExantasWorkSection workSection = ExantasWorkSection.today;
  List<Map<String, dynamic>> creations = [];
  Set<String> favs = {};
  final connectFlight = ExantasSingleFlight();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gFFI.recentPeersModel.addListener(recentChanged);
    office.addListener(recentChanged);
    unawaited(run(refresh));
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!busy && mounted && ModalRoute.of(context)?.isCurrent == true)
        unawaited(run(refresh));
    });
  }

  @override
  void didUpdateWidget(ExantasSupportPage old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view && widget.view == ExantasSupportView.work) {
      loadSection(workSection);
    }
  }

  @override
  void dispose() {
    office.removeListener(recentChanged);
    office.dispose();
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
      works = [];
      devices = [];
      pending = [];
      // Account/API change or logout: drop cached Office work and in-flight
      // responses, and close any customer/work page of the previous account.
      office.reset();
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null) {
          Navigator.of(context).popUntil((r) => r == route);
        }
      }
    }
    status = next;
    if (!next.technicianLoggedIn) {
      office.reset();
      return;
    }
    try {
      await support.refresh();
    } finally {
      pending = await support.rows();
      creations = await support.creations();
    }
    try {
      favs = (await bind.mainGetFav()).map((e) => '$e').toSet();
    } catch (_) {
      favs = {};
    }
    if (widget.view == ExantasSupportView.work) loadSection(workSection);
  }

  void loadSection(ExantasWorkSection section) {
    if (status?.technicianLoggedIn != true) return;
    switch (section) {
      case ExantasWorkSection.today:
        unawaited(office.loadToday());
      case ExantasWorkSection.open:
        unawaited(office.loadOpen());
      case ExantasWorkSection.customers:
        unawaited(office.searchCustomers(search.text));
      case ExantasWorkSection.pending:
        break;
    }
  }

  void selectSection(ExantasWorkSection section) {
    setState(() => workSection = section);
    loadSection(section);
  }

  Set<String> get pendingWorkIds => {
        for (final r in pending)
          if (r['work_item_id'] is String) r['work_item_id'] as String
      };

  Future<void> openWorkDetail(OfficeWorkCard card) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OfficeWorkDetailPage(
              card: card,
              office: office,
              pending: pendingWorkIds.contains(card.id),
              onConnect: connectFromDetail)));

  Future<void> openCustomer(Map<String, dynamic> c) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OfficeCustomerPage(
              customer: c,
              office: office,
              pendingWorkIds: pendingWorkIds,
              onOpenWork: openWorkDetail,
              onNewWork: createWorkFor)));

  /// Connects through the same path as the previous work list: the selected
  /// work and device are re-validated against Office inside [connectPeer].
  Future<void> connectFromDetail(WorkDetail detail, WorkDevice device) async {
    if (busy) throw StateError('Υπάρχει άλλη ενέργεια σε εξέλιξη.');
    setState(() => busy = true);
    try {
      customer = null;
      work = Map<String, dynamic>.from(detail.rawItem);
      await connectPeer(device.peerId,
          workId: detail.id, customerId: detail.customerId);
    } finally {
      work = null;
      if (mounted) setState(() => busy = false);
    }
  }

  /// Existing creation flow (dialog + idempotent recovery) for [c].
  Future<OfficeWorkCard?> createWorkFor(Map<String, dynamic> c) async {
    if (busy) throw StateError('Υπάρχει άλλη ενέργεια σε εξέλιξη.');
    setState(() => busy = true);
    try {
      customer = c;
      work = null;
      await createWork();
      final created = work;
      work = null;
      return created == null ? null : OfficeWorkCard.fromFlat(created);
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    final value = await showExSheet<String>(
        context: context,
        builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Νέα εργασία',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ExantasTokens.space3),
              TextField(
                  controller: title,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                  decoration: const InputDecoration(labelText: 'Περιγραφή')),
              const SizedBox(height: ExantasTokens.space4),
              FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(ExantasTokens.minTouch)),
                  onPressed: () => Navigator.pop(ctx, title.text.trim()),
                  child: const Text('Δημιουργία')),
              const SizedBox(height: ExantasTokens.space2),
              TextButton(
                  style: TextButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(ExantasTokens.minTouch)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Άκυρο')),
            ]));
    // The sheet's exit animation may still read the controller.
    Future<void>.delayed(const Duration(milliseconds: 600), title.dispose);
    if (value == null || value.isEmpty) return;
    final item = await support.createWork(c['id'] as String, value);
    // Recovery may return the original customer/work, never silently switch it.
    if (item['customer_id'] != c['id'])
      throw StateError(
          'Ανακτήθηκε η προηγούμενη εργασία. Ανοίξτε τον αρχικό πελάτη.');
    await selectCustomer(c);
    await selectWork(item);
  }

  /// Home / recent entry: an explicit sheet decides work vs no work. A
  /// dismissed sheet connects nothing; no earlier selection is reused.
  Future<void> startConnect(String raw) async {
    if (busy) return;
    await connectFlight.run(() async {
      final String peer;
      try {
        peer = normalizeAndroidPeerId(raw);
      } on FormatException {
        if (mounted) setState(() => error = 'Μη έγκυρο RustDesk ID. Ελέγξτε το και δοκιμάστε ξανά.');
        return;
      }
      if (mounted) setState(() => error = null);
      FocusScope.of(context).unfocus();
      try {
        await office.loadOpen().timeout(const Duration(seconds: 4));
      } catch (_) {}
      if (!mounted) return;
      final open = office.open.items
          .where((c) => ['draft', 'review'].contains(c.supportState))
          .map((c) => ExantasWorkOption(id: c.id, title: c.title, customerName: c.customerName))
          .toList();
      final choice = await showExantasConnectSheet(context,
          peerId: peer,
          openWorks: open,
          loadSuggestions: () => suggestionsFor(peer, open));
      if (choice == null || !mounted) return;
      if (busy) {
        // Never drop an explicit choice silently.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Υπάρχει άλλη ενέργεια σε εξέλιξη. Δοκιμάστε ξανά.')));
        return;
      }
      await run(() => connectPeer(peer, workId: choice.workId));
    });
  }

  /// Own open work whose customer lists [peer] as a connectable device.
  /// Evidence only: the result is shown, never selected.
  Future<List<ExantasWorkOption>> suggestionsFor(String peer, List<ExantasWorkOption> open) async {
    final contexts = <Map<String, dynamic>>[];
    await Future.wait(open.take(10).map((w) async {
      try {
        contexts.add(await support.get('/support-workflow/items/${Uri.encodeComponent(w.id)}'));
      } catch (_) {}
    }));
    final ids = suggestWorkIds(peer, contexts).toSet();
    return open.where((w) => ids.contains(w.id)).toList();
  }

  Future<void> connectPeer(String peer, {String? workId, String? customerId}) async {
    FocusScope.of(context).unfocus();
    peer = normalizeAndroidPeerId(peer);
    await support.journal.load();
    await support.service.ensureNativeReady();
    final current = await support.service.loadStatus();
    if (!current.technicianLoggedIn || !current.nativeReady)
      throw StateError('Απαιτείται επιβεβαίωση RustDesk.');
    Map<String, dynamic>? selection;
    String? contextLabel;
    if (workId != null) {
      // Fresh revision and permissions immediately before connecting.
      final context = await support.get('/support-workflow/items/${Uri.encodeComponent(workId)}');
      final check = evaluateWorkConnect(context,
          peer: peer,
          owner: current.officeUserId,
          api: current.apiBase,
          expectedWorkId: workId,
          expectedCustomerId: customerId);
      if (!check.ok) throw StateError(check.reason!);
      selection = check.selection;
      work = Map<String, dynamic>.from(context['item'] as Map);
      contextLabel = ExSessionContext.fromWorkContext(context, peer);
    }
    if (!mounted) return;
    final from = (await bind.mainGetMyId()).trim();
    if (!mounted) return;
    Map<String, dynamic>? closure;
    stateGlobal.isInMainPage = false;
    unawaited(HapticFeedback.lightImpact());
    // Bind and clear in one try/finally set right before the push: a throw or
    // dispose can never leave the work bound to a later scan/URL connection.
    try {
      support.journal.mobileWork = selection;
      // Chip only for an explicitly bound work; unbound connections show none.
      ExSessionContext.label.value = selection == null ? null : contextLabel;
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
      ExSessionContext.label.value = null;
      // A leftover page-level work must never be reused by later actions.
      work = null;
      stateGlobal.isInMainPage = true;
    }
    unawaited(HapticFeedback.lightImpact());
    await refresh();
    if (!mounted) return;
    // No blocking dialog: the session is already saved as «Αργότερα».
    final candidates =
        pending.where((r) => androidClosureMatches(r, closure)).toList();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(exantasSessionSavedSnackBar(onDecide: () {
      if (candidates.length == 1) {
        unawaited(run(() => completion(candidates.single)));
      } else {
        openWork(ExantasWorkSection.pending);
      }
    }));
  }

  Future<void> toggleFavorite(String id) async {
    try {
      final list = (await bind.mainGetFav()).map((e) => '$e').toList();
      if (!list.remove(id)) list.add(id);
      await bind.mainStoreFav(favs: list);
      favs = list.toSet();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'Δεν αποθηκεύτηκε η καρφίτσα: $e');
    }
  }

  /// Explicit pick of one of the user's open works for [row]. Never reuses a
  /// page-level selection left over from an earlier connect.
  Future<ExantasWorkOption?> pickWorkFor(Map<String, dynamic> row) async {
    try {
      await office.loadOpen().timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (!mounted) return null;
    final cid = row['customer_id'];
    final open = office.open.items
        .where((c) => ['draft', 'review'].contains(c.supportState))
        .toList();
    final sameCustomer = cid == null
        ? open
        : open.where((c) => c.customerId == '$cid').toList();
    final options = (sameCustomer.isEmpty ? open : sameCustomer)
        .map((c) => ExantasWorkOption(
            id: c.id, title: c.title, customerName: c.customerName))
        .toList();
    if (options.isEmpty) {
      throw StateError('Δεν υπάρχει ανοιχτή εργασία για αντιστοίχιση.');
    }
    return showExSheet<ExantasWorkOption>(
        context: context,
        builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Επιλέξτε εργασία για ${row['peer_id']}',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ExantasTokens.space2),
              for (final o in options)
                ExListRow(
                    key: ValueKey('associate-${o.id}'),
                    title: o.title,
                    subtitle: o.customerName,
                    icon: Icons.work_outline,
                    onTap: () => Navigator.pop(ctx, o)),
            ]));
  }

  Future<void> associate(Map<String, dynamic> row) async {
    final picked = await pickWorkFor(row);
    if (picked == null) return;
    final fresh = await support.get('/support-workflow/items/${Uri.encodeComponent(picked.id)}');
    if (fresh['permissions']?['can_edit'] != true ||
        !['draft', 'review'].contains(fresh['item']?['support_state'])) {
      throw StateError('Η εργασία δεν είναι ανοιχτή ή δεν επιτρέπεται αλλαγή.');
    }
    final w = Map<String, dynamic>.from(fresh['item'] as Map);
    final context = await support.get('/support-workflow/items/${w['id']}');
    final candidates = maps(context['candidate_sessions']);
    if (!candidates.any((s) =>
        s['id'] == row['remote_session_id'] &&
        s['rustdesk_session_id'] == row['rustdesk_session_id'])) {
      throw StateError(
          'Δεν επιβεβαιώθηκε η ταυτότητα πελάτη. Αντιστοιχίστε τον υπολογιστή στο Office.');
    }
    final confirmed = await showExConfirmDialog(this.context,
        title: 'Σύνδεση συνεδρίας με εργασία',
        message:
            '${row['peer_id']} → ${picked.customerName.isEmpty ? '' : '${picked.customerName} · '}${w['title']}');
    if (!confirmed) return;
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
    final choice = await showExantasDecisionSheet(context,
        peerId: '${row['peer_id']}', note: note);
    final text = note.text.trim();
    // The sheet's exit animation may still read the controller.
    Future<void>.delayed(const Duration(milliseconds: 600), note.dispose);
    // Closed without a decision: nothing is saved or sent.
    if (choice == null) return;
    await support.save(row, {'draft_note': text});
    if (choice == 'later') {
      await support.later(row);
      unawaited(HapticFeedback.lightImpact());
      return;
    }
    if (choice == 'ignore' && row['work_item_id'] == null) {
      final current = await support.service.loadStatus();
      if (current.supportRole != 'admin')
        throw StateError('Η εξαίρεση πηγής απαιτεί διαχειριστή Office.');
      if (text.isEmpty)
        throw StateError('Γράψτε αιτιολογία στην περιγραφή για την εξαίρεση πηγής.');
      if (!mounted) return;
      final confirmed = await showExConfirmDialog(context,
          title: 'Εξαίρεση πηγής από Office',
          message:
              'Εξαιρούνται οι συνδέσεις από αυτό το τηλέφωνο προς ${row['peer_id']}, '
              'περιλαμβανομένων μελλοντικών συνδέσεων που δεν έχουν ακόμη γίνει. '
              'Το audit διατηρείται. Αιτιολογία: $text',
          confirmLabel: 'Επιβεβαίωση εξαίρεσης πηγής',
          destructive: true);
      if (confirmed) {
        await support.excludeUnassigned(row, text);
        unawaited(HapticFeedback.lightImpact());
      }
      await refresh();
      return;
    }
    final reviewed = await support.preview(row, choice, text);
    if (!mounted) return;
    final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
            builder: (_) => ExantasBillingPreviewPage(reviewed: reviewed)));
    if (confirmed == true) {
      await support.finalize(row, reviewed);
      unawaited(HapticFeedback.lightImpact());
    }
    await refresh();
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
            nativeRecoveryRequired: s.nativeConfirmationRequired,
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
    await showExSheet<void>(
        context: context,
        builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Λογαριασμός Office',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ExantasTokens.space3),
              accountSettings(),
            ]));
    if (mounted) await run(refresh);
  }

  void copySourceId() {
    if (sourceId.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: sourceId)));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Το RustDesk ID αντιγράφηκε.')));
  }

  void openWork(ExantasWorkSection section) {
    setState(() => workSection = section);
    widget.onOpenWork?.call();
  }

  void searchFromHome(String query) {
    openWork(ExantasWorkSection.customers);
    unawaited(office.searchCustomers(query));
  }

  Widget todayPanel() => OfficeWorkFeedPanel(
      feed: office.today,
      pendingWorkIds: pendingWorkIds,
      onOpen: openWorkDetail,
      onRetry: () => unawaited(office.loadToday()),
      emptyTitle: ExWork.noToday,
      emptyMessage: ExWork.noTodayHint);

  Widget openPanel() => OfficeWorkFeedPanel(
      feed: office.open,
      pendingWorkIds: pendingWorkIds,
      onOpen: openWorkDetail,
      onRetry: () => unawaited(office.loadOpen()),
      onMore: () => unawaited(office.loadOpen(more: true)),
      emptyTitle: ExWork.noOpen);

  Widget customerPanel() => OfficeCustomersPanel(
      controller: search,
      feed: office.customers,
      onSearch: (q) => unawaited(office.searchCustomers(q)),
      onOpen: openCustomer);

  List<PendingItem> get pendingItems =>
      classifyPendingRows([...pending, ...creations]);

  Future<void> pendingAction(PendingItem item) async {
    final r = item.row;
    switch (item.action) {
      case PendingAction.refresh:
        await refresh();
      case PendingAction.associate:
        await associate(r);
      case PendingAction.decide:
        await completion(r);
      case PendingAction.checkRequest:
        if (item.isCreation) {
          await support.createWork(r['customer_id'] as String, '');
          await refresh();
          return;
        }
        final recovered = await support.recover(r);
        await refresh();
        if (!recovered)
          throw StateError(
              'Το προηγούμενο αίτημα παραμένει ανεπιβεβαίωτο. Δεν επαναλήφθηκε χρέωση.');
      case PendingAction.openOffice:
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Ελέγξτε την εργασία στο Office. Από το κινητό δεν γίνεται άλλη ενέργεια.')));
    }
  }

  Future<void> abandonPending(PendingItem item) async {
    final confirmed = await showExConfirmDialog(context,
        title: 'Ακύρωση εκκρεμούς αιτήματος',
        message:
            'Το Office δεν έχει καταγράψει το αίτημα. Θα αφαιρεθεί μόνο η τοπική εκκρεμότητα και η επόμενη ολοκλήρωση θα απαιτήσει νέα προεπισκόπηση και νέο κλειδί. Το παλιό αίτημα δεν θα σταλεί ξανά.',
        confirmLabel: 'Ακύρωση αιτήματος',
        destructive: true);
    if (!confirmed) return;
    final cleared = item.isCreation
        ? await support.abandonCreation(item.row)
        : await support.abandon(item.row);
    await refresh();
    if (!cleared)
      throw StateError('Το Office απάντησε για το αίτημα. Δεν ακυρώθηκε.');
  }

  Widget pendingPanel() => ExantasPendingList(
      items: pendingItems,
      now: DateTime.now(),
      busy: busy,
      onAction: (i) => unawaited(run(() => pendingAction(i))),
      onAbandon: (i) => unawaited(run(() => abandonPending(i))));

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
            online: p.online,
            pinned: favs.contains(p.id)))
        .toList();
    final errorText = [
      if (error != null) error!,
      if (support.journal.error != null) support.journal.error!
    ].join('\n');
    final viewKey = ValueKey('${status?.officeUserId}:${status?.apiBase}');
    if (widget.view == ExantasSupportView.work) {
      return ExantasWorkView(
          key: viewKey,
          signedIn: signedIn,
          busy: busy,
          section: workSection,
          onSection: selectSection,
          todayPanel: todayPanel(),
          openPanel: openPanel(),
          customerPanel: customerPanel(),
          pendingPanel: pendingPanel(),
          pendingCount: pendingItems.length,
          error: errorText.isEmpty ? null : errorText,
          onRefresh: () => run(refresh));
    }
    return ExantasSupportHome(
        key: viewKey,
        account: signedIn
            ? ExantasAccountSummary(
                name: status!.technicianName,
                nativeRecoveryRequired: status!.nativeConfirmationRequired,
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
        nativeRecoveryRequired: status?.nativeConfirmationRequired == true,
        busy: busy,
        controller: manual,
        searchController: search,
        devices: recent,
        pendingCount: pendingItems.length,
        pendingSummary: pendingSummary(pendingItems),
        pinnedIds: favs,
        onTogglePin: (id) => unawaited(toggleFavorite(id)),
        error: errorText.isEmpty ? null : errorText,
        onConnect: (id) => unawaited(startConnect(id)),
        onSearchCustomers: searchFromHome,
        onOpenPending: () => openWork(ExantasWorkSection.pending),
        onRefresh: () => run(refresh),
        onConfirmNative: () => run(() async {
              await support.service.ensureNativeReady(force: true);
              await refresh();
            }));
  }
}
