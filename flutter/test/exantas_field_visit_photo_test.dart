import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_hbb/models/exantas_field_visit_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _cameraJpeg({int w = 3000, int h = 2000, int orientation = 1, bool gps = true}) {
  final r = Random(7);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = (p.x * 255 ~/ w)
      ..b = (p.y * 255 ~/ h);
  }
  im.exif.imageIfd['Orientation'] = orientation;
  if (gps) im.exif.gpsIfd['GPSLatitudeRef'] = 'N';
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  test('noisy 6 MP photo shrinks to the target size and edge', () {
    final input = _cameraJpeg();
    final out = fvOptimizePhoto(input)!;
    expect(out.mediaType, 'image/jpeg');
    expect(out.bytes.length, lessThanOrEqualTo(FvPhotoLimits.targetBytes));
    expect(out.bytes.length, lessThan(input.length));
    final d = img.decodeJpg(out.bytes)!;
    expect(max(d.width, d.height), lessThanOrEqualTo(FvPhotoLimits.maxEdge));
  });

  test('EXIF, including GPS, is removed', () {
    final out = fvOptimizePhoto(_cameraJpeg(w: 800, h: 600))!;
    final d = img.decodeJpg(out.bytes)!;
    expect(d.exif.gpsIfd.isEmpty, isTrue);
    expect(d.exif.imageIfd['Orientation'], isNull);
  });

  test('orientation is baked into the pixels', () {
    final out = fvOptimizePhoto(_cameraJpeg(w: 1600, h: 1200, orientation: 6))!;
    final d = img.decodeJpg(out.bytes)!;
    expect(d.height, greaterThan(d.width));
  });

  test('PNG input becomes JPEG', () {
    final im = img.Image(width: 400, height: 300);
    final out = fvOptimizePhoto(Uint8List.fromList(img.encodePng(im)))!;
    expect(out.mediaType, 'image/jpeg');
    expect(out.bytes.sublist(0, 2), [0xFF, 0xD8]);
  });

  test('non-image bytes return null', () {
    expect(fvOptimizePhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
