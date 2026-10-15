import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/floating_background_shapes.dart';
import '../../core/widgets/primary_button.dart';
import '../profile/profile_controller.dart';
import 'onboarding_controller.dart';

/// One slide in the onboarding carousel.
class OnboardingSlide {
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Background tint for the icon tile.
  final Color tint;
}

const List<OnboardingSlide> _slides = <OnboardingSlide>[
  OnboardingSlide(
    icon: Icons.subscriptions_rounded,
    title: 'Dozens of games, one subscription',
    body:
        'Unlock the full library with a single plan. Casual, brain, and arcade — all in one app.',
    tint: AppColors.primary,
  ),
  OnboardingSlide(
    icon: Icons.wifi_off_rounded,
    title: 'Play offline, anywhere',
    body:
        'Download once, play anywhere — no signal, no data drain, no waiting.',
    tint: AppColors.mint,
  ),
  OnboardingSlide(
    icon: Icons.local_fire_department_rounded,
    title: 'Track your progress and build your streak',
    body:
        'Earn rewards, climb the leaderboard, and never lose your daily momentum.',
    tint: AppColors.reward,
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  int _index = 0;

  /// Total pages in the carousel — the 3 intro slides plus the final
  /// name-capture slide.
  static const int _totalPages = 4;

  /// Index of the name-capture slide (last).
  static const int _namePageIndex = 3;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    // Auto-focus the name field when the name slide appears so the
    // system soft keyboard pops open immediately.
    if (index == _namePageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    } else {
      _nameFocus.unfocus();
    }
  }

  void _next() {
    if (_index >= _totalPages - 1) {
      _finish();
      return;
    }
    _pageController.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// "Skip" jumps forward to the name slide so we still collect the
  /// player's name on first install — they just don't have to read the
  /// intro carousel. From the name slide, the only way out is to type
  /// a name and tap "Get Started" (the button is disabled otherwise).
  void _skip() {
    _pageController.animateToPage(
      _namePageIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final raw = _nameController.text.trim();
    if (_index == _namePageIndex && raw.isNotEmpty) {
      // Persist the chosen display name before sealing onboarding.
      await ref.read(profileControllerProvider.notifier).setName(raw);
    }
    await ref.read(onboardingControllerProvider.notifier).markComplete();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final isNameSlide = _index == _namePageIndex;
    final isLast = _index >= _totalPages - 1;
    final typedName = _nameController.text.trim();
    final canFinish = !isNameSlide || typedName.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.canvasTopLight,
      body: SafeArea(
        child: FloatingBackgroundShapes(
          child: Stack(
            children: <Widget>[
              // Page content
              Column(
                children: <Widget>[
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: _totalPages,
                      itemBuilder: (context, i) {
                        if (i == _namePageIndex) {
                          return _NameSlide(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            onChanged: (_) => setState(() {}),
                          );
                        }
                        return _SlideView(slide: _slides[i]);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      children: <Widget>[
                        _DotIndicator(count: _totalPages, index: _index),
                        AppSpacing.gapXl,
                        PrimaryButton(
                          label: isLast ? 'Get Started' : 'Next',
                          icon: isLast ? Icons.arrow_forward_rounded : null,
                          onPressed: canFinish ? _next : null,
                        ),
                        AppSpacing.gapSm,
                      ],
                    ),
                  ),
                ],
              ),
              // Skip button — top right, hidden on the name slide.
              // From the name slide, the user must enter a name and
              // tap "Get Started" — there's no escape hatch that
              // bypasses name capture on first install.
              if (!isNameSlide)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: TextButton(
                    onPressed: _skip,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.play,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slide.tint.withValues(alpha: 0.20),
                  slide.tint.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(48),
              border: Border.all(
                color: slide.tint.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: slide.tint.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              slide.icon,
              size: 92,
              color: slide.tint,
              shadows: [
                Shadow(
                  color: slide.tint.withValues(alpha: 0.4),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          AppSpacing.gapXxl,
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppTypography.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: theme.colorScheme.onSurface,
            ),
          ),
          AppSpacing.gapMd,
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: AppTypography.inter(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: i == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (i != count - 1) AppSpacing.gapSm,
        ],
      ],
    );
  }
}

/// Final onboarding slide — collects the player's display name. Lives
/// outside the static `_slides` list because it owns mutable state
/// (the text controller + focus node) and isn't a fixed slide content.
class _NameSlide extends StatelessWidget {
  const _NameSlide({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The soft keyboard pops up and shrinks the available height by
    // ~280dp on small phones. Wrapping the content in a scroll view
    // keeps the TextField reachable instead of overflowing the page
    // (the "BOTTOM OVERFLOWED BY 23 PIXELS" error from before).
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.play.withValues(alpha: 0.20),
                  AppColors.play.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: AppColors.play.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.play.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.waving_hand_rounded,
              size: 68,
              color: AppColors.play,
              shadows: [
                Shadow(
                  color: AppColors.play.withValues(alpha: 0.4),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
          AppSpacing.gapXl,
          Text(
            'What should we call you?',
            textAlign: TextAlign.center,
            style: AppTypography.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: theme.colorScheme.onSurface,
            ),
          ),
          AppSpacing.gapSm,
          Text(
            'Your name will show on your profile and on the home screen greeting.',
            textAlign: TextAlign.center,
            style: AppTypography.inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AppSpacing.gapLg,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              maxLength: 20,
              style: AppTypography.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Your name',
                hintStyle: AppTypography.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: AppColors.play,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
