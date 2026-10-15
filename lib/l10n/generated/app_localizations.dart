import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// Application title shown in task switchers.
  ///
  /// In en, this message translates to:
  /// **'PlayNest'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsAppearanceThemeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsAppearanceThemeModeSystem;

  /// No description provided for @settingsAppearanceThemeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceThemeModeLight;

  /// No description provided for @settingsAppearanceThemeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceThemeModeDark;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageBangla.
  ///
  /// In en, this message translates to:
  /// **'Bangla'**
  String get settingsLanguageBangla;

  /// No description provided for @settingsNotificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsSection;

  /// No description provided for @settingsNotificationsDailyChallenge.
  ///
  /// In en, this message translates to:
  /// **'Daily challenge reminder'**
  String get settingsNotificationsDailyChallenge;

  /// No description provided for @settingsNotificationsDailyChallengeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get a nudge when today\'s challenge is live.'**
  String get settingsNotificationsDailyChallengeSubtitle;

  /// No description provided for @settingsNotificationsStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak reminder'**
  String get settingsNotificationsStreak;

  /// No description provided for @settingsNotificationsStreakSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Don\'t break your streak — play each day.'**
  String get settingsNotificationsStreakSubtitle;

  /// No description provided for @settingsDataStorageSection.
  ///
  /// In en, this message translates to:
  /// **'Data & Storage'**
  String get settingsDataStorageSection;

  /// No description provided for @settingsDataStorageDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get settingsDataStorageDownloads;

  /// No description provided for @settingsDataStorageDownloadsValue.
  ///
  /// In en, this message translates to:
  /// **'0 MB used'**
  String get settingsDataStorageDownloadsValue;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsAboutVersion;

  /// No description provided for @settingsAboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsAboutPrivacyPolicy;

  /// No description provided for @settingsAboutTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsAboutTerms;

  /// No description provided for @settingsSubscriptionSection.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get settingsSubscriptionSection;

  /// No description provided for @settingsSubscriptionManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Subscription'**
  String get settingsSubscriptionManage;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionPlaceholderHeadline.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get subscriptionPlaceholderHeadline;

  /// No description provided for @subscriptionPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'Subscription management arrives in a future release.'**
  String get subscriptionPlaceholderBody;

  /// Headline for games marked as coming soon on the details page.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoonTitle;

  /// Sub-headline body shown beneath the coming-soon title.
  ///
  /// In en, this message translates to:
  /// **'This game arrives in a future release.'**
  String get comingSoonMessage;

  /// No description provided for @aboutPrivacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicyTitle;

  /// No description provided for @aboutTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get aboutTermsTitle;

  /// No description provided for @aboutPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'This page is a placeholder. The final copy will be added before public launch.'**
  String get aboutPlaceholderBody;

  /// No description provided for @languageEnglishName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglishName;

  /// No description provided for @languageBanglaName.
  ///
  /// In en, this message translates to:
  /// **'Bangla'**
  String get languageBanglaName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
