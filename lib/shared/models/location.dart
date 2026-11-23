import 'location_data.dart';

/// ZH
/// 用户所在地：国家/地区代码，中国（`CN`）可再带省与市。
///
/// 取值与校验对齐 chat-demo 的 `location.ts`。
///
/// EN
/// User location: a country/region code; China (`CN`) may also include province and city.
///
/// Values and validation align with `location.ts` in chat-demo.
final class UserLocation {
  const UserLocation({required this.region, this.province, this.city});

  final String region;
  final String? province;
  final String? city;

  Map<String, Object?> toJson() => {
    'region': region,
    if (province != null) 'province': province,
    if (city != null) 'city': city,
  };

  @override
  bool operator ==(Object other) =>
      other is UserLocation &&
      other.region == region &&
      other.province == province &&
      other.city == city;

  @override
  int get hashCode => Object.hash(region, province, city);
}

final class City {
  const City({required this.code, required this.name});

  final String code;
  final String name;
}

final class Province {
  const Province({
    required this.code,
    required this.name,
    required this.cities,
  });

  final String code;
  final String name;
  final List<City> cities;
}

/// ZH
/// 省级行政区与下辖城市，顺序沿用 chat-demo。
///
/// EN
/// Province-level regions and their cities, in chat-demo order.
final List<Province> provinces = [
  for (final province in provinceNames.entries)
    Province(
      code: province.key,
      name: province.value,
      cities: [
        for (final city in cityNames.entries)
          if (city.key.startsWith(province.key.substring(0, 2)))
            City(code: city.key, name: city.value),
      ],
    ),
];

Province? provinceByCode(String? code) {
  for (final province in provinces) {
    if (province.code == code) return province;
  }
  return null;
}

City? cityByCode(Province? province, String? code) {
  for (final city in province?.cities ?? const <City>[]) {
    if (city.code == code) return city;
  }
  return null;
}

/// ZH
/// 界面语言代码是否中文；决定 `/ 中文` 还是 `/ English` 的地区名称。
///
/// EN
/// Whether the UI language code is Chinese; picks Chinese or English region names.
bool isChineseLanguage(String languageCode) =>
    languageCode.toLowerCase().startsWith('zh');

/// ZH
/// 地区名称；未知代码返回 null。港澳台使用固定名称覆盖。
///
/// EN
/// Region name; returns null for unknown codes. Hong Kong, Macao, and Taiwan use fixed overrides.
String? getRegionName(String code, String languageCode) {
  final zh = isChineseLanguage(languageCode);
  final key = zh ? 'zh' : 'en';
  return regionNameOverrides[key]?[code] ??
      (zh ? regionNamesZh : regionNamesEn)[code];
}

/// ZH
/// 校验并收敛本地保存的所在地；结构不合法时返回 null（chat-demo `normalizeLocation`）。
///
/// EN
/// Validate and normalize the stored location; null if invalid (chat-demo `normalizeLocation`).
UserLocation? normalizeLocation(Object? value) {
  if (value is! Map) return null;
  final region = value['region'];
  if (region is! String || !regionCodes.contains(region)) return null;
  if (region != 'CN') return UserLocation(region: region);

  final provinceCode = value['province'];
  final cityCode = value['city'];
  if (provinceCode == null) {
    return cityCode == null ? const UserLocation(region: 'CN') : null;
  }
  if (provinceCode is! String) return null;
  final province = provinceByCode(provinceCode);
  if (province == null) return null;
  if (cityCode == null) {
    return UserLocation(region: 'CN', province: province.code);
  }
  if (cityCode is! String) return null;
  final city = cityByCode(province, cityCode);
  return city == null
      ? null
      : UserLocation(region: 'CN', province: province.code, city: city.code);
}
