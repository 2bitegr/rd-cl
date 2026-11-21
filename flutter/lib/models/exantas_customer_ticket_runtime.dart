import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:win32/win32.dart' as win;
import 'package:window_manager/window_manager.dart';

import 'exantas_companion_model.dart';
import 'exantas_customer_ticket.dart';
import 'exantas_customer_ticket_store.dart';
import 'exantas_customer_ticket_proxy.dart';
import 'exantas_secure_store.dart';
import 'platform_model.dart';

Future<ExantasCustomerTicketClient> createCustomerTicketClient() async {
  if (!Platform.isWindows) throw const ExantasTicketFailure('ticket_contract');
  final service = ExantasCompanionService();
  final proxySettings = List<String>.from(await bind.mainGetSocks());
  final proxy = ExantasTicketProxy.fromSettings(proxySettings);
  Future<ExantasTicketIdentity> current() async {
    final status = await service.loadStatus();
    if (!status.enrolled ||
        status.enrollmentPending ||
        status.technicianLoggedIn) {
      throw const ExantasTicketFailure('ticket_identity_changed');
    }
    if (jsonEncode(await bind.mainGetSocks()) != jsonEncode(proxySettings)) {
      throw const ExantasTicketFailure('ticket_network_changed');
    }
    return ExantasTicketIdentity(
        status.apiBase.replaceFirst(RegExp(r'/+$'), ''),
        bind.mainGetLocalOption(key: kExantasDeviceId),
        status.deviceToken);
  }

  final identity = await current();
  const secure = ExantasSecureStore();
  final root = await getApplicationSupportDirectory();
  final store = ExantasTicketFileStore(
      directory: Directory(
          p.join(root.path, 'office-customer-tickets', identity.scope)),
      scope: identity.scope,
      protectedPrefix: 'dpapi:v1:',
      protect: secure.protectAsync,
      unprotect: secure.unprotectAsync);
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  proxy?.configure(http);
  return ExantasCustomerTicketClient(
      identity: identity,
      current: current,
      store: store,
      transport: ExantasTicketHttpTransport(client: http));
}

Future<List<String>> pickCustomerTicketFiles() async {
  final chosen = await FilePicker.platform.pickFiles(
      dialogTitle: 'Εικόνες ή βίντεο για την υποστήριξη',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'mp4', 'webm'],
      allowMultiple: true,
      withData: false);
  return chosen?.files.map((file) => file.path).whereType<String>().toList() ??
      [];
}

Future<void> previewCustomerTicketFile(String path) async {
  // A user-selected, locally verified media file only; no shell command string.
  await inspectTicketFile(path);
  if (!await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication)) {
    throw const ExantasTicketFailure('ticket_preview_unavailable');
  }
}

Future<void> openCustomerTicketMedia(Uri uri) async {
  checkedTicketMediaUrl(uri.toString());
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const ExantasTicketFailure('ticket_preview_unavailable');
  }
}

Uint8List captureCustomerPrimaryDisplay() {
  if (!Platform.isWindows) {
    throw const ExantasTicketFailure('ticket_capture_unavailable');
  }
  final width = win.GetSystemMetrics(win.SYSTEM_METRICS_INDEX.SM_CXSCREEN);
  final height = win.GetSystemMetrics(win.SYSTEM_METRICS_INDEX.SM_CYSCREEN);
  if (width <= 0 || height <= 0 || width * height > 16000000) {
    throw const ExantasTicketFailure('ticket_capture_unavailable');
  }
  final screen = win.GetDC(0);
  if (screen == 0) {
    throw const ExantasTicketFailure('ticket_capture_unavailable');
  }
  var dc = 0, bitmap = 0, old = 0;
  try {
    dc = win.CreateCompatibleDC(screen);
    if (dc == 0) throw const ExantasTicketFailure('ticket_capture_unavailable');
    bitmap = win.CreateCompatibleBitmap(screen, width, height);
    if (bitmap == 0) {
      throw const ExantasTicketFailure('ticket_capture_unavailable');
    }
    old = win.SelectObject(dc, bitmap);
    if (old == 0 ||
        old == -1 ||
        win.BitBlt(dc, 0, 0, width, height, screen, 0, 0,
                win.ROP_CODE.SRCCOPY | win.ROP_CODE.CAPTUREBLT) ==
            0) {
      throw const ExantasTicketFailure('ticket_capture_unavailable');
    }
    win.SelectObject(dc, old);
    old = 0;
    return using((alloc) {
      final info = alloc<win.BITMAPINFO>();
      info.ref.bmiHeader
        ..biSize = sizeOf<win.BITMAPINFOHEADER>()
        ..biWidth = width
        ..biHeight = -height
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = win.BI_COMPRESSION.BI_RGB;
      final pixels = alloc<Uint8>(width * height * 4);
      if (win.GetDIBits(dc, bitmap, 0, height, pixels, info,
              win.DIB_USAGE.DIB_RGB_COLORS) !=
          height) {
        throw const ExantasTicketFailure('ticket_capture_unavailable');
      }
      final frame = image.Image.fromBytes(
          width: width,
          height: height,
          bytes: pixels.asTypedList(width * height * 4).buffer,
          numChannels: 4,
          order: image.ChannelOrder.bgra);
      // GDI's unused alpha byte must not make the screenshot transparent.
      for (final pixel in frame) {
        pixel.a = 255;
      }
      final png = image.encodePng(frame);
      if (png.length > 10000000) {
        throw const ExantasTicketFailure('invalid_ticket_upload');
      }
      return png;
    });
  } finally {
    if (old != 0 && dc != 0) win.SelectObject(dc, old);
    if (bitmap != 0) win.DeleteObject(bitmap);
    if (dc != 0) win.DeleteDC(dc);
    win.ReleaseDC(0, screen);
  }
}

/// Called only by the explicit screenshot button after the customer confirms
/// the privacy notice. No timer, initialization or background action captures.
Future<String?> captureAndSaveCustomerScreenshot() async {
  final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Αποθήκευση screenshot στον υπολογιστή σας',
      fileName: 'support-screen-${DateTime.now().millisecondsSinceEpoch}.png',
      type: FileType.custom,
      allowedExtensions: const ['png']);
  if (path == null) return null;
  if (p.extension(path).toLowerCase() != '.png') {
    throw const ExantasTicketFailure('invalid_ticket_upload');
  }
  await windowManager.minimize();
  Uint8List png;
  try {
    await Future<void>.delayed(const Duration(seconds: 3));
    png = captureCustomerPrimaryDisplay();
  } finally {
    await windowManager.show();
    await windowManager.focus();
  }
  // Preserve existing user files, including a same-name screenshot.
  final file = File(path);
  await file.create(exclusive: true);
  await file.writeAsBytes(png, flush: true);
  return path;
}
