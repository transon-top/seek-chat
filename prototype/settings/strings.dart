/// 票 20 原型的中英文案。生产文案在 `lib/l10n/*.arb`，这里只服务原型。
library;

class SettingsStrings {
  const SettingsStrings({required this.zh});

  final bool zh;

  String get title => zh ? '设置' : 'Settings';
  String get prototypeBadge => zh ? '原型控制' : 'Prototype';
  String get cancel => zh ? '取消' : 'Cancel';
  String get done => zh ? '完成' : 'Done';
  String get delete => zh ? '删除' : 'Delete';
  String get clear => zh ? '清除' : 'Clear';
  String get placeholderToast => zh ? '原型占位' : 'Prototype placeholder';
  String get systemSettings => zh ? '系统设置' : 'System settings';
  String get mockDataNote => zh ? '设置项均为原型假数据' : 'All settings are mocked';

  String get sectionAccount => zh ? '账户' : 'Account';
  String get sectionChat => zh ? '对话' : 'Chat';
  String get sectionAppearance => zh ? '外观' : 'Appearance';
  String get sectionLocale => zh ? '语言与位置' : 'Language & location';
  String get sectionSpeech => zh ? '语音' : 'Speech';
  String get sectionData => zh ? '数据管理' : 'Data';

  String get apiKey => 'DeepSeek API Key';
  String get apiKeySaved => zh ? '已保存 · sk-••••7f3a' : 'Saved · sk-••••7f3a';
  String get apiKeyMissing => zh ? '未设置' : 'Not set';
  String get apiKeyDialogDescription => zh
      ? '只保存在设备安全存储中，不随导出迁移。'
      : 'Stored in the device keystore. Never included in exports.';
  String get apiKeyVerify => zh ? '保存并校验' : 'Save and verify';
  String get verifying => zh ? '校验中…' : 'Verifying…';
  String get apiKeyVerified => zh ? 'Key 校验通过（原型模拟）' : 'Key verified (mock)';
  String get clearKey => zh ? '清除已保存的 Key' : 'Clear saved key';
  String get clearKeyTitle => zh ? '清除 API Key？' : 'Clear API key?';
  String get clearKeyDescription => zh
      ? '清除后需要重新填写才能发送消息。'
      : 'You will need to enter it again before sending.';

  String get model => zh ? '模型' : 'Model';
  String get modelFixed => zh ? 'v1 固定模型' : 'Fixed in v1';
  String get deepThinking => zh ? '深度思考' : 'Deep thinking';
  String get smartSearch => zh ? '智能搜索' : 'Smart search';
  String get toggleHint =>
      zh ? '默认值；输入区也可随时切换' : 'Default; also toggled in the composer';

  String get theme => zh ? '主题' : 'Theme';
  String get themeSystem => zh ? '跟随系统' : 'System';
  String get themeLight => zh ? '浅色' : 'Light';
  String get themeDark => zh ? '深色' : 'Dark';

  String get language => zh ? '语言' : 'Language';
  String get languageZh => '简体中文';
  String get languageEn => 'English';
  String get languageNote => zh
      ? '切换后界面立即生效，已生成的回复保持原样。'
      : 'The interface updates immediately. Existing replies stay as-is.';

  String get location => zh ? '位置信息' : 'Location';
  String get locationUnset => zh ? '未设置' : 'Not set';
  String get locationNone => zh ? '不指定' : 'None';
  String get locationProvince => zh ? '省份' : 'Province';
  String get locationCity => zh ? '城市' : 'City';
  String get locationRegion => zh ? '国家 / 地区' : 'Country / region';
  String get locationNote => zh
      ? '只随消息发送给你配置的 API，不申请定位权限。'
      : 'Sent only with messages to your API. No location permission is requested.';

  String get ttsVoice => zh ? '朗读音色' : 'Read-aloud voice';
  String get voiceStella => zh ? 'Stella · 女声' : 'Stella · female';
  String get voiceTide => zh ? 'Tide · 男声' : 'Tide · male';
  String get micPermission => zh ? '麦克风权限' : 'Microphone';
  String get micNotRequested => zh ? '未请求' : 'Not requested';
  String get micExplanation => zh
      ? '语音输入需要麦克风权限；朗读不需要。v1 只在前台工作。'
      : 'Voice input needs microphone access; read-aloud does not. v1 works in the foreground only.';

  String get importHistory => zh ? '导入历史对话' : 'Import history';
  String get importDescription => zh
      ? '会覆盖全部本地对话和附件，支持 DeepSeek 导出的 ZIP 文件。'
      : 'Replaces all local chats and images. Accepts ZIP files exported by DeepSeek.';
  String get importAction => zh ? '选择文件' : 'Choose file';
  String get importPickTitle => zh ? '选择导入文件' : 'Choose a file';
  String get importPickNote =>
      zh ? '原型用假文件代替系统文件选择器。' : 'Mock files replace the system picker.';
  String get importConfirmTitle =>
      zh ? '确认导入历史对话？' : 'Import chat history?';
  String get importConfirmDescription => zh
      ? '上传的历史对话会覆盖当前所有对话和附件。如需保留，请先导出备份。'
      : 'The selected file replaces all chats and attachments. Export a backup first if needed.';
  String get importConfirm => zh ? '确认导入' : 'Import';
  String get importing => zh ? '正在导入…' : 'Importing…';
  String get importingNote =>
      zh ? '请保持应用在前台。' : 'Keep the app in the foreground.';
  String get importFailed => zh ? '导入失败：文件过大' : 'Import failed: file too large';
  String imported(int count) =>
      zh ? '已导入 $count 个对话' : 'Imported $count chat${count == 1 ? '' : 's'}';

  String get exportHistory => zh ? '导出所有历史对话' : 'Export all chats';
  String get exportDescription => zh
      ? '包含对话和图片原件；不含 API Key 与设置。'
      : 'Includes chats and original images. Excludes the API key and settings.';
  String get exportAction => zh ? '导出' : 'Export';
  String get exporting => zh ? '正在导出…' : 'Exporting…';
  String get exported => zh ? '导出文件已保存' : 'Export saved';
  String get exportFailed => zh ? '导出失败，请重试' : 'Export failed. Try again.';

  String get deleteAll => zh ? '删除全部对话' : 'Delete all chats';
  String get deleteAllDescription => zh
      ? '只删除会话与附件，保留设置和 API Key。'
      : 'Removes chats and attachments. Keeps settings and the API key.';
  String get deleteAllButton => zh ? '全部删除' : 'Delete all';
  String get deleteAllTitle => zh ? '删除全部对话？' : 'Delete all chats?';
  String get deleteAllConfirmDescription => zh
      ? '所有会话、消息和附件将从本机删除，且无法撤销。'
      : 'All chats, messages and attachments will be deleted. This cannot be undone.';
  String get deleting => zh ? '正在删除…' : 'Deleting…';
  String get deleted => zh ? '已删除全部对话（原型）' : 'All chats deleted (mock)';

  String get chooseProvinceFirst => zh ? '先选择省份' : 'Choose a province first';

  String get devChineseSystem => zh ? '中文系统（省 / 市）' : 'Chinese system (province / city)';
  String get devOtherSystem => zh ? '其他系统（国家 / 列表）' : 'Other system (country list)';
  String get devExportOutcome => zh ? '导出结果' : 'Export outcome';
  String get devSuccess => zh ? '成功' : 'Success';
  String get devFailure => zh ? '失败' : 'Failure';
  String get devNote =>
      zh ? '只影响位置选择器形态，不属于设置。' : 'Only changes the location picker. Not a setting.';
}

/// 原型用假数据；真实省市表在 `lib/shared/models/location_data.dart`。
const prototypeProvinces = <(String, List<String>)>[
  ('北京市', ['北京市']),
  ('浙江省', ['杭州市', '宁波市', '温州市']),
  ('广东省', ['广州市', '深圳市', '珠海市']),
  ('四川省', ['成都市', '绵阳市']),
];

const prototypeRegions = <String>[
  'Australia',
  'Canada',
  'China',
  'France',
  'Germany',
  'Japan',
  'Singapore',
  'United Kingdom',
  'United States',
];

class PrototypeFile {
  const PrototypeFile(this.name, this.size, {this.tooLarge = false});

  final String name;
  final String size;
  final bool tooLarge;
}

const prototypeFiles = <PrototypeFile>[
  PrototypeFile('chat-backup-2026-11-18.zip', '12.4 MB'),
  PrototypeFile('chat-backup-2026-11-18-超大.zip', '268 MB', tooLarge: true),
];
