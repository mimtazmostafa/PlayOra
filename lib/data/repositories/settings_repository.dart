import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/settings/app_locale.dart';
import '../local/hive_boxes.dart';

/// Persisted user preferences.
///
/// Two implementations:
/// - [HiveSettingsRepository] — backed by the `app_settings` Hive box
///   (production).
/// - [InMemorySettingsRepository] — for tests / previews.
///
/// Backed keys (all inside [HiveBoxes.appSettings]):
/// - `theme_mode`              — string: light | dark | system
/// - `locale`                  — string: en | bn
/// - `daily_reminder_on`       — bool
/// - `streak_reminder_on`      — bool
/// - `sound_on`                — bool (in-game audio feedback)
/// - `haptics_on`              — bool (tactile haptic feedback)
abstract class SettingsRepository {
  ThemeMode getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);

  AppLocale getLocale();
  Future<void> setLocale(AppLocale locale);

  bool getDailyReminderOn();
  Future<void> setDailyReminderOn(bool value);

  bool getStreakReminderOn();
  Future<void> setStreakReminderOn(bool value);

  bool getSoundOn();
  Future<void> setSoundOn(bool value);

  bool getHapticsOn();
  Future<void> setHapticsOn(bool value);
}

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  static const String _themeModeKey = 'theme_mode';
  static const String _localeKey = 'locale';
  static const String _dailyReminderKey = 'daily_reminder_on';
  static const String _streakReminderKey = 'streak_reminder_on';
  static const String _soundOnKey = 'sound_on';
  static const String _hapticsOnKey = 'haptics_on';

  final Box<dynamic> _box;

  /// Underlying Hive box. Exposed so other repositories can share it
  /// (e.g. [HiveOnboardingRepository] reuses `app_settings` for
  /// `has_onboarded`).
  Box<dynamic> get box => _box;

  /// Open the settings box. Call once at startup (Hive must already
  /// be init'd).
  static Future<HiveSettingsRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.appSettings);
    return HiveSettingsRepository(box);
  }

  @override
  ThemeMode getThemeMode() {
    final raw = _box.get(_themeModeKey) as String?;
    return _decodeThemeMode(raw);
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    await _box.put(_themeModeKey, _encodeThemeMode(mode));
  }

  @override
  AppLocale getLocale() {
    final raw = _box.get(_localeKey) as String?;
    return AppLocaleX.fromCode(raw);
  }

  @override
  Future<void> setLocale(AppLocale locale) async {
    await _box.put(_localeKey, locale.code);
  }

  @override
  bool getDailyReminderOn() {
    // Default: opt-in for reminders. Users who want silence can flip
    // them off; the previous product stance was to ship reminders on.
    return (_box.get(_dailyReminderKey) as bool?) ?? true;
  }

  @override
  Future<void> setDailyReminderOn(bool value) async {
    await _box.put(_dailyReminderKey, value);
  }

  @override
  bool getStreakReminderOn() {
    return (_box.get(_streakReminderKey) as bool?) ?? true;
  }

  @override
  Future<void> setStreakReminderOn(bool value) async {
    await _box.put(_streakReminderKey, value);
  }

  @override
  bool getSoundOn() {
    return (_box.get(_soundOnKey) as bool?) ?? true;
  }

  @override
  Future<void> setSoundOn(bool value) async {
    await _box.put(_soundOnKey, value);
  }

  @override
  bool getHapticsOn() {
    return (_box.get(_hapticsOnKey) as bool?) ?? true;
  }

  @override
  Future<void> setHapticsOn(bool value) async {
    await _box.put(_hapticsOnKey, value);
  }

  static ThemeMode _decodeThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository({
    this._mode = ThemeMode.system,
    this._locale = AppLocale.english,
    this._dailyReminderOn = true,
    this._streakReminderOn = true,
    this._soundOn = true,
    this._hapticsOn = true,
  });

  ThemeMode _mode;
  AppLocale _locale;
  bool _dailyReminderOn;
  bool _streakReminderOn;
  bool _soundOn;
  bool _hapticsOn;

  @override
  ThemeMode getThemeMode() => _mode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    _mode = mode;
  }

  @override
  AppLocale getLocale() => _locale;

  @override
  Future<void> setLocale(AppLocale locale) async {
    _locale = locale;
  }

  @override
  bool getDailyReminderOn() => _dailyReminderOn;

  @override
  Future<void> setDailyReminderOn(bool value) async {
    _dailyReminderOn = value;
  }

  @override
  bool getStreakReminderOn() => _streakReminderOn;

  @override
  Future<void> setStreakReminderOn(bool value) async {
    _streakReminderOn = value;
  }

  @override
  bool getSoundOn() => _soundOn;

  @override
  Future<void> setSoundOn(bool value) async {
    _soundOn = value;
  }

  @override
  bool getHapticsOn() => _hapticsOn;

  @override
  Future<void> setHapticsOn(bool value) async {
    _hapticsOn = value;
  }
}