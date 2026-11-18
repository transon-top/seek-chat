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
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageZh => 'Simplified Chinese';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLocation => 'Location';

  @override
  String get settingsLocationNone => 'Not specified';

  @override
  String get settingsData => 'Data';

  @override
  String get historyImport => 'Import chat history';

  @override
  String get historyImportAction => 'Choose file';

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
  String get historyExportAction => 'Export';

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
}
