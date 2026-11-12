// Invoked only by the owned Office HTTPS fixture; never uses installed auth.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_hbb/models/exantas_customer_ticket.dart';
import 'package:flutter_hbb/models/exantas_customer_ticket_proxy.dart';

class DriverStore extends ExantasTicketStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> next) async {
    value = ticketMap(jsonDecode(jsonEncode(next)));
  }
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  check(args.length == 1, 'Owned fixture path required');
  final meta = ticketMap(jsonDecode(await File(args.single).readAsString()));
  check(meta['owner'] == 'customer-tickets-20261112', 'Fixture owner mismatch');
  final uri = Uri.parse(meta['api']);
  check(
      uri.scheme == 'https' &&
          uri.host == '127.0.0.1' &&
          uri.path == '/api/v1' &&
          uri.port > 1024,
      'Loopback HTTPS fixture required');
  final identity =
      ExantasTicketIdentity(meta['api'], meta['device_id'], meta['bearer']);
  final untrusted = ExantasTicketHttpTransport();
  var rejected = false;
  try {
    await untrusted.request(identity, 'GET', '/capabilities');
  } catch (_) {
    rejected = true;
  } finally {
    untrusted.close();
  }
  check(rejected,
      'Default transport must reject an untrusted fixture certificate');
  ExantasTicketTransport trusted([List<String>? settings]) {
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(meta['certificate']);
    final http = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 15);
    if (settings != null) {
      ExantasTicketProxy.fromSettings(settings, context: context)!
          .configure(http);
    }
    return ExantasTicketHttpTransport(client: http);
  }

  final store = DriverStore();
  ExantasCustomerTicketClient create() => ExantasCustomerTicketClient(
      identity: identity,
      current: () async => identity,
      store: store,
      transport: trusted());
  var client = create();
  await client.refreshCapabilities();
  final file = await inspectTicketFile(meta['image']);
  await client.saveDraft({
    'category': 'problem',
    'priority': 'normal',
    'subject': 'Native HTTPS fixture',
    'details': 'Synthetic native customer support'
  }, [
    file
  ]);
  try {
    await client.submit();
  } catch (_) {/* The fixture drops the committed ACK. */}
  await client.dispose();
  client = create();
  await client.load();
  final recovered = await client.recoverCreate();
  check(recovered != null, 'Committed request not recovered');
  final id = client.draft!['request_id'] as String;
  await client.uploadPending();
  check(client.draft!['files'][0]['ready'] == true, 'File confirmation absent');
  await client.finishDraft();
  check(client.draft == null, 'Completed draft not retired');
  try {
    await client.reply(id, 'Native HTTPS public reply');
  } catch (_) {/* Deliberate lost reply ACK. */}
  if (client.pendingReply != null) {
    await client.dispose();
    client = create();
    await client.load();
    await client.reply(id, 'Native HTTPS public reply');
  }
  await client.dispose();
  final verified = <String>[], anonymous = <String>[];
  for (final raw in meta['proxies'] as List) {
    final proxy = ticketMap(raw),
        settings = List<String>.from(proxy['settings']);
    client = ExantasCustomerTicketClient(
        identity: identity,
        current: () async => identity,
        store: store,
        transport: trusted(settings));
    await client.refreshCapabilities();
    await client.stageFiles(id, [await inspectTicketFile(meta['image'])]);
    await client.uploadPending();
    await client.finishDraft();
    await client.dispose();
    verified.add(proxy['scheme']);
    final noAuth = [settings[0], '', ''];
    final anonymousTransport = trusted(noAuth);
    await anonymousTransport.request(identity, 'GET', '/capabilities');
    anonymousTransport.close();
    anonymous.add(proxy['scheme']);
  }
  final first = List<String>.from(meta['proxies'][0]['settings']);
  first[2] = 'wrong-synthetic-password';
  final denied = trusted(first);
  var deniedAuth = false;
  try {
    await denied.request(identity, 'GET', '/capabilities');
  } catch (_) {
    deniedAuth = true;
  } finally {
    denied.close();
  }
  check(
      deniedAuth, 'Proxy authentication failure must not fall back to direct');
  final untrustedProxyHttp = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  ExantasTicketProxy.fromSettings(
          List<String>.from(meta['proxies'][0]['settings']))!
      .configure(untrustedProxyHttp);
  final untrustedProxy = ExantasTicketHttpTransport(client: untrustedProxyHttp);
  var proxyTlsRejected = false;
  try {
    await untrustedProxy.request(identity, 'GET', '/capabilities');
  } catch (_) {
    proxyTlsRejected = true;
  } finally {
    untrustedProxy.close();
  }
  check(proxyTlsRejected,
      'Target TLS verification must remain active inside the proxy tunnel');
  client = create();
  final detail = await client.request('/$id');
  check((detail['files'] as List).length == 4,
      'Four exact file transfers expected');
  check(
      (detail['events'] as List)
              .where((event) => event['body'] == 'Native HTTPS public reply')
              .length ==
          1,
      'Reply duplicated');
  final url = ticketMap((await client.request(
      '/$id/files/${detail['files'][0]['id']}'))['signed_download'])['url'];
  check(checkedTicketMediaUrl(url).host == '127.0.0.1',
      'Unexpected media origin');
  check((detail['reports'] as List).isEmpty, 'No report or finance invented');
  await client.dispose();
  stdout.writeln(jsonEncode({
    'status': 'PASS',
    'ticket_id': id,
    'untrusted_tls_rejected': true,
    'confirmed_files': 4,
    'public_replies': 1,
    'proxies_verified': verified,
    'anonymous_proxies_verified': anonymous,
    'proxy_target_tls_rejected': proxyTlsRejected,
    'bad_proxy_auth_rejected': deniedAuth
  }));
}
