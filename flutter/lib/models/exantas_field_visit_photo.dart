import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Limits for field-visit photos. Photos are internal evidence, so they only
/// need to stay readable (labels, serial plates, cabling), not print quality.
class FvPhotoLimits {
  /// Longest edge after resizing, in pixels.
  static const int maxEdge = 1280;

  /// Fallback longest edge when a busy photo is still over [targetBytes].
  static const int fallbackEdge = 1024;

  /// Size we aim for; quality steps down until the photo fits.
  static const int targetBytes = 250 * 1024;

  static const int startQuality = 70;
  static const int minQuality = 45;
}

/// Result of [fvOptimizePhoto]: always a baseline JPEG without metadata.
typedef FvOptimizedPhoto = ({Uint8List bytes, String mediaType});

/// Re-encodes a camera photo to the smallest JPEG that stays readable:
/// applies the EXIF orientation, drops every EXIF field (including the
/// phone's GPS tag), shrinks the longest edge to [FvPhotoLimits.maxEdge] and
/// lowers JPEG quality until the file is at most [FvPhotoLimits.targetBytes].
/// Returns null when the bytes are not a decodable image.
FvOptimizedPhoto? fvOptimizePhoto(Uint8List input) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } catch (_) {
    return null; // truncated or foreign bytes make some decoders throw
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  image.exif = img.ExifData();

  Uint8List encodeAt(img.Image src, int edge) {
    final resized = _fit(src, edge);
    var quality = FvPhotoLimits.startQuality;
    var out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    while (out.length > FvPhotoLimits.targetBytes && quality > FvPhotoLimits.minQuality) {
      quality = (quality - 10).clamp(FvPhotoLimits.minQuality, 100);
      out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    }
    return out;
  }

  var bytes = encodeAt(image, FvPhotoLimits.maxEdge);
  if (bytes.length > FvPhotoLimits.targetBytes) {
    bytes = encodeAt(image, FvPhotoLimits.fallbackEdge);
  }
  // Never hand back something bigger than what the camera produced, as long
  // as the original was already a JPEG that we could read.
  if (bytes.length >= input.length && _isJpeg(input) && decoded.exif.isEmpty) {
    return (bytes: input, mediaType: 'image/jpeg');
  }
  return (bytes: bytes, mediaType: 'image/jpeg');
}

/// Runs [fvOptimizePhoto] off the UI thread.
Future<FvOptimizedPhoto?> fvOptimizePhotoInBackground(Uint8List input) =>
    compute(fvOptimizePhoto, input);

img.Image _fit(img.Image src, int edge) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= edge) return src;
  return src.width >= src.height
      ? img.copyResize(src, width: edge, interpolation: img.Interpolation.average)
      : img.copyResize(src, height: edge, interpolation: img.Interpolation.average);
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
