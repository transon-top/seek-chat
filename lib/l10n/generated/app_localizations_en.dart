// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get errorNoApiKey => 'No API key set. Add one in Settings first.';

  @override
  String errorSaveReplyFailed(String error) {
    return 'Could not save the reply: $error';
  }

  @override
  String get errorApiKeyEmpty => 'Enter an API key';

  @override
  String get apiErrorUnauthorized => 'Invalid API key';

  @override
  String get apiErrorInsufficientBalance => 'Insufficient balance';

  @override
  String get apiErrorTooLarge => 'The request is too large';

  @override
  String get apiErrorRateLimited => 'Too many requests. Try again later.';

  @override
  String get apiErrorServerBusy => 'The server is busy. Try again later.';

  @override
  String get apiErrorNetwork => 'Network error. Check your connection.';

  @override
  String get apiErrorContentRejected =>
      'The content did not pass safety review. Edit it and try again.';

  @override
  String get apiErrorOther => 'Something went wrong. Please try again.';

  @override
  String replyFailed(String error) {
    return 'Generation failed: $error';
  }

  @override
  String get replyFailedTitle => 'Generation failed';

  @override
  String get replyRefused =>
      'Sorry, that\'s beyond my current scope. Let\'s talk about something else.';

  @override
  String get replyImageBlocked =>
      'The image was blocked by content safety review. Remove it and try again.';

  @override
  String errorSaveAttachmentFailed(String error) {
    return 'Could not save the attachment: $error';
  }

  @override
  String get uploadFile => 'Upload files';

  @override
  String get uploadFromPhotos => 'Choose from Photos';

  @override
  String get uploadFromFiles => 'Choose Files';

  @override
  String get uploadUnsupportedFormat =>
      'The selected files include an unsupported format. Convert them and try again. Supported: PDF, DOC, XLSX, PPT, images, text, and code.';

  @override
  String uploadMaxMBSize(int size) {
    return 'Each file must be at most $size MB. Adjust the file and try again';
  }

  @override
  String uploadMaxFiles(int count) {
    return 'You can attach at most $count files';
  }

  @override
  String get uploadFileStatusUploading => 'Uploading...';

  @override
  String get uploadFileStatusFailed => 'Upload failed';

  @override
  String uploadRetry(String message) {
    return '$message. Click to retry';
  }

  @override
  String get uploadServerBusy => 'The server is busy';

  @override
  String get uploadParseFailed => 'Could not parse the file';

  @override
  String uploadFileCountLimit(String limit) {
    return 'Uploaded file limit reached ($limit files)';
  }

  @override
  String uploadStorageLimit(String limit) {
    return 'Storage quota reached ($limit GB)';
  }

  @override
  String get uploadDeleteFiles => 'Delete files';

  @override
  String get removeAttachment => 'Remove attachment';

  @override
  String get retry => 'Retry';

  @override
  String get previewImage => 'View image';

  @override
  String get missingAttachment => 'The original file is missing';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsEntry => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsFontSize => 'Text size';

  @override
  String get settingsFontSizeSystem => 'Follow system';

  @override
  String get settingsFontSizeStandard => 'Default';

  @override
  String get settingsFontSizeSmallest => 'Smallest';

  @override
  String get settingsFontSizeSmall => 'Small';

  @override
  String get settingsFontSizeMedium => 'Medium';

  @override
  String get settingsFontSizeLarge => 'Large';

  @override
  String get settingsFontSizeLarger => 'Larger';

  @override
  String get settingsFontSizeLargest => 'Largest';

  @override
  String get settingsClearKey => 'Clear saved key';

  @override
  String get settingsApiKeySaved => 'Saved';

  @override
  String get settingsApiKeyPrompt => 'Enter an API key to get started';

  @override
  String get settingsApiKeyPlaceholder => 'Enter API key';

  @override
  String get settingsApiKeyConfirm => 'Confirm';

  @override
  String get settingsApiKeyVerifying => 'Verifying…';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageZh => 'Simplified Chinese';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsProvincePlaceholder => 'Select province';

  @override
  String get settingsCityPlaceholder => 'Select city';

  @override
  String get settingsLocation => 'Location';

  @override
  String get settingsLocationNone => 'Not specified';

  @override
  String get settingsLocationDescription =>
      'Sent only with messages to your configured API. Location access is not requested.';

  @override
  String get newChat => 'New chat';

  @override
  String get openSessionList => 'Open chat list';

  @override
  String get sessionActions => 'Chat actions';

  @override
  String get sessionGroupToday => 'Today';

  @override
  String get sessionGroupYesterday => 'Yesterday';

  @override
  String get sessionGroupLast7Days => 'Last 7 days';

  @override
  String get sessionGroupEarlier => 'Earlier';

  @override
  String get sessionGroupPinned => 'Pinned';

  @override
  String get searchChatsPlaceholder => 'Search chats…';

  @override
  String get searchBack => 'Back to chats';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get searchNoResults => 'No results';

  @override
  String get selectChats => 'Select';

  @override
  String get selectionTitle => 'Select chats';

  @override
  String selectionCount(int count) {
    return '$count selected';
  }

  @override
  String get exitSelection => 'Exit selection';

  @override
  String get pinSession => 'Pin';

  @override
  String get unpinSession => 'Unpin';

  @override
  String deleteSessionsTitle(int count) {
    return 'Delete $count chats';
  }

  @override
  String get sessionLoading => 'Loading chats…';

  @override
  String get sessionsLoadFailed => 'Could not load chats';

  @override
  String get chatEmptyTitle => 'How can I help you?';

  @override
  String get noSessions => 'No chats yet';

  @override
  String get untitledChat => 'New chat';

  @override
  String get renameSession => 'Rename chat';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get deleteSession => 'Delete chat?';

  @override
  String get deleteSessionDescription =>
      'This chat and its uploaded files will be permanently deleted and cannot be recovered. Delete this chat?';

  @override
  String get save => 'Save';

  @override
  String get close => 'Dismiss';

  @override
  String get copy => 'Copy';

  @override
  String get edit => 'Edit';

  @override
  String get userMessage => 'Your message';

  @override
  String get assistantReply => 'Assistant reply';

  @override
  String get messageActions => 'Message actions';

  @override
  String versionPosition(int current, int total) {
    return 'Version $current of $total';
  }

  @override
  String sourceNumber(int index) {
    return 'Source $index';
  }

  @override
  String get openSource => 'Open source';

  @override
  String get stopGeneration => 'Stop generating';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get continueGeneration => 'Continue';

  @override
  String get editMessage => 'Edit message';

  @override
  String get messageVersions => 'Message versions';

  @override
  String get previousVersion => 'Previous version';

  @override
  String get nextVersion => 'Next version';

  @override
  String get deepThinking => 'DeepThink';

  @override
  String thoughtForSeconds(int seconds) {
    return 'Thought for ${seconds}s';
  }

  @override
  String thinkingForSeconds(int seconds) {
    return 'Thinking… ${seconds}s';
  }

  @override
  String get stopped => 'Stopped';

  @override
  String get imageSearching => 'Searching images...';

  @override
  String get searching => 'Searching';

  @override
  String get browsingWeb => 'Browsing the web';

  @override
  String get reading => 'Reading';

  @override
  String get thinking => 'Thinking';

  @override
  String searchingQuery(String query) {
    return 'Searching $query';
  }

  @override
  String get searchingDots => 'Searching...';

  @override
  String get searchStopped => 'Search stopped';

  @override
  String get searchUnavailable => 'Web search is unavailable';

  @override
  String get noSuitableResults => 'No suitable results found';

  @override
  String get noRelevantResults => 'No relevant results found';

  @override
  String searchedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count pages',
      one: 'Found 1 page',
    );
    return '$_temp0';
  }

  @override
  String readPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Read $count pages',
      one: 'Read 1 page',
    );
    return '$_temp0';
  }

  @override
  String get browsePageFailed => 'Could not load the page';

  @override
  String browsingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Browsing $count pages',
      one: 'Browsing 1 page',
    );
    return '$_temp0';
  }

  @override
  String get browseFailed => 'Load failed';

  @override
  String get viewAll => 'View all';

  @override
  String get findFailed => 'Find failed';

  @override
  String get findKeywords => 'Find keywords';

  @override
  String get noMatchingContent => 'No matching content found';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get searchResults => 'Search results';

  @override
  String get composerHint => 'Message or hold to talk';

  @override
  String get composerHintWithAttachments => 'Message';

  @override
  String get composerPlaceholder => 'Enter a message';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get closeAttachmentPanel => 'Close attachment panel';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get photoUnreadable => 'Couldn\'t read this photo';

  @override
  String get send => 'Send';

  @override
  String get smartSearch => 'Search';

  @override
  String get settingsData => 'Data';

  @override
  String get historyImport => 'Import chat history';

  @override
  String get historyImportAction => 'Upload';

  @override
  String get historyImportDescription =>
      'Importing chat history replaces all local chats and attachments. Supports ZIP files exported from DeepSeek.';

  @override
  String get historyImportConfirmTitle => 'Import chat history?';

  @override
  String get historyImportConfirmDescription =>
      'The uploaded chat history will replace all your current chats and attachments. Export a backup first if you need to keep them.';

  @override
  String get historyImportConfirm => 'Import';

  @override
  String get historyImporting => 'Importing...';

  @override
  String get historyImportedOne => 'Imported 1 chat';

  @override
  String historyImported(int count) {
    return 'Imported $count chats';
  }

  @override
  String get historyImportFailed =>
      'Import failed. The file may be invalid or use an old export format.';

  @override
  String get historyExport => 'Export all chats';

  @override
  String get historyExportAction => 'Download';

  @override
  String get historyExportDescription =>
      'Includes all chat history and locally stored images. Other attachments keep file details only. Your API key is not included.';

  @override
  String get historyExporting => 'Exporting...';

  @override
  String get historyExported => 'Export saved';

  @override
  String get historyExportFailed => 'Export failed. Please try again.';

  @override
  String get historyDelete => 'Delete all chats';

  @override
  String get historyDeleteConfirmTitle => 'Delete all chats?';

  @override
  String get historyDeleteConfirmDescription =>
      'All chats and attachments on this device will be permanently deleted and cannot be recovered.';

  @override
  String get historyDeleted => 'All chats deleted';

  @override
  String get historyDeleteFailed => 'Delete failed. Please try again.';

  @override
  String get historyErrorUnrecognized =>
      'File not recognized. Choose a DeepSeek chat history ZIP.';

  @override
  String get historyErrorNewerVersion =>
      'This file uses a newer version. Update the app before importing.';

  @override
  String get historyErrorInvalidVersion =>
      'The file version is invalid and cannot be imported.';

  @override
  String get historyErrorInvalidJson => 'The file is not valid JSON.';

  @override
  String get historyErrorIncomplete =>
      'The file is incomplete and cannot be imported.';

  @override
  String get historyErrorInvalidBranches =>
      'The message branches in this file are corrupted and cannot be imported.';

  @override
  String get historyErrorInvalidFiles =>
      'The attachment data in this file is corrupted and cannot be imported.';

  @override
  String get historyErrorTooLarge => 'The file is too large to import.';

  @override
  String get cancel => 'Cancel';

  @override
  String get historyErrorExportTooLarge => 'The file is too large to export.';

  @override
  String get voiceInput => 'Voice input';

  @override
  String voiceInputRecording(int seconds) {
    return 'Recording ${seconds}s';
  }

  @override
  String get voiceInputStop => 'Stop recording and transcribe';

  @override
  String get voiceInputTranscribing => 'Transcribing…';

  @override
  String get voiceInputCancel => 'Transcribing. Tap to cancel';

  @override
  String get voiceInputPermissionDenied =>
      'Microphone access is denied. Allow it in system settings.';

  @override
  String get voiceInputNoDevice => 'No microphone detected';

  @override
  String get voiceInputFailed =>
      'Speech recognition failed. Please try again later.';

  @override
  String get voiceInputEmpty => 'No speech detected';

  @override
  String get voiceInputLimitReached => 'Maximum recording length reached';

  @override
  String get voiceInputInterrupted => 'Recording interrupted';

  @override
  String get ttsPlay => 'Read aloud';

  @override
  String get ttsStop => 'Stop reading';

  @override
  String get ttsUnavailable => 'This answer cannot be read aloud right now';

  @override
  String get ttsFailed => 'Read-aloud failed. Please try again later.';

  @override
  String get settingsTtsVoice => 'Read-aloud voice';

  @override
  String get settingsTtsVoiceStella => 'Stella · female';

  @override
  String get settingsTtsVoiceTide => 'Tide · male';

  @override
  String get settingsSpeech => 'Speech';

  @override
  String get settingsMicPermission => 'Microphone access';

  @override
  String get settingsMicNotRequested => 'Not requested';

  @override
  String get settingsMicGranted => 'Allowed';

  @override
  String get settingsMicDenied => 'Denied';

  @override
  String get settingsSpeechDescription =>
      'Voice input needs microphone access; read-aloud does not. Works in the foreground only.';

  @override
  String get settingsOpenSystemSettings => 'Open system settings';
}
