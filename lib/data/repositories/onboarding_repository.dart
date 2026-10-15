import 'package:hive_flutter/hive_flutter.dart';

/// Tracks whether the user has completed the first-launch onboarding flow.
///
/// Two implementations:
/// - [HiveOnboardingRepository] — backed by the `app_settings` Hive box (production).
/// - [InMemoryOnboardingRepository] — for tests / previews.
abstract class OnboardingRepository {
  /// True if the user has seen onboarding at least once.
  bool hasOnboarded();

  /// Mark onboarding as completed. Persists immediately.
  Future<void> setOnboarded();
}

class HiveOnboardingRepository implements OnboardingRepository {
  HiveOnboardingRepository(this._box);

  static const String _hasOnboardedKey = 'has_onboarded';

  final Box<dynamic> _box;

  @override
  bool hasOnboarded() => _box.get(_hasOnboardedKey) == true;

  @override
  Future<void> setOnboarded() async {
    await _box.put(_hasOnboardedKey, true);
  }
}

class InMemoryOnboardingRepository implements OnboardingRepository {
  bool _onboarded = false;

  @override
  bool hasOnboarded() => _onboarded;

  @override
  Future<void> setOnboarded() async {
    _onboarded = true;
  }
}