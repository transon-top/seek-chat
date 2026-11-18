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
}
