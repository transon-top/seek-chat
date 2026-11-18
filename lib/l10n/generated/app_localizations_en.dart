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
  String get apiErrorOther => 'Something went wrong. Please try again.';

  @override
  String replyFailed(String error) {
    return 'Generation failed: $error';
  }

  @override
  String get replyRefused => 'The content was blocked by safety policy.';

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
}
