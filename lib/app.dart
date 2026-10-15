import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/achievements/widgets/achievement_unlocked_overlay.dart';
import 'features/auth/auth_controller.dart';
import 'features/daily_challenge/widgets/daily_challenge_overlay.dart';
import 'features/rewards/widgets/level_up_overlay.dart';
import 'features/settings/app_locale.dart';
import 'features/settings/settings_controller.dart';
import 'l10n/generated/app_localizations.dart';

class PlayNestApp extends ConsumerStatefulWidget {
  const PlayNestApp({super.key});

  @override
  ConsumerState<PlayNestApp> createState() => _PlayNestAppState();
}

class _PlayNestAppState extends ConsumerState<PlayNestApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App-start session check — the spec's rule 5: "on every app
    // start, if a saved number exists, call check_subscription in
    // the background". The controller itself debounces on
    // `lastVerifiedAtMs` so this won't fire if we just verified.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(subscriptionControllerProvider.notifier)
          .verifySessionInBackground();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // "on resume after a few hours" — debounced inside the
    // controller by `lastVerifiedAtMs` (1h default).
    if (state == AppLifecycleState.resumed) {
      developer.log('app resumed — firing background verify', name: 'AuthFlow');
      ref
          .read(subscriptionControllerProvider.notifier)
          .verifySessionInBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      locale: _localeFromEnum(settings.locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => AchievementUnlockedOverlay(
        child: DailyChallengeOverlay(
          child: LevelUpOverlay(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }

  Locale _localeFromEnum(AppLocale value) {
    return switch (value) {
      AppLocale.english => const Locale('en'),
      AppLocale.bangla => const Locale('bn'),
    };
  }
}
