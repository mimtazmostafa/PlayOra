import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import 'app_locale.dart';
import 'theme_mode_controller.dart';

/// Snapshot of every persisted preference the Settings screen reads
/// or mutates. Riverpod state for the whole settings surface.
class AppSettingsState {
  const AppSettingsState({
    required this.themeMode,
    required this.locale,
    required this.dailyReminderOn,
    required this.streakReminderOn,
    required this.soundOn,
    required this.hapticsOn,
  });

  final ThemeMode themeMode;
  final AppLocale locale;
  final bool dailyReminderOn;
  final bool streakReminderOn;
  final bool soundOn;
  final bool hapticsOn;

  static const AppSettingsState initial = AppSettingsState(
    themeMode: ThemeMode.system,
    locale: AppLocale.english,
    dailyReminderOn: true,
    streakReminderOn: true,
    soundOn: true,
    hapticsOn: true,
  );

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    AppLocale? locale,
    bool? dailyReminderOn,
    bool? streakReminderOn,
    bool? soundOn,
    bool? hapticsOn,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      dailyReminderOn: dailyReminderOn ?? this.dailyReminderOn,
      streakReminderOn: streakReminderOn ?? this.streakReminderOn,
      soundOn: soundOn ?? this.soundOn,
      hapticsOn: hapticsOn ?? this.hapticsOn,
    );
  }
}

/// Notifier exposing the four persisted preferences plus mutators.
/// Backed by [SettingsRepository]; persistence happens on every setter.
class SettingsController extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() {
    final repo = ref.read(settingsRepositoryProvider);
    return AppSettingsState(
      themeMode: repo.getThemeMode(),
      locale: repo.getLocale(),
      dailyReminderOn: repo.getDailyReminderOn(),
      streakReminderOn: repo.getStreakReminderOn(),
      soundOn: repo.getSoundOn(),
      hapticsOn: repo.getHapticsOn(),
    );
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
    await _repo.setThemeMode(mode);
  }

  Future<void> setLocale(AppLocale locale) async {
    if (state.locale == locale) return;
    state = state.copyWith(locale: locale);
    await _repo.setLocale(locale);
  }

  Future<void> setDailyReminderOn(bool value) async {
    if (state.dailyReminderOn == value) return;
    state = state.copyWith(dailyReminderOn: value);
    await _repo.setDailyReminderOn(value);
  }

  Future<void> setStreakReminderOn(bool value) async {
    if (state.streakReminderOn == value) return;
    state = state.copyWith(streakReminderOn: value);
    await _repo.setStreakReminderOn(value);
  }

  Future<void> setSoundOn(bool value) async {
    if (state.soundOn == value) return;
    state = state.copyWith(soundOn: value);
    await _repo.setSoundOn(value);
  }

  Future<void> setHapticsOn(bool value) async {
    if (state.hapticsOn == value) return;
    state = state.copyWith(hapticsOn: value);
    await _repo.setHapticsOn(value);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettingsState>(
  SettingsController.new,
);