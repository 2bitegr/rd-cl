import 'package:flutter/material.dart';
import '../ui/exantas_strings.dart';

/// Root navigation destinations of the mobile HomePage.
/// `connection` is the legacy non-Android connection page.
enum HomeDestination { home, work, share, settings, connection }

extension HomeDestinationUi on HomeDestination {
  String get label => switch (this) {
        HomeDestination.home => ExStrings.navHome,
        HomeDestination.work => ExStrings.navWork,
        HomeDestination.share => ExStrings.navShare,
        HomeDestination.settings => ExStrings.navSettings,
        HomeDestination.connection => '',
      };
  IconData get icon => switch (this) {
        HomeDestination.home => Icons.home_outlined,
        HomeDestination.work => Icons.work_outline,
        HomeDestination.share => Icons.screen_share_outlined,
        HomeDestination.settings => Icons.settings_outlined,
        HomeDestination.connection => Icons.devices_other,
      };
  IconData get selectedIcon => switch (this) {
        HomeDestination.home => Icons.home,
        HomeDestination.work => Icons.work,
        HomeDestination.share => Icons.screen_share,
        HomeDestination.settings => Icons.settings,
        HomeDestination.connection => Icons.devices_other,
      };
}

/// Chat is not a root destination; it lives inside [HomeDestination.share].
List<HomeDestination> homeDestinations(
    {required bool isAndroid,
    required bool incomingOnly,
    required bool outgoingOnly}) {
  if (!isAndroid) {
    return [
      if (!incomingOnly) HomeDestination.connection,
      HomeDestination.settings,
    ];
  }
  return [
    if (!incomingOnly) ...[HomeDestination.home, HomeDestination.work],
    if (!outgoingOnly) HomeDestination.share,
    HomeDestination.settings,
  ];
}
