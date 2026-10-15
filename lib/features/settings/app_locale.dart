/// Supported app locales.
///
/// We persist one of these via [SettingsRepository] and surface the
/// matching [Locale] to `MaterialApp.locale` so the framework picks the
/// correct `app_en.arb` / `app_bn.arb` bundle. English is the only
/// fully-translated locale for now; Bangla strings fall back to English
/// until Phase 6 lands full translations.
enum AppLocale { english, bangla }

extension AppLocaleX on AppLocale {
  String get code => switch (this) {
        AppLocale.english => 'en',
        AppLocale.bangla => 'bn',
      };

  String get label => switch (this) {
        AppLocale.english => 'English',
        AppLocale.bangla => 'Bangla',
      };

  static AppLocale fromCode(String? raw) {
    if (raw == 'bn') return AppLocale.bangla;
    return AppLocale.english;
  }
}