import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Persists profile-level fields the player owns: display name, plus
/// any future per-player data that lives outside the gameplay state
/// (rewards / streak / achievements each have their own box).
///
/// Two implementations:
/// - [HiveProfileRepository] — backed by Hive (production).
/// - [InMemoryProfileRepository] — for tests / previews.
///
/// Storage shape: a tiny map at [HiveBoxes.profileKey] with the
/// fields we currently track. Adding a new field is just a new key +
/// a getter that reads it (returning a sensible default when missing).
abstract class ProfileRepository {
  /// The player's chosen display name. Empty string when never set.
  String getDisplayName();

  /// Persist [name]. Pass an empty string to clear the custom name and
  /// fall back to the default ("Player") in the UI.
  Future<void> setDisplayName(String name);
}

class HiveProfileRepository implements ProfileRepository {
  HiveProfileRepository(this._box);

  final Box<dynamic> _box;

  /// Open the profile box. Call once at startup (Hive must already
  /// be init'd via `HiveSetup.init`).
  static Future<HiveProfileRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.userProfile);
    return HiveProfileRepository(box);
  }

  @override
  String getDisplayName() {
    final raw = _box.get(HiveBoxes.profileKey);
    return raw is String ? raw : '';
  }

  @override
  Future<void> setDisplayName(String name) async {
    await _box.put(HiveBoxes.profileKey, name);
  }
}

class InMemoryProfileRepository implements ProfileRepository {
  String _name = '';

  /// Test helper: pre-populate the displayed name. Mirrors the
  /// production "previously stored on prior sessions" shape.
  void seedName(String name) {
    _name = name;
  }

  @override
  String getDisplayName() => _name;

  @override
  Future<void> setDisplayName(String name) async {
    _name = name;
  }
}
