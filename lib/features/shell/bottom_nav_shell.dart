import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Bottom navigation destinations shown in the main app shell.
///
/// Tabs (left → right):
///   * **Home**      — Dashboard (greeting, hero, quick play, rows)
///   * **Games**     — Catalog (category grid → detail → play)
///   * **Favorites** — Hearted games for quick access
///   * **More**      — Settings / sound / about / language
class NavDestinations {
  NavDestinations._();

  static const String home = '/';
  static const String games = '/games';
  static const String favorites = '/favorites';
  static const String more = '/more';

  static const List<NavTab> tabs = <NavTab>[
    NavTab(
      path: home,
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    NavTab(
      path: games,
      label: 'Games',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
    NavTab(
      path: favorites,
      label: 'Favorites',
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
    ),
    NavTab(
      path: more,
      label: 'More',
      icon: Icons.menu_rounded,
      activeIcon: Icons.menu_open_rounded,
    ),
  ];

  static int indexFor(String location) {
    final i = tabs.indexWhere((t) => location == t.path ||
        (t.path != '/' && location.startsWith('$t.path/')));
    return i < 0 ? 0 : i;
  }
}

/// One entry in the bottom navigation bar.
class NavTab {
  const NavTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Reactive flag — when `false` the bottom bar slides off-screen so
/// the active screen (typically a mini-game) gets the full viewport.
final showBottomNavProvider = StateProvider<bool>((ref) => true);

/// Root shell with a 4-tab floating-pill bottom navigation bar.
///
/// The bar is a custom rounded translucent **pill** (not a flat
/// full-width Material `NavigationBar`) so we can match the reference
/// image:
///   * Wrapped in 16-dp horizontal padding + 16-dp bottom padding so it
///     floats above the screen edge with breathing room.
///   * 32-dp pill border-radius with a soft drop-shadow.
///   * Each tab is an [Icon] + small label + a 28×28 rounded-square
///     blue indicator behind the icon when active (instead of an
///     underline). Indicator transitions over 220 ms.
///   * Tap triggers `HapticFeedback.selectionClick()`.
class BottomNavShell extends ConsumerWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final showBar = ref.watch(showBottomNavProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: showBar
            ? _FloatingPillBar(
                key: const ValueKey('bottom-nav-visible'),
                currentIndex: currentIndex,
                onTap: _onTap,
              )
            : const SizedBox.shrink(key: ValueKey('bottom-nav-hidden')),
      ),
    );
  }
}

/// Floating-pill bottom bar — matches the reference design.
class _FloatingPillBar extends StatelessWidget {
  const _FloatingPillBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    // Light redesign: bright surface capsule so the nav reads as a
    // floating chip against the icy background gradient; dark mode
    // keeps the existing surface token.
    final fill = isDark
        ? AppColors.surface(brightness)
        : AppColors.surfaceLight;
    final inactiveFg = isDark
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.navUnselectedLight;
    final outlineAlpha = isDark ? 0.5 : 0.10;
    final elevation = isDark ? 0.0 : 6.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Material(
        color: fill,
        elevation: elevation,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.navCornerRadius),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.navCornerRadius),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: outlineAlpha),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.navCornerRadius),
            child: SafeArea(
              top: false,
              bottom: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var i = 0; i < NavDestinations.tabs.length; i++)
                      Expanded(
                        child: _NavTabButton(
                          tab: NavDestinations.tabs[i],
                          active: i == currentIndex,
                          inactiveColor: inactiveFg,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.tab,
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  final NavTab tab;
  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Selected indicator color: vibrant blue on the redesigned light
    // theme; legacy royal blue on dark mode.
    final accent = isDark ? AppColors.play : AppColors.navSelected;
    final fg = active ? Colors.white : inactiveColor;
    final iconData = active ? tab.activeIcon : tab.icon;
    // Both the indicator pill and the bare icon occupy the same slot —
    // we use AnimatedSwitcher so layout stays stable across the active
    // transition (no double-rendered children → no overflow).
    return InkResponse(
      onTap: onTap,
      radius: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 32,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: active
                  ? Container(
                      key: const ValueKey('pill'),
                      width: 40,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: !isDark
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.40),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Icon(iconData, color: fg, size: 20),
                    )
                  : Padding(
                      key: const ValueKey('bare'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(iconData, color: fg, size: 22),
                    ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.inter(
              fontSize: 11,
              fontWeight: active ? FontWeight.w900 : FontWeight.w600,
              color: active ? accent : fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}