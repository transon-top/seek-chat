// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get errorNoApiKey => '未设置 API Key，请先在设置中填写。';

  @override
  String errorSaveReplyFailed(String error) {
    return '保存回复失败：$error';
  }

  @override
  String get errorApiKeyEmpty => '请输入 API Key';

  @override
  String get apiErrorUnauthorized => 'API Key 无效';

  @override
  String get apiErrorInsufficientBalance => '余额不足';

  @override
  String get apiErrorTooLarge => '请求内容过大';

  @override
  String get apiErrorRateLimited => '请求过于频繁，请稍后再试';

  @override
  String get apiErrorServerBusy => '服务器繁忙，请稍后再试';

  @override
  String get apiErrorNetwork => '网络错误，请检查连接';

  @override
  String get apiErrorOther => '发生错误，请重试';

  @override
  String replyFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get replyRefused => '内容被安全策略拒绝';
}
