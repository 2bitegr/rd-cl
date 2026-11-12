import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'exantas_customer_ticket.dart';

/// Reuses the app's HTTP/HTTPS/SOCKS5 setting for both JSON and signed uploads.
/// Tunnel credentials stay in memory; a failed tunnel never falls back direct.
class ExantasTicketProxy {
  ExantasTicketProxy._(this.uri, this.username, this.password, this.context);
  final Uri uri;
  final String username, password;
  final SecurityContext? context;
  static ExantasTicketProxy? fromSettings(List<String> values,
      {SecurityContext? context}) {
    if (values.isEmpty) return null;
    if (values.length != 3 || values[0].isEmpty) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    final address =
        values[0].contains('://') ? values[0] : 'socks5://${values[0]}';
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !['http', 'https', 'socks5'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    var username = '', password = '';
    if (uri.userInfo.contains(':')) {
      final parts = uri.userInfo.split(':');
      username = Uri.decodeComponent(parts.first);
      password = Uri.decodeComponent(parts.skip(1).join(':'));
    }
    if (values[1].isNotEmpty && values[2].isNotEmpty) {
      username = values[1];
      password = values[2];
    }
    if (utf8.encode(username).length > 255 ||
        utf8.encode(password).length > 255) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    if (uri.scheme == 'socks5' &&
        (username.isNotEmpty || password.isNotEmpty) &&
        (username.isEmpty || password.isEmpty)) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    final port = uri.hasPort
        ? uri.port
        : uri.scheme == 'socks5'
            ? 1080
            : uri.scheme == 'https'
                ? 443
                : 80;
    if (port < 1 || port > 65535) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    return ExantasTicketProxy._(
        uri.replace(port: port), username, password, context);
  }

  void configure(HttpClient client) {
    client.findProxy =
        (_) => 'DIRECT'; // The custom factory establishes the tunnel.
    client.connectionFactory = connect;
  }

  Future<ConnectionTask<Socket>> connect(
      Uri target, String? proxyHost, int? proxyPort) async {
    if (target.scheme != 'https' ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    Socket? socket;
    var cancelled = false;
    Future<Socket> establish() async {
      try {
        socket = uri.scheme == 'https'
            ? await SecureSocket.connect(uri.host, uri.port,
                context: context, timeout: const Duration(seconds: 15))
            : await Socket.connect(uri.host, uri.port,
                timeout: const Duration(seconds: 15));
        if (cancelled) throw const ExantasTicketFailure('ticket_cancelled');
        final reader = _TunnelReader(socket!);
        if (uri.scheme == 'socks5') {
          await _socks(socket!, reader, target);
        } else {
          final authority = target.host.contains(':')
              ? '[${target.host}]:${target.port}'
              : '${target.host}:${target.port}';
          final auth = username.isEmpty && password.isEmpty
              ? ''
              : 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('$username:$password'))}\r\n';
          socket!.add(ascii.encode(
              'CONNECT $authority HTTP/1.1\r\nHost: $authority\r\n$auth\r\n'));
          await socket!.flush();
          final header = <int>[];
          while (header.length < 8192) {
            header.add((await reader.take(1)).single);
            if (header.length >= 4 &&
                header.sublist(header.length - 4).join(',') == '13,10,13,10') {
              break;
            }
          }
          final first =
              ascii.decode(header, allowInvalid: true).split('\r\n').first;
          if (!RegExp(r'^HTTP/1\.[01] 200(?: |$)').hasMatch(first) ||
              header.length >= 8192 ||
              reader.buffer.isNotEmpty) {
            throw const ExantasTicketFailure('ticket_custom_proxy');
          }
        }
        // A custom HttpClient connection factory must return target TLS itself.
        // The pinned SDK supports upgrading an already-listened paused socket.
        // Never install a bad-certificate callback for either TLS layer.
        reader.pause();
        socket = await SecureSocket.secure(socket!,
            host: target.host, context: context);
        if (cancelled) throw const ExantasTicketFailure('ticket_cancelled');
        return socket!;
      } catch (_) {
        socket?.destroy();
        rethrow;
      }
    }

    return ConnectionTask.fromSocket(establish(), () {
      cancelled = true;
      socket?.destroy();
    });
  }

  Future<void> _socks(Socket socket, _TunnelReader reader, Uri target) async {
    final authenticated = username.isNotEmpty;
    socket.add([5, 1, authenticated ? 2 : 0]);
    await socket.flush();
    final greeting = await reader.take(2);
    if (greeting[0] != 5 || greeting[1] != (authenticated ? 2 : 0)) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    if (authenticated) {
      final user = utf8.encode(username), secret = utf8.encode(password);
      socket.add([1, user.length, ...user, secret.length, ...secret]);
      await socket.flush();
      final response = await reader.take(2);
      if (response[0] != 1 || response[1] != 0) {
        throw const ExantasTicketFailure('ticket_custom_proxy');
      }
    }
    // Match the existing native socks5 setting's local-DNS policy.
    final address = InternetAddress.tryParse(target.host) ??
        (await InternetAddress.lookup(target.host)
                .timeout(const Duration(seconds: 15)))
            .first;
    final ipv6 = address.type == InternetAddressType.IPv6;
    socket.add([
      5,
      1,
      0,
      ipv6 ? 4 : 1,
      ...address.rawAddress,
      target.port >> 8,
      target.port & 255
    ]);
    await socket.flush();
    final response = await reader.take(4);
    if (response[0] != 5 || response[1] != 0 || response[2] != 0) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    final size = response[3] == 1
        ? 4
        : response[3] == 4
            ? 16
            : response[3] == 3
                ? (await reader.take(1)).single
                : -1;
    if (size < 1 || size > 255) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
    await reader.take(size + 2);
    if (reader.buffer.isNotEmpty) {
      throw const ExantasTicketFailure('ticket_custom_proxy');
    }
  }
}

class _TunnelReader {
  _TunnelReader(Socket socket) {
    subscription = socket.listen((bytes) {
      if (buffer.length + bytes.length > 8192) {
        error = const ExantasTicketFailure('ticket_custom_proxy');
      } else {
        buffer.addAll(bytes);
      }
      waiter?.complete();
      waiter = null;
    }, onError: (Object failure) {
      error = const ExantasTicketFailure('ticket_custom_proxy');
      waiter?.complete();
      waiter = null;
    }, onDone: () {
      ended = true;
      waiter?.complete();
      waiter = null;
    });
  }
  final buffer = <int>[];
  late final StreamSubscription<Uint8List> subscription;
  Completer<void>? waiter;
  Object? error;
  bool ended = false;
  Future<List<int>> take(int size) async {
    while (buffer.length < size) {
      if (error != null) throw error!;
      if (ended) throw const ExantasTicketFailure('ticket_custom_proxy');
      waiter = Completer<void>();
      await waiter!.future.timeout(const Duration(seconds: 15));
    }
    if (error != null) throw error!;
    final bytes = buffer.sublist(0, size);
    buffer.removeRange(0, size);
    return bytes;
  }

  void pause() => subscription.pause();
}
