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

  @override
  String errorSaveAttachmentFailed(String error) {
    return '保存附件失败：$error';
  }

  @override
  String get uploadFile => '上传文件';

  @override
  String get uploadFromPhotos => '从相册选择';

  @override
  String get uploadFromFiles => '选择文件';

  @override
  String get uploadUnsupportedFormat =>
      '上传的文件包含暂未支持的文件格式，请转换文件格式后重试。支持 PDF、DOC、XLSX、PPT、图片、文本、代码等。';

  @override
  String uploadMaxMBSize(int size) {
    return '单个文件大小超过限制（${size}MB），请调整后重试';
  }

  @override
  String uploadMaxFiles(int count) {
    return '上传文件最多支持 $count 个';
  }

  @override
  String get uploadFileStatusUploading => '上传中...';

  @override
  String get uploadFileStatusFailed => '上传失败';

  @override
  String uploadRetry(String message) {
    return '$message，点击重试';
  }

  @override
  String get uploadServerBusy => '服务器繁忙';

  @override
  String get uploadParseFailed => '解析失败';

  @override
  String uploadFileCountLimit(String limit) {
    return '已上传文件数达到上限（$limit 个）';
  }

  @override
  String uploadStorageLimit(String limit) {
    return '已上传文件占用空间达到上限（${limit}GB）';
  }

  @override
  String get uploadDeleteFiles => '删除文件';

  @override
  String get removeAttachment => '移除附件';

  @override
  String get retry => '重试';

  @override
  String get previewImage => '查看图片';

  @override
  String get missingAttachment => '原件已丢失';
}
