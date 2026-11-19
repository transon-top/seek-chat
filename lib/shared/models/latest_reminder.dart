import 'location.dart';

const _weekdaysZh = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// 本轮 `latest_reminder` 内容：日期、星期、所在地、平台、语言，逗号连接。
///
/// 对齐 chat-demo 的 `createLatestReminder`：日期与星期用本地时间；中国省市
/// 只在中文界面下展开，否则只给国家名；未设置所在地时该字段留空。
String buildLatestReminder({
  required String languageCode,
  required UserLocation? location,
  required String platform,
  DateTime? now,
}) {
  final value = now ?? DateTime.now();
  final zh = isChineseLanguage(languageCode);
  return [
    _formatDate(value),
    (zh ? _weekdaysZh : _weekdaysEn)[value.weekday - 1],
    locationName(location, languageCode),
    platform,
    zh ? '中文' : 'English',
  ].join(',');
}

/// 所在地的展示名（`latestReminder.ts` 的 `locationName`）。
String locationName(UserLocation? location, String languageCode) {
  if (location == null) return '';
  if (location.region == 'CN' && isChineseLanguage(languageCode)) {
    final province = provinceByCode(location.province);
    if (province == null) return getRegionName('CN', languageCode) ?? '';
    return cityByCode(province, location.city)?.name ?? province.name;
  }
  return getRegionName(location.region, languageCode) ?? '';
}

/// 平台标记；服务端只接受 `App` 与 `Web`，移动端即 `App`。
String currentPlatformMarker() => 'App';

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
