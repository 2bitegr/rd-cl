import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/exantas_android_support.dart';
import 'package:flutter_hbb/models/exantas_companion_model.dart';
import 'package:flutter_hbb/models/exantas_lifecycle_outbox.dart';
import 'package:flutter_hbb/models/exantas_lifecycle_queue.dart';
import 'package:flutter_hbb/models/exantas_session_report.dart';

class MemoryJournal extends ExantasLifecycleOutbox {
  final writes = <Map<String, dynamic>>[];
  late final _queue = ExantasLifecycleQueue(save: (r) async => writes.add({...r}), send: (_) async => {});
  @override ExantasLifecycleQueue get queue => _queue;
  @override Future<void> load() async {}
}
class OfficeFixture extends ExantasCompanionService {
  String actor = 'technician-a', role = 'technician';
  int claims = 0;
  bool lost = false, applied = false, denied = false, completedInOffice = false;
  int posts = 0;
  Map<String, dynamic>? createdItem;
  final requests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> sessions = [];
  ExantasWorkContext? context;
  Map<String, dynamic> source = {'id': 'remote', 'started_at': '2026-10-30T10:00:00Z',
    'ended_at': '2026-10-30T10:02:00Z', 'duration_seconds': 120, 'timing_quality': 'verified'};
  @override Future<ExantasCompanionStatus> loadStatus() async => ExantasCompanionStatus(
    apiBase: 'https://office.invalid/api/v1', enrolled: false, technicianLoggedIn: !denied,
    deviceToken: '', companionToken: 'synthetic-$actor', customerName: '', technicianName: '',
    supportRole: role, policy: {}, officeUserId: actor);
  @override Future<List<Map<String, dynamic>>> pendingSessions({bool includeLegacyQueue = false, bool includeWorkflowSessions = false}) async => sessions;
  @override Future<ExantasWorkContext?> lookupWorkContext({required String peerId, required String fromPeer,
    String? rustDeskSessionId, ExantasWorkflowCapabilities? capabilities}) async => context;
  @override Future<Map<String, dynamic>> androidOfficeRequest(String path, {Map<String, dynamic>? body, String? expectedOwner, String? expectedApi}) async {
    if (denied) throw StateError('revoked');
    if (body != null) { posts++; requests.add({...body}); }
    if (path.endsWith('/items') && body != null) {
      createdItem = {'id': 'work', 'customer_id': body['customer_id']}; applied = true;
      if (lost) { throw StateError('lost creation response'); }
      return result();
    }
    if (path.endsWith('/exclusions')) { return {'status': 'ok', 'exclusion': {'peer_id': body!['peer_id'], 'from_peer': body['from_peer']}}; }
    if (path.endsWith('/finalize')) { applied = true; if (lost) throw StateError('lost response'); return result(); }
    if (path.contains('/requests/')) return {'request': {'state': applied ? 'applied' : 'not_found', 'result': applied ? result() : null}};
    if (path.endsWith('/preview')) return {'preview': {'revision': '3', 'preview_hash': 'server-only-hash',
      'billing_mode': body!['billing_mode'], 'can_finalize': true, 'net_minor': 3333, 'vat_minor': 800, 'gross_minor': 4133}};
    return {'item': {'id': 'work', 'support_state': completedInOffice ? 'finalized' : 'draft'},
      if (completedInOffice) 'current_report': {'id': 'published-report'}, 'activities': {'sessions': [source]}, 'permissions': {'can_finalize': true}};
  }
  @override Future<ExantasWorkContext> claimWorkContext({required String workItemId, required String remoteSessionId,
    required String expectedRevision, required String idempotencyKey, required String expectedOfficeUserId, required String expectedApiBase}) async {
    claims++; expect(workItemId, 'work'); expect(remoteSessionId, 'remote'); expect(expectedOfficeUserId, actor);
    context = ExantasWorkContext(classification: ExantasWorkContextClassification.bound,
      workItemId: workItemId, workRevision: '4', remoteSessionId: remoteSessionId, suppressLegacy: true);
    return context!;
  }
  Map<String, dynamic> result() => {'status': 'ok', 'item': createdItem ?? {'id': 'work', 'support_state': 'finalized'}};
}
Map<String, dynamic> row() => {'event_id': 'local-1', 'local_session': 'local-1', 'owner': 'technician-a',
  'api': 'https://office.invalid/api/v1', 'from_peer': 'phone', 'peer_id': 'target',
  'rustdesk_session_id': '18446744073709551615', 'work_item_id': 'work', 'remote_session_id': 'remote', 'decision': 'later'};
void main() {
  late MemoryJournal journal; late OfficeFixture office; late ExantasAndroidSupport support;
  setUp(() { journal = MemoryJournal(); office = OfficeFixture();
    support = ExantasAndroidSupport(service: office, journal: journal, sourcePeer: () async => 'phone');
    journal.queue.records['local-1'] = row(); });
  test('manual and known PCs accept RustDesk custom IDs without overriding the configured server', () {
    expect(normalizeAndroidPeerId('123 456 789'), '123456789');
    expect(normalizeAndroidPeerId('Office_PC-01'), 'Office_PC-01');
    expect(normalizeAndroidPeerId('pc_πελάτης'), 'pc_πελάτης');
    for (final invalid in ['', 'pc@another-server', 'https://another-server', '192.168.1.10', '127.0.0.1', '[::1]', 'host.example:21118', 'pc\nother', 'x' * 129]) {
      expect(() => normalizeAndroidPeerId(invalid), throwsFormatException);
    }
  });
  test('completion uses exact native source tuple, never a sole pending row for the same target', () {
    final close = {...row()}; expect(androidClosureMatches(row(), close), true);
    for (final key in ['owner', 'api', 'from_peer', 'peer_id', 'rustdesk_session_id']) {
      expect(androidClosureMatches(row(), {...close, key: 'different'}), false);
    }
    expect(androidClosureMatches(row(), {...close, 'rustdesk_session_id': '0'}), false);
    expect(androidClosureMatches(row(), null), false);
  });
  test('later persists pending decision and never invokes billing', () async {
    await support.later(row()); expect(journal.queue.records['local-1']!['decision'], 'later'); expect(office.posts, 0);
  });
  test('unknown or incomplete provider evidence never becomes zero duration', () async {
    for (final change in [{'ended_at': null}, {'timing_quality': 'unverified'}, {'duration_seconds': null}, {'duration_seconds': 0}]) {
      office.source = {...office.source, ...change};
      await expectLater(support.preview(row(), 'free', 'synthetic work'), throwsStateError);
    }
    expect(office.posts, 0);
  });
  test('billing, free and exclusion delegate mode and preview to Office without price calculation', () async {
    for (final mode in ['automatic', 'free', 'ignore']) {
      final reviewed = await support.preview(row(), mode, mode == 'ignore' ? '' : 'synthetic work');
      expect(reviewed['preview']['net_minor'], 3333); expect(office.requests.last['billing_mode'], mode);
      expect(office.requests.last.containsKey('net_minor'), false); expect(office.requests.last['send_email'], false);
    }
  });
  test('lost financial response persists original key; recovery performs only GET after restart', () async {
    final preview = await support.preview(row(), 'automatic', 'synthetic work'); office.lost = true;
    await expectLater(support.finalize(row(), preview), throwsStateError);
    final operation = journal.queue.records['local-1']!['financial_operation'] as Map;
    expect(operation['key'], office.requests.last['idempotency_key']); expect(office.posts, 2);
    final restarted = ExantasAndroidSupport(service: office, journal: journal, sourcePeer: () async => 'phone');
    await expectLater(restarted.finalize(row(), preview), throwsStateError); expect(office.posts, 2);
    expect(await restarted.recover(row()), true); expect(office.posts, 2);
    expect(journal.queue.records['local-1']!['decision'], 'completed');
  });
  test('not-found recovery remains pending and cannot silently allow a second charge', () async {
    await support.save(row(), {'financial_operation': {'key': 'original', 'work_item_id': 'work'}});
    expect(await support.recover(row()), false); expect(journal.queue.records['local-1']!['financial_operation'], isNotNull);
    await expectLater(support.preview(row(), 'automatic', 'work'), throwsStateError); expect(office.posts, 0);
  });
  test('account switch or permission revocation blocks finalization without an operation', () async {
    office.actor = 'technician-b'; await expectLater(support.preview(row(), 'free', 'work'), throwsStateError);
    office.actor = 'technician-a'; office.denied = true;
    await expectLater(support.preview(row(), 'free', 'work'), throwsStateError); expect(office.posts, 0);
  });
  test('manual peer without exact association stays pending', () async {
    office.context = const ExantasWorkContext(classification: ExantasWorkContextClassification.pendingIdentity,
      workItemId: null, workRevision: null, remoteSessionId: null, suppressLegacy: true);
    journal.queue.records['local-1']!.remove('work_item_id');
    await support.refresh(); expect(journal.queue.records.length, 1);
    expect(journal.queue.records['local-1']!['work_item_id'], isNull); expect(office.posts, 0);
  });
  test('selected work claims only exact audited session and never creates a second link on refresh', () async {
    journal.queue.records['local-1']!['mobile_work'] = {'work_item_id': 'work', 'revision': '3'};
    office.context = const ExantasWorkContext(classification: ExantasWorkContextClassification.unassigned,
      workItemId: null, workRevision: null, remoteSessionId: 'remote', suppressLegacy: true);
    await support.refresh(); await support.refresh(); expect(office.claims, 1);
    expect(journal.queue.records['local-1']!['work_item_id'], 'work');
  });
  test('later completed in Office resolves only through the exact linked published report', () async {
    office.context = const ExantasWorkContext(classification: ExantasWorkContextClassification.bound,
      workItemId: 'work', workRevision: '4', remoteSessionId: 'remote', suppressLegacy: true);
    office.completedInOffice = true;
    await support.refresh(); expect(journal.queue.records['local-1']!['decision'], 'completed');
    expect(await support.rows(), isEmpty); expect(office.posts, 0);
  });
  test('unassigned personal source exclusion uses current admin workflow and exact source pair', () async {
    final r = row()..remove('work_item_id'); journal.queue.records['local-1'] = r;
    await expectLater(support.excludeUnassigned(r, 'synthetic test'), throwsStateError); expect(office.posts, 0);
    office.role = 'admin'; await support.excludeUnassigned(r, 'synthetic test');
    expect(office.requests.single['from_peer'], 'phone'); expect(office.requests.single['peer_id'], 'target');
    expect(journal.queue.records['local-1']!['decision'], 'excluded');
  });
  test('lost work creation response is recovered without another work POST', () async {
    office.lost = true;
    await expectLater(support.createWork('customer', 'synthetic'), throwsStateError); expect(office.posts, 1);
    final recovered = await support.createWork('customer', 'different title');
    expect(recovered['id'], 'work'); expect(office.posts, 1);
  });
  test('foreign work identity cannot consume the selected customer work', () async {
    journal.queue.records['local-1']!['mobile_work'] = {'work_item_id': 'work', 'revision': '3'};
    office.context = const ExantasWorkContext(classification: ExantasWorkContextClassification.bound,
      workItemId: 'foreign-work', workRevision: '4', remoteSessionId: 'remote', suppressLegacy: true);
    await expectLater(support.refresh(), throwsStateError); expect(office.claims, 0); expect(office.posts, 0);
  });
  test('another technician journal remains retained and invisible to the current technician', () async {
    journal.queue.records['other'] = {...row(), 'event_id': 'other', 'owner': 'technician-b'};
    expect((await support.rows()).length, 1); expect(journal.queue.records.length, 2);
  });
  test('duplicate provider events deduplicate by exact source and separate reconnect IDs', () async {
    office.sessions = [for (final id in ['18446744073709551615', '18446744073709551615', '18446744073709551614'])
      {'id': id.endsWith('15') ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222',
        'rustdesk_session_id': id, 'from_peer': 'phone', 'peer_id': 'target', 'technician_admin_id': 'technician-a'}];
    await support.refresh(); await support.refresh(); expect(journal.queue.records.length, 2);
    expect((await support.rows()).length, 2);
  });
}
