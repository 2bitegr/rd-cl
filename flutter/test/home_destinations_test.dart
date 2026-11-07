import 'package:flutter_hbb/mobile/pages/home_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const h = HomeDestination.home,
      w = HomeDestination.work,
      s = HomeDestination.share,
      g = HomeDestination.settings;
  List<HomeDestination> d(bool android, bool incoming, bool outgoing) =>
      homeDestinations(
          isAndroid: android, incomingOnly: incoming, outgoingOnly: outgoing);

  test('android full mode has no chat root tab', () {
    expect(d(true, false, false), [h, w, s, g]);
  });
  test('android incoming-only keeps share and settings', () {
    expect(d(true, true, false), [s, g]);
  });
  test('android outgoing-only keeps home, work and settings', () {
    expect(d(true, false, true), [h, w, g]);
  });
  test('non-android keeps connection page and settings', () {
    expect(d(false, false, false), [HomeDestination.connection, g]);
    expect(d(false, true, false), [g]);
  });
  test('destinations carry Greek labels', () {
    expect([h, w, s, g].map((e) => e.label),
        ['Αρχική', 'Εργασίες', 'Κοινή χρήση', 'Ρυθμίσεις']);
  });
}
