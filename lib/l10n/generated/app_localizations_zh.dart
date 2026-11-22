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
  String get apiErrorContentRejected => '内容未通过安全审核，请修改后重试';

  @override
  String get apiErrorOther => '发生错误，请重试';

  @override
  String replyFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get replyFailedTitle => '生成失败';

  @override
  String get replyRefused => '你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。';

  @override
  String get replyImageBlocked => '图片未通过内容安全审核，请移除后重试。';

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

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsEntry => '设置';

  @override
  String get settingsGeneral => '通用设置';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsFontSize => '字体大小';

  @override
  String get settingsFontSizeSystem => '跟随系统';

  @override
  String get settingsFontSizeStandard => '标准';

  @override
  String get settingsFontSizeSmallest => '最小';

  @override
  String get settingsFontSizeSmall => '小';

  @override
  String get settingsFontSizeMedium => '较小';

  @override
  String get settingsFontSizeLarge => '较大';

  @override
  String get settingsFontSizeLarger => '大';

  @override
  String get settingsFontSizeLargest => '最大';

  @override
  String get settingsClearKey => '清除已保存的 Key';

  @override
  String get settingsApiKeySaved => '已保存';

  @override
  String get settingsApiKeyPrompt => '输入 API Key 开始使用';

  @override
  String get settingsApiKeyPlaceholder => '请输入 API Key';

  @override
  String get settingsApiKeyConfirm => '确定';

  @override
  String get settingsApiKeyVerifying => '正在验证…';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsProvincePlaceholder => '请选择省份';

  @override
  String get settingsCityPlaceholder => '请选择市';

  @override
  String get settingsLocation => '位置信息';

  @override
  String get settingsLocationNone => '不指定';

  @override
  String get settingsLocationDescription => '只随消息发送给你配置的 API，不申请定位权限。';

  @override
  String get newChat => '开启新对话';

  @override
  String get openSessionList => '打开会话列表';

  @override
  String get sessionActions => '会话操作';

  @override
  String get sessionGroupToday => '今天';

  @override
  String get sessionGroupYesterday => '昨天';

  @override
  String get sessionGroupLast7Days => '7 天内';

  @override
  String get sessionGroupEarlier => '更早';

  @override
  String get sessionGroupPinned => '置顶';

  @override
  String get searchChatsPlaceholder => '搜索对话内容…';

  @override
  String get searchBack => '返回会话列表';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get searchNoResults => '暂无相关结果';

  @override
  String get selectChats => '多选';

  @override
  String get selectionTitle => '选择对话';

  @override
  String selectionCount(int count) {
    return '已选择 $count 个对话';
  }

  @override
  String get exitSelection => '退出多选';

  @override
  String get pinSession => '置顶';

  @override
  String get unpinSession => '取消置顶';

  @override
  String deleteSessionsTitle(int count) {
    return '删除 $count 个对话';
  }

  @override
  String get sessionLoading => '正在加载会话…';

  @override
  String get sessionsLoadFailed => '无法加载会话';

  @override
  String get chatEmptyTitle => '嗨! 今天想聊些什么?';

  @override
  String get noSessions => '还没有会话';

  @override
  String get untitledChat => '新对话';

  @override
  String get renameSession => '重命名会话';

  @override
  String get rename => '重命名';

  @override
  String get delete => '删除';

  @override
  String get deleteSession => '永久删除对话';

  @override
  String get deleteSessionDescription => '删除后，该对话及其中上传的文件将不可恢复。确认删除吗？';

  @override
  String get save => '保存';

  @override
  String get close => '关闭';

  @override
  String get copy => '复制';

  @override
  String get edit => '编辑';

  @override
  String get userMessage => '你的消息';

  @override
  String get assistantReply => '助手回复';

  @override
  String get messageActions => '消息操作';

  @override
  String versionPosition(int current, int total) {
    return '第 $current 个，共 $total 个';
  }

  @override
  String sourceNumber(int index) {
    return '来源 $index';
  }

  @override
  String get openSource => '打开来源';

  @override
  String get stopGeneration => '停止生成';

  @override
  String get regenerate => '重新生成';

  @override
  String get continueGeneration => '继续生成';

  @override
  String get editMessage => '编辑提问';

  @override
  String get messageVersions => '消息版本';

  @override
  String get previousVersion => '上一个版本';

  @override
  String get nextVersion => '下一个版本';

  @override
  String get deepThinking => '深度思考';

  @override
  String thoughtForSeconds(int seconds) {
    return '已思考（用时 $seconds 秒）';
  }

  @override
  String thinkingForSeconds(int seconds) {
    return '思考中… $seconds 秒';
  }

  @override
  String get stopped => '已停止';

  @override
  String get imageSearching => '图像搜索中...';

  @override
  String get searching => '正在搜索';

  @override
  String get browsingWeb => '正在浏览网页';

  @override
  String get reading => '正在阅读';

  @override
  String get thinking => '正在思考';

  @override
  String searchingQuery(String query) {
    return '搜索 $query';
  }

  @override
  String get searchingDots => '搜索中...';

  @override
  String get searchStopped => '搜索已停止';

  @override
  String get searchUnavailable => '联网搜索暂不可用';

  @override
  String get noSuitableResults => '未搜索到合适内容';

  @override
  String get noRelevantResults => '未搜索到相关内容';

  @override
  String searchedPages(int count) {
    return '搜索到 $count 个网页';
  }

  @override
  String readPages(int count) {
    return '已阅读 $count 个网页';
  }

  @override
  String get browsePageFailed => '浏览页面失败';

  @override
  String browsingPages(int count) {
    return '浏览 $count 个页面';
  }

  @override
  String get browseFailed => '浏览失败';

  @override
  String get viewAll => '查看全部';

  @override
  String get findFailed => '查找失败';

  @override
  String get findKeywords => '查找关键词';

  @override
  String get noMatchingContent => '未查找到相关内容';

  @override
  String pagesCount(int count) {
    return '$count 个网页';
  }

  @override
  String get searchResults => '搜索结果';

  @override
  String get composerHint => '发消息或按住说话';

  @override
  String get composerHintWithAttachments => '发消息';

  @override
  String get composerPlaceholder => '给 Fleepseek 发送消息';

  @override
  String get addAttachment => '添加附件';

  @override
  String get closeAttachmentPanel => '收起附件面板';

  @override
  String get takePhoto => '拍照';

  @override
  String get photoUnreadable => '无法读取这张照片';

  @override
  String get photoPermissionDenied => '无法访问照片';

  @override
  String get photoLimitedManage => '管理';

  @override
  String get photoLimitedManageSemantics => '管理可访问照片';

  @override
  String get photoStripEmpty => '没有最近照片';

  @override
  String get photoStripLoadFailed => '无法读取照片';

  @override
  String photoTileSelected(int index) {
    return '照片，第 $index 张，已选';
  }

  @override
  String photoTileUnselected(int index) {
    return '照片，第 $index 张，未选';
  }

  @override
  String get send => '发送';

  @override
  String get smartSearch => '智能搜索';

  @override
  String get settingsData => '数据管理';

  @override
  String get historyImport => '导入历史对话';

  @override
  String get historyImportAction => '上传';

  @override
  String get historyImportDescription =>
      '导入历史对话会覆盖全部本地对话和附件，支持 DeepSeek 导出的 ZIP 文件。';

  @override
  String get historyImportConfirmTitle => '确认导入历史对话？';

  @override
  String get historyImportConfirmDescription =>
      '上传的历史对话会覆盖当前所有对话和附件。如需保留，请先导出备份。';

  @override
  String get historyImportConfirm => '确认导入';

  @override
  String get historyImporting => '正在导入…';

  @override
  String get historyImportedOne => '已导入 1 个对话';

  @override
  String historyImported(int count) {
    return '已导入 $count 个对话';
  }

  @override
  String get historyImportFailed => '文件导入失败，可能是格式错误或使用了旧版导出文件。';

  @override
  String get historyExport => '导出所有历史对话';

  @override
  String get historyExportAction => '下载';

  @override
  String get historyExportDescription =>
      '包含所有历史对话及本地图片原件；其他附件仅保留文件信息，不包含 API Key。';

  @override
  String get historyExporting => '正在导出…';

  @override
  String get historyExported => '导出文件已保存';

  @override
  String get historyExportFailed => '导出失败，请重试';

  @override
  String get historyDelete => '删除所有对话';

  @override
  String get historyDeleteConfirmTitle => '删除所有对话？';

  @override
  String get historyDeleteConfirmDescription => '本机全部对话与附件将被永久删除，且无法恢复。';

  @override
  String get historyDeleted => '已删除全部对话';

  @override
  String get historyDeleteFailed => '删除失败，请重试';

  @override
  String get historyErrorUnrecognized => '无法识别该文件，请选择 DeepSeek 导出的历史对话 ZIP 文件';

  @override
  String get historyErrorNewerVersion => '文件版本过新，请升级应用后再导入';

  @override
  String get historyErrorInvalidVersion => '文件版本无效，无法导入';

  @override
  String get historyErrorInvalidJson => '文件不是有效的 JSON';

  @override
  String get historyErrorIncomplete => '文件内容不完整，无法导入';

  @override
  String get historyErrorInvalidBranches => '文件中的消息分支已损坏，无法导入';

  @override
  String get historyErrorInvalidFiles => '文件中的附件数据已损坏，无法导入';

  @override
  String get historyErrorTooLarge => '文件过大，无法导入';

  @override
  String get cancel => '取消';

  @override
  String get historyErrorExportTooLarge => '文件过大，无法导出';

  @override
  String get voiceInputPermissionDenied => '无法使用麦克风，请在系统设置中允许访问';

  @override
  String get voiceInputNoDevice => '未检测到麦克风';

  @override
  String get voiceInputFailed => '语音识别失败，请稍后再试';

  @override
  String get voiceInputEmpty => '未识别到内容';

  @override
  String get voiceInputLimitReached => '已达到单次录音时长上限';

  @override
  String get voiceInputInterrupted => '录音已中断';

  @override
  String get holdToTalk => '按住说话';

  @override
  String get voiceHoldToSend => '松手发送，上滑取消';

  @override
  String get voiceReleaseToCancel => '松开取消';

  @override
  String get voiceRecognizing => '识别中';

  @override
  String get voiceMicGrantedRetry => '已授权麦克风，请再按住说话';

  @override
  String get voiceRecordSemantics => '录音中，双击结束并发送';

  @override
  String get voiceCancelRecording => '取消录音';

  @override
  String get voiceCancelled => '已取消';

  @override
  String get voiceRecognizingSemantics => '正在识别';

  @override
  String get voiceSendFailedInserted => '发送失败，已放入输入框';

  @override
  String get voiceInsertedGenerating => '生成中，转写内容已插入输入框';

  @override
  String get voiceInsertedUploading => '附件上传中，转写内容已插入输入框';

  @override
  String get voiceInsertedNotSent => '转写内容已插入输入框，未自动发送';

  @override
  String get ttsPlay => '朗读';

  @override
  String get ttsStop => '停止朗读';

  @override
  String get ttsUnavailable => '这条回答暂时无法朗读';

  @override
  String get ttsFailed => '朗读失败，请稍后再试';

  @override
  String get settingsTtsVoice => '朗读音色';

  @override
  String get settingsTtsVoiceStella => 'Stella · 女声';

  @override
  String get settingsTtsVoiceTide => 'Tide · 男声';

  @override
  String get settingsSpeech => '语音';

  @override
  String get settingsMicPermission => '麦克风权限';

  @override
  String get settingsMicNotRequested => '未请求';

  @override
  String get settingsMicGranted => '已允许';

  @override
  String get settingsMicDenied => '已拒绝';

  @override
  String get settingsSpeechDescription => '语音输入需要麦克风权限；朗读不需要。v1 只在前台工作。';

  @override
  String get settingsOpenSystemSettings => '打开系统设置';
}
