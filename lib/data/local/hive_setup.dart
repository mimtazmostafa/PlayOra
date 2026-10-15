import 'package:hive_flutter/hive_flutter.dart';

import 'hive_boxes.dart';

/// Initializes Hive. Call once from `main()` before runApp.
class HiveSetup {
  HiveSetup._();

  static Future<void> init() async {
    await Hive.initFlutter();

    // Open all known boxes up front so the rest of the app can
    // assume they're ready. Add new boxes to [HiveBoxes] as needed.
    await Future.wait([
      Hive.openBox(HiveBoxes.appSettings),
      Hive.openBox(HiveBoxes.userProfile),
      Hive.openBox(HiveBoxes.gameLibrary),
      Hive.openBox(HiveBoxes.rewards),
      Hive.openBox(HiveBoxes.recentSearches),
      Hive.openBox(HiveBoxes.favorites),
      Hive.openBox(HiveBoxes.streak),
      Hive.openBox(HiveBoxes.dailyChallenge),
      Hive.openBox(HiveBoxes.achievements),
      Hive.openBox(HiveBoxes.playHistory),
      Hive.openBox(HiveBoxes.levelProgress),
      Hive.openBox(HiveBoxes.subscription),
    ]);
  }
}
