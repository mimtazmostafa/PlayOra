import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/onboarding_repository.dart';

/// Riverpod entry point for the onboarding flag repository.
/// Override in `main` (with the Hive impl) or in tests (with the in-memory one).
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  throw UnimplementedError(
    'onboardingRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Reactive read of the onboarding flag. Re-emits whenever [markComplete]
/// is called, so the splash screen can react without re-reading the box.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(onboardingRepositoryProvider).hasOnboarded();
  }

  /// Persist `has_onboarded = true` and update state.
  Future<void> markComplete() async {
    if (state) return;
    await ref.read(onboardingRepositoryProvider).setOnboarded();
    state = true;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);