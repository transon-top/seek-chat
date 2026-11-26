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

  /// No description provided for @keyPromptMessage.
  ///
  /// In en, this message translates to:
  /// **'No API key set. Add one to start chatting.'**
  String get keyPromptMessage;

  /// No description provided for @keyPromptAction.
  ///
  /// In en, this message translates to:
  /// **'Add key'**
  String get keyPromptAction;

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

  /// No description provided for @apiErrorContentRejected.
  ///
  /// In en, this message translates to:
  /// **'The content did not pass safety review. Edit it and try again.'**
  String get apiErrorContentRejected;

  /// No description provided for @apiErrorOther.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get apiErrorOther;

  /// No description provided for @replyRefused.
  ///
  /// In en, this message translates to:
  /// **'Sorry, that\'s beyond my current scope. Let\'s talk about something else.'**
  String get replyRefused;

  /// No description provided for @replyImageBlocked.
  ///
  /// In en, this message translates to:
  /// **'The image was blocked by content safety review. Remove it and try again.'**
  String get replyImageBlocked;

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

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsEntry.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsEntry;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsSectionApp;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get settingsAccount;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsSystemShort.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystemShort;

  /// No description provided for @settingsFontSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview text size'**
  String get settingsFontSizePreview;

  /// No description provided for @settingsFontSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'Drag the slider to adjust the text size.'**
  String get settingsFontSizeDescription;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsFontSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsFontSize;

  /// No description provided for @settingsFontSizeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsFontSizeSystem;

  /// No description provided for @settingsFontSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsFontSizeStandard;

  /// No description provided for @settingsFontSizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Smallest'**
  String get settingsFontSizeSmallest;

  /// No description provided for @settingsFontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsFontSizeSmall;

  /// No description provided for @settingsFontSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get settingsFontSizeMedium;

  /// No description provided for @settingsFontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsFontSizeLarge;

  /// No description provided for @settingsFontSizeLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get settingsFontSizeLarger;

  /// No description provided for @settingsFontSizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Largest'**
  String get settingsFontSizeLargest;

  /// No description provided for @settingsClearKey.
  ///
  /// In en, this message translates to:
  /// **'Clear saved key'**
  String get settingsClearKey;

  /// No description provided for @settingsApiKeyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter an API key to get started'**
  String get settingsApiKeyPrompt;

  /// No description provided for @settingsApiKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter API key'**
  String get settingsApiKeyPlaceholder;

  /// No description provided for @settingsApiKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get settingsApiKeyConfirm;

  /// No description provided for @settingsApiKeyVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get settingsApiKeyVerifying;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get settingsProvince;

  /// No description provided for @settingsCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get settingsCity;

  /// No description provided for @settingsRegion.
  ///
  /// In en, this message translates to:
  /// **'Country / region'**
  String get settingsRegion;

  /// No description provided for @settingsProvincePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select province'**
  String get settingsProvincePlaceholder;

  /// No description provided for @settingsCityPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select city'**
  String get settingsCityPlaceholder;

  /// No description provided for @settingsLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get settingsLocation;

  /// No description provided for @settingsLocationNone.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get settingsLocationNone;

  /// No description provided for @settingsLocationDescription.
  ///
  /// In en, this message translates to:
  /// **'Sent only with messages to your configured API. Location access is not requested.'**
  String get settingsLocationDescription;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @openSessionList.
  ///
  /// In en, this message translates to:
  /// **'Open chat list'**
  String get openSessionList;

  /// No description provided for @sessionGroupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get sessionGroupToday;

  /// No description provided for @sessionGroupYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get sessionGroupYesterday;

  /// No description provided for @sessionGroupLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get sessionGroupLast7Days;

  /// No description provided for @sessionGroupEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get sessionGroupEarlier;

  /// No description provided for @sessionGroupPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get sessionGroupPinned;

  /// No description provided for @searchChatsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search chats…'**
  String get searchChatsPlaceholder;

  /// No description provided for @searchBack.
  ///
  /// In en, this message translates to:
  /// **'Back to chats'**
  String get searchBack;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get searchNoResults;

  /// No description provided for @selectChats.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectChats;

  /// No description provided for @selectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select chats'**
  String get selectionTitle;

  /// No description provided for @selectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectionCount(int count);

  /// No description provided for @exitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get exitSelection;

  /// No description provided for @pinSession.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinSession;

  /// No description provided for @unpinSession.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinSession;

  /// No description provided for @deleteSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} chats'**
  String deleteSessionsTitle(int count);

  /// No description provided for @sessionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading chats…'**
  String get sessionLoading;

  /// No description provided for @sessionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load chats'**
  String get sessionsLoadFailed;

  /// No description provided for @startupFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot open SeekChat'**
  String get startupFailedTitle;

  /// No description provided for @startupFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Local data could not be read. Try again; if the problem persists, clear local chats and attachments to start over.'**
  String get startupFailedBody;

  /// No description provided for @startupClearData.
  ///
  /// In en, this message translates to:
  /// **'Clear local chats and attachments'**
  String get startupClearData;

  /// No description provided for @startupClearDataConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear local chats and attachments?'**
  String get startupClearDataConfirmTitle;

  /// No description provided for @startupClearDataConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All chats, messages, and attachment originals will be permanently deleted. Settings and the API key are kept. This cannot be undone.'**
  String get startupClearDataConfirmBody;

  /// No description provided for @startupClearDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get startupClearDataConfirm;

  /// No description provided for @startupClearDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear data. Try again.'**
  String get startupClearDataFailed;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'How can I help you?'**
  String get chatEmptyTitle;

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noSessions;

  /// No description provided for @untitledChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get untitledChat;

  /// No description provided for @renameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameSession;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get deleteSession;

  /// No description provided for @deleteSessionDescription.
  ///
  /// In en, this message translates to:
  /// **'This chat and its uploaded files will be permanently deleted and cannot be recovered. Delete this chat?'**
  String get deleteSessionDescription;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @userMessage.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get userMessage;

  /// No description provided for @assistantReply.
  ///
  /// In en, this message translates to:
  /// **'Assistant reply'**
  String get assistantReply;

  /// No description provided for @messageActions.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get messageActions;

  /// No description provided for @versionPosition.
  ///
  /// In en, this message translates to:
  /// **'Version {current} of {total}'**
  String versionPosition(int current, int total);

  /// No description provided for @sourceNumber.
  ///
  /// In en, this message translates to:
  /// **'Source {index}'**
  String sourceNumber(int index);

  /// No description provided for @openSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get openSource;

  /// No description provided for @stopGeneration.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get stopGeneration;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @continueGeneration.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueGeneration;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessage;

  /// No description provided for @messageVersions.
  ///
  /// In en, this message translates to:
  /// **'Message versions'**
  String get messageVersions;

  /// No description provided for @previousVersion.
  ///
  /// In en, this message translates to:
  /// **'Previous version'**
  String get previousVersion;

  /// No description provided for @nextVersion.
  ///
  /// In en, this message translates to:
  /// **'Next version'**
  String get nextVersion;

  /// No description provided for @deepThinking.
  ///
  /// In en, this message translates to:
  /// **'DeepThink'**
  String get deepThinking;

  /// No description provided for @thoughtForSeconds.
  ///
  /// In en, this message translates to:
  /// **'Thought for {seconds}s'**
  String thoughtForSeconds(int seconds);

  /// No description provided for @thinkingForSeconds.
  ///
  /// In en, this message translates to:
  /// **'Thinking… {seconds}s'**
  String thinkingForSeconds(int seconds);

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @imageSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching images...'**
  String get imageSearching;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get searching;

  /// No description provided for @browsingWeb.
  ///
  /// In en, this message translates to:
  /// **'Browsing the web'**
  String get browsingWeb;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get thinking;

  /// No description provided for @searchingQuery.
  ///
  /// In en, this message translates to:
  /// **'Searching {query}'**
  String searchingQuery(String query);

  /// No description provided for @searchingDots.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searchingDots;

  /// No description provided for @searchStopped.
  ///
  /// In en, this message translates to:
  /// **'Search stopped'**
  String get searchStopped;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Web search is unavailable'**
  String get searchUnavailable;

  /// No description provided for @noSuitableResults.
  ///
  /// In en, this message translates to:
  /// **'No suitable results found'**
  String get noSuitableResults;

  /// No description provided for @noRelevantResults.
  ///
  /// In en, this message translates to:
  /// **'No relevant results found'**
  String get noRelevantResults;

  /// No description provided for @searchedPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Found 1 page} other{Found {count} pages}}'**
  String searchedPages(int count);

  /// No description provided for @readPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Read 1 page} other{Read {count} pages}}'**
  String readPages(int count);

  /// No description provided for @browsePageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the page'**
  String get browsePageFailed;

  /// No description provided for @browsingPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Browsing 1 page} other{Browsing {count} pages}}'**
  String browsingPages(int count);

  /// No description provided for @browseFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed'**
  String get browseFailed;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @findFailed.
  ///
  /// In en, this message translates to:
  /// **'Find failed'**
  String get findFailed;

  /// No description provided for @findKeywords.
  ///
  /// In en, this message translates to:
  /// **'Find keywords'**
  String get findKeywords;

  /// No description provided for @noMatchingContent.
  ///
  /// In en, this message translates to:
  /// **'No matching content found'**
  String get noMatchingContent;

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String pagesCount(int count);

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResults;

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Message or hold to talk'**
  String get composerHint;

  /// No description provided for @composerHintWithAttachments.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get composerHintWithAttachments;

  /// No description provided for @composerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a message'**
  String get composerPlaceholder;

  /// No description provided for @addAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get addAttachment;

  /// No description provided for @closeAttachmentPanel.
  ///
  /// In en, this message translates to:
  /// **'Close attachment panel'**
  String get closeAttachmentPanel;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @photoUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this photo'**
  String get photoUnreadable;

  /// No description provided for @photoPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Can\'t access photos'**
  String get photoPermissionDenied;

  /// No description provided for @photoLimitedManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get photoLimitedManage;

  /// No description provided for @photoLimitedManageSemantics.
  ///
  /// In en, this message translates to:
  /// **'Manage accessible photos'**
  String get photoLimitedManageSemantics;

  /// No description provided for @photoStripEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent photos'**
  String get photoStripEmpty;

  /// No description provided for @photoStripLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load photos'**
  String get photoStripLoadFailed;

  /// No description provided for @photoTileSelected.
  ///
  /// In en, this message translates to:
  /// **'Photo {index}, selected'**
  String photoTileSelected(int index);

  /// No description provided for @photoTileUnselected.
  ///
  /// In en, this message translates to:
  /// **'Photo {index}, not selected'**
  String photoTileUnselected(int index);

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @smartSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get smartSearch;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @historyImport.
  ///
  /// In en, this message translates to:
  /// **'Import chat history'**
  String get historyImport;

  /// No description provided for @historyImportAction.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get historyImportAction;

  /// No description provided for @historyImportDescription.
  ///
  /// In en, this message translates to:
  /// **'Importing chat history replaces all local chats and attachments. Supports ZIP files exported from DeepSeek.'**
  String get historyImportDescription;

  /// No description provided for @historyImportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Import chat history?'**
  String get historyImportConfirmTitle;

  /// No description provided for @historyImportConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'The uploaded chat history will replace all your current chats and attachments. Export a backup first if you need to keep them.'**
  String get historyImportConfirmDescription;

  /// No description provided for @historyImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get historyImportConfirm;

  /// No description provided for @historyImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get historyImporting;

  /// No description provided for @historyImportedOne.
  ///
  /// In en, this message translates to:
  /// **'Imported 1 chat'**
  String get historyImportedOne;

  /// No description provided for @historyImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} chats'**
  String historyImported(int count);

  /// No description provided for @historyImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed. The file may be invalid or use an old export format.'**
  String get historyImportFailed;

  /// No description provided for @historyExport.
  ///
  /// In en, this message translates to:
  /// **'Export all chats'**
  String get historyExport;

  /// No description provided for @historyExportAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get historyExportAction;

  /// No description provided for @historyExportDescription.
  ///
  /// In en, this message translates to:
  /// **'Includes all chat history and locally stored images. Other attachments keep file details only. Your API key is not included.'**
  String get historyExportDescription;

  /// No description provided for @historyExporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get historyExporting;

  /// No description provided for @historyExported.
  ///
  /// In en, this message translates to:
  /// **'Export saved'**
  String get historyExported;

  /// No description provided for @historyExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get historyExportFailed;

  /// No description provided for @historyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats'**
  String get historyDelete;

  /// No description provided for @historyDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats?'**
  String get historyDeleteConfirmTitle;

  /// No description provided for @historyDeleteConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'All chats and attachments on this device will be permanently deleted and cannot be recovered.'**
  String get historyDeleteConfirmDescription;

  /// No description provided for @historyDeleted.
  ///
  /// In en, this message translates to:
  /// **'All chats deleted'**
  String get historyDeleted;

  /// No description provided for @historyDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed. Please try again.'**
  String get historyDeleteFailed;

  /// No description provided for @historyErrorUnrecognized.
  ///
  /// In en, this message translates to:
  /// **'File not recognized. Choose a DeepSeek chat history ZIP.'**
  String get historyErrorUnrecognized;

  /// No description provided for @historyErrorNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'This file uses a newer version. Update the app before importing.'**
  String get historyErrorNewerVersion;

  /// No description provided for @historyErrorInvalidVersion.
  ///
  /// In en, this message translates to:
  /// **'The file version is invalid and cannot be imported.'**
  String get historyErrorInvalidVersion;

  /// No description provided for @historyErrorInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'The file is not valid JSON.'**
  String get historyErrorInvalidJson;

  /// No description provided for @historyErrorIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The file is incomplete and cannot be imported.'**
  String get historyErrorIncomplete;

  /// No description provided for @historyErrorInvalidBranches.
  ///
  /// In en, this message translates to:
  /// **'The message branches in this file are corrupted and cannot be imported.'**
  String get historyErrorInvalidBranches;

  /// No description provided for @historyErrorInvalidFiles.
  ///
  /// In en, this message translates to:
  /// **'The attachment data in this file is corrupted and cannot be imported.'**
  String get historyErrorInvalidFiles;

  /// No description provided for @historyErrorTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is too large to import.'**
  String get historyErrorTooLarge;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @historyErrorExportTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is too large to export.'**
  String get historyErrorExportTooLarge;

  /// No description provided for @voiceInputPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is denied. Allow it in system settings.'**
  String get voiceInputPermissionDenied;

  /// No description provided for @voiceInputNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No microphone detected'**
  String get voiceInputNoDevice;

  /// No description provided for @voiceInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition failed. Please try again later.'**
  String get voiceInputFailed;

  /// No description provided for @voiceInputEmpty.
  ///
  /// In en, this message translates to:
  /// **'No speech detected'**
  String get voiceInputEmpty;

  /// No description provided for @voiceInputLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Maximum recording length reached'**
  String get voiceInputLimitReached;

  /// No description provided for @voiceInputInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Recording interrupted'**
  String get voiceInputInterrupted;

  /// No description provided for @holdToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get holdToTalk;

  /// No description provided for @voiceHoldToSend.
  ///
  /// In en, this message translates to:
  /// **'Release to send, slide up to cancel'**
  String get voiceHoldToSend;

  /// No description provided for @voiceReleaseToCancel.
  ///
  /// In en, this message translates to:
  /// **'Release to cancel'**
  String get voiceReleaseToCancel;

  /// No description provided for @voiceRecognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing'**
  String get voiceRecognizing;

  /// No description provided for @voiceMicGrantedRetry.
  ///
  /// In en, this message translates to:
  /// **'Microphone access granted. Hold to talk again.'**
  String get voiceMicGrantedRetry;

  /// No description provided for @voiceRecordSemantics.
  ///
  /// In en, this message translates to:
  /// **'Recording. Double-tap to finish and send.'**
  String get voiceRecordSemantics;

  /// No description provided for @voiceCancelRecording.
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get voiceCancelRecording;

  /// No description provided for @voiceCancelled.
  ///
  /// In en, this message translates to:
  /// **'Recording cancelled'**
  String get voiceCancelled;

  /// No description provided for @voiceRecognizingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Recognizing speech'**
  String get voiceRecognizingSemantics;

  /// No description provided for @voiceSendFailedInserted.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send. The text is in the message field.'**
  String get voiceSendFailedInserted;

  /// No description provided for @voiceInsertedGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating. Transcription inserted.'**
  String get voiceInsertedGenerating;

  /// No description provided for @voiceInsertedUploading.
  ///
  /// In en, this message translates to:
  /// **'Attachments uploading. Transcription inserted.'**
  String get voiceInsertedUploading;

  /// No description provided for @voiceInsertedNotSent.
  ///
  /// In en, this message translates to:
  /// **'Transcription inserted. Not sent automatically.'**
  String get voiceInsertedNotSent;

  /// No description provided for @ttsPlay.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get ttsPlay;

  /// No description provided for @ttsStop.
  ///
  /// In en, this message translates to:
  /// **'Stop reading'**
  String get ttsStop;

  /// No description provided for @ttsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This answer cannot be read aloud right now'**
  String get ttsUnavailable;

  /// No description provided for @ttsFailed.
  ///
  /// In en, this message translates to:
  /// **'Read-aloud failed. Please try again later.'**
  String get ttsFailed;

  /// No description provided for @settingsTtsVoice.
  ///
  /// In en, this message translates to:
  /// **'Read-aloud voice'**
  String get settingsTtsVoice;

  /// No description provided for @settingsTtsVoiceStella.
  ///
  /// In en, this message translates to:
  /// **'Stella · female'**
  String get settingsTtsVoiceStella;

  /// No description provided for @settingsTtsVoiceTide.
  ///
  /// In en, this message translates to:
  /// **'Tide · male'**
  String get settingsTtsVoiceTide;

  /// No description provided for @settingsSpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get settingsSpeech;

  /// No description provided for @settingsMicPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone access'**
  String get settingsMicPermission;

  /// No description provided for @settingsMicNotRequested.
  ///
  /// In en, this message translates to:
  /// **'Not requested'**
  String get settingsMicNotRequested;

  /// No description provided for @settingsMicGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get settingsMicGranted;

  /// No description provided for @settingsMicDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get settingsMicDenied;

  /// No description provided for @settingsSpeechDescription.
  ///
  /// In en, this message translates to:
  /// **'Voice input needs microphone access; read-aloud does not. Works in the foreground only.'**
  String get settingsSpeechDescription;

  /// No description provided for @settingsOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get settingsOpenSystemSettings;

  /// No description provided for @scrollToBottom.
  ///
  /// In en, this message translates to:
  /// **'Back to bottom'**
  String get scrollToBottom;
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
