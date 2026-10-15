import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/achievements_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/categories/category_detail_screen.dart';
import '../../features/favorites/favorites_screen.dart';
import '../../features/game_player/game_container_screen.dart';
import '../../features/games/game_details_screen.dart';
import '../../features/home/all_games_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/more/more_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/about/about_screen.dart';
import '../../features/settings/about/static_legal_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/bottom_nav_shell.dart';
import '../../features/shell/hide_bottom_nav.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/subscribe/subscribe_screen.dart';
import '../../data/models/game_category.dart';
import '../../l10n/generated/app_localizations.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  /// Marketing/OTP screen — entry point after splash for everyone
  /// who isn't already subscribed.
  static const String subscribe = '/subscribe';
  /// "Already subscribed" login screen — reachable from the
  /// subscribe screen's login link, or after the user hits Logout
  /// from the More/Settings tab.
  static const String login = '/login';
  static const String home = '/';
  static const String games = '/games';
  /// Backwards-compatible alias — the original catalog route lived at
  /// `/categories`. Old bookmarks / deep-links keep working.
  static const String categories = '/categories';
  static const String categoryDetail = '/category-detail';
  static const String search = '/search';
  static const String gamePlayer = '/game';
  static const String gameDetails = '/game-details';
  static const String rewards = '/rewards';
  static const String favorites = '/favorites';
  static const String more = '/more';
  /// Backwards-compatible alias — the original fourth tab lived at
  /// `/profile`.
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String achievements = '/achievements';
  static const String about = '/about';
  static const String privacyPolicy = '/privacy-policy';
  static const String terms = '/terms';
}

final goRouterProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect every time the subscription session flips
  // (Logout / Unsubscribe / fresh markSubscribed). We bridge the
  // reactive [subscriptionControllerProvider] into a Listenable so
  // go_router's `refreshListenable` re-evaluates the redirect.
  final refresh = ValueNotifier<int>(0);
  ref.listen<SubscriptionState>(subscriptionControllerProvider, (_, _) {
    refresh.value++;
  });

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    // Auth gate — kicks the user out of Home to Subscribe whenever
    // the subscription session disappears (Logout/Unsubscribe). All
    // other transitions are handled inside the screens themselves.
    redirect: (context, state) {
      final session = ref.read(subscriptionControllerProvider);
      final loc = state.matchedLocation;
      final atAuth = loc == AppRoutes.subscribe || loc == AppRoutes.login;
      // Unsubscribed users anywhere outside /splash, /onboarding, or
      // an auth surface get sent to /subscribe.
      if (!session.isSubscribed && !atAuth &&
          loc != AppRoutes.splash &&
          loc != AppRoutes.onboarding) {
        return AppRoutes.subscribe;
      }
      // If somehow already on /subscribe or /login while subscribed,
      // bounce them home (defensive — happy-path screens go() home
      // themselves, but this catches edge cases like deep-link
      // replay).
      if (session.isSubscribed && atAuth) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      // Cold-start splash — auto-routes to /subscribe or /onboarding
      // after ~1.5s. Auth gate below does the subscribe→home hop if
      // the user is already subscribed.
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      // First-launch carousel. "Get Started" writes has_onboarded and goes Home.
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Auth gate entry — Subscribe (default) and Login (opt-in for
      // landing-page subscribers). Both render full-screen so the
      // bottom-nav shell never wraps them.
      GoRoute(
        path: AppRoutes.subscribe,
        builder: (context, state) => const SubscribeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      // Full-screen routes — pushed above the bottom nav.
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.categoryDetail,
        builder: (context, state) => CategoryDetailScreen(
          category: GameCategory.fromWire(
            state.uri.queryParameters['cat'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.gameDetails,
        builder: (context, state) => GameDetailsScreen(
          gameId: state.uri.queryParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.gamePlayer}/:id',
        // HideBottomNav flips the bottom-bar provider off on mount
        // and restores on dispose, so the game always launches into
        // a full-viewport surface.
        builder: (context, state) => HideBottomNav(
          child: GameContainerScreen(
            gameId: state.pathParameters['id'] ?? '',
            level: int.tryParse(
                  state.uri.queryParameters['level'] ?? '',
                ) ??
                1,
          ),
        ),
      ),
      // Post-game rewards — now shown as a modal from inside the host
      // (see GamePlayerScreen + GameEndModal.show). The bottom-nav
      // Rewards tab is still mounted at AppRoutes.rewards, so the
      // modal-free landing route is the only one needed here.
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.achievements,
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      // Placeholder legal screens — final copy arrives with the public launch.
      GoRoute(
        path: AppRoutes.privacyPolicy,
        builder: (context, state) => StaticLegalScreen(
          title: AppLocalizations.of(context).aboutPrivacyPolicyTitle,
        ),
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) => StaticLegalScreen(
          title: AppLocalizations.of(context).aboutTermsTitle,
        ),
      ),

      // Bottom-nav shell hosting the 4 main tabs.
      //
      // Branch paths match [NavDestinations.tabs] 1-to-1:
      //   * `/`          → Home      (dashboard)
      //   * `/games`     → Games     (catalog — reuses the existing
      //                              CategoriesScreen + CategoryDetailScreen)
      //   * `/favorites` → Favorites (hearted games)
      //   * `/more`      → More      (settings / sound / about — reuses
      //                              the existing ProfileScreen until a
      //                              dedicated MoreScreen lands)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            BottomNavShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '${AppRoutes.home}all-games',
                builder: (context, state) {
                  final extra = state.extra;
                  final section = (extra is Map && extra['section'] is String)
                      ? extra['section'] as String
                      : 'all';
                  return AllGamesScreen(section: section);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Primary entry — matches the bottom-nav tab.
              GoRoute(
                path: AppRoutes.games,
                builder: (context, state) => const CategoriesScreen(),
              ),
              // Legacy `/categories` path — redirects into the same
              // screen so old deep-links still land on the Games tab.
              GoRoute(
                path: AppRoutes.categories,
                redirect: (_, _) => AppRoutes.games,
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.favorites,
                builder: (context, state) => const FavoritesScreen(),
              ),
              // Legacy `/rewards` path → favourites tab.
              GoRoute(
                path: AppRoutes.rewards,
                redirect: (_, _) => AppRoutes.favorites,
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Primary entry — matches the bottom-nav tab.
              GoRoute(
                path: AppRoutes.more,
                builder: (context, state) => const MoreScreen(),
              ),
              // Legacy `/profile` path — deep-links straight to the
              // ProfileScreen sub-page for users who bookmarked the
              // old Player tab.
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
