// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @errorNoApiKey.
  ///
  /// In en, this message translates to:
  /// **'No API key set. Add one in Settings first.'**
  String get errorNoApiKey;

  /// No description provided for @errorSaveReplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the reply: {error}'**
  String errorSaveReplyFailed(String error);

  /// No description provided for @errorApiKeyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter an API key'**
  String get errorApiKeyEmpty;

  /// No description provided for @apiErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Invalid API key'**
  String get apiErrorUnauthorized;

  /// No description provided for @apiErrorInsufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get apiErrorInsufficientBalance;

  /// No description provided for @apiErrorTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The request is too large'**
  String get apiErrorTooLarge;

  /// No description provided for @apiErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again later.'**
  String get apiErrorRateLimited;

  /// No description provided for @apiErrorServerBusy.
  ///
  /// In en, this message translates to:
  /// **'The server is busy. Try again later.'**
  String get apiErrorServerBusy;

  /// No description provided for @apiErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection.'**
  String get apiErrorNetwork;

  /// No description provided for @apiErrorOther.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get apiErrorOther;

  /// No description provided for @replyFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed: {error}'**
  String replyFailed(String error);

  /// No description provided for @replyRefused.
  ///
  /// In en, this message translates to:
  /// **'The content was blocked by safety policy.'**
  String get replyRefused;

  /// No description provided for @errorSaveAttachmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the attachment: {error}'**
  String errorSaveAttachmentFailed(String error);

  /// No description provided for @uploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload files'**
  String get uploadFile;

  /// No description provided for @uploadFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose from Photos'**
  String get uploadFromPhotos;

  /// No description provided for @uploadFromFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose Files'**
  String get uploadFromFiles;

  /// No description provided for @uploadUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'The selected files include an unsupported format. Convert them and try again. Supported: PDF, DOC, XLSX, PPT, images, text, and code.'**
  String get uploadUnsupportedFormat;

  /// No description provided for @uploadMaxMBSize.
  ///
  /// In en, this message translates to:
  /// **'Each file must be at most {size} MB. Adjust the file and try again'**
  String uploadMaxMBSize(int size);

  /// No description provided for @uploadMaxFiles.
  ///
  /// In en, this message translates to:
  /// **'You can attach at most {count} files'**
  String uploadMaxFiles(int count);

  /// No description provided for @uploadFileStatusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploadFileStatusUploading;

  /// No description provided for @uploadFileStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFileStatusFailed;

  /// No description provided for @uploadRetry.
  ///
  /// In en, this message translates to:
  /// **'{message}. Click to retry'**
  String uploadRetry(String message);

  /// No description provided for @uploadServerBusy.
  ///
  /// In en, this message translates to:
  /// **'The server is busy'**
  String get uploadServerBusy;

  /// No description provided for @uploadParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not parse the file'**
  String get uploadParseFailed;

  /// No description provided for @uploadFileCountLimit.
  ///
  /// In en, this message translates to:
  /// **'Uploaded file limit reached ({limit} files)'**
  String uploadFileCountLimit(String limit);

  /// No description provided for @uploadStorageLimit.
  ///
  /// In en, this message translates to:
  /// **'Storage quota reached ({limit} GB)'**
  String uploadStorageLimit(String limit);

  /// No description provided for @uploadDeleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete files'**
  String get uploadDeleteFiles;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachment;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'View image'**
  String get previewImage;

  /// No description provided for @missingAttachment.
  ///
  /// In en, this message translates to:
  /// **'The original file is missing'**
  String get missingAttachment;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
