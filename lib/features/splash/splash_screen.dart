import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../auth/auth_controller.dart';
import '../onboarding/onboarding_controller.dart';

/// Cold-start splash. Shows the brand gradient, the
/// `assets/images/logo.png` gamepad PNG, tagline, and an animated
/// loading bar for [visibleFor], then routes to Subscribe (for both
/// new + already-subscribed users — the router's redirect listener
/// will bounce them to Home if their session is still valid).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// How long the splash stays on screen before auto-routing.
  static const Duration visibleFor = Duration(milliseconds: 1500);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeAfterDelay());
  }

  @override
  void dispose() {
    _progressController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _routeAfterDelay() async {
    await Future<void>.delayed(SplashScreen.visibleFor);
    if (!mounted) return;

    // Route logic:
    //   * First launch (no onboarding completed) → onboarding.
    //   * Already onboarded + subscribed         → Home (auth gate
    //                                              bounces to Home
    //                                              if it lands on
    //                                              /subscribe instead).
    //   * Already onboarded + NOT subscribed     → Subscribe (default
    //                                              for both fresh and
    //                                              logged-out users).
    final hasOnboarded = ref.read(onboardingControllerProvider);
    if (!hasOnboarded) {
      context.go(AppRoutes.onboarding);
      return;
    }
    final isSubscribed = ref.read(subscriptionControllerProvider).isSubscribed;
    context.go(isSubscribed ? AppRoutes.home : AppRoutes.subscribe);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.play,
              AppColors.playInk, // deeper Royal Soft Blue
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: _SplashContent(
              progress: _progressController,
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered logo + tagline + animated progress bar.
class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.progress});

  final AnimationController progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cap the logo size on tall screens so the splash doesn't feel empty.
        final double logoSize = constraints.maxWidth * 0.42;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // New brand gamepad PNG — replaces the painted wordmark.
                SizedBox(
                  width: logoSize.clamp(112, 200),
                  height: logoSize.clamp(112, 200),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                AppSpacing.gapLg,
                Text(
                  'PlayNest',
                  style: AppTypography.poppins(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
                AppSpacing.gapXs,
                Text(
                  'One Hub. Endless Play.',
                  style: AppTypography.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
                    letterSpacing: 0.5,
                  ),
                ),
                AppSpacing.gapXl,
                SizedBox(
                  width: constraints.maxWidth * 0.55 < 220
                      ? constraints.maxWidth * 0.55
                      : 220,
                  child: _LoadingBar(controller: progress),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Determinate-feeling indeterminate progress bar.
///
/// Tweens a single 0→1 controller and renders a soft white stripe that
/// slides across the track. Feels faster than the stock
/// `LinearProgressIndicator` and matches the brand palette.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final double t = controller.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: <Widget>[
                // Track.
                Container(color: Colors.white.withValues(alpha: 0.18)),
                // Sliding gradient stripe — slides from -100% to 100%.
                Align(
                  alignment: Alignment(-1 + t * 2, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[
                            Color(0x00FFFFFF),
                            Colors.white,
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
