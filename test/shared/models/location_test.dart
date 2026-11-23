import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/models/location.dart';

void main() {
  test('normalizeLocation keeps valid countries and Chinese divisions', () {
    expect(
      normalizeLocation({'region': 'US'}),
      const UserLocation(region: 'US'),
    );
    expect(
      normalizeLocation({'region': 'CN'}),
      const UserLocation(region: 'CN'),
    );
    expect(
      normalizeLocation({'region': 'CN', 'province': '330000'}),
      const UserLocation(region: 'CN', province: '330000'),
    );
    expect(
      normalizeLocation({
        'region': 'CN',
        'province': '330000',
        'city': '330100',
      }),
      const UserLocation(region: 'CN', province: '330000', city: '330100'),
    );
  });

  test('normalizeLocation rejects malformed values', () {
    expect(normalizeLocation(null), isNull);
    expect(normalizeLocation('CN'), isNull);
    expect(normalizeLocation(['CN']), isNull);
    expect(normalizeLocation({'region': 42}), isNull);
    expect(normalizeLocation({'region': 'XX'}), isNull);
    // ZH
    // 有市无省、省或市非法、市不属于该省。
    //
    // EN
    // City without province, invalid province or city, and city outside its province.
    expect(normalizeLocation({'region': 'CN', 'city': '330100'}), isNull);
    expect(normalizeLocation({'region': 'CN', 'province': '999999'}), isNull);
    expect(
      normalizeLocation({
        'region': 'CN',
        'province': '330000',
        'city': '110100',
      }),
      isNull,
    );
    expect(normalizeLocation({'region': 'CN', 'province': 330000}), isNull);
  });

  test('getRegionName uses fixed names for Taiwan, Hong Kong and Macao', () {
    expect(getRegionName('TW', 'zh'), '中国台湾');
    expect(getRegionName('TW', 'en'), 'Taiwan, China');
    expect(getRegionName('HK', 'zh'), '中国香港');
    expect(getRegionName('MO', 'en'), 'Macao, China');
    expect(getRegionName('US', 'zh'), '美国');
    expect(getRegionName('XX', 'zh'), isNull);
  });

  test('provinces group cities by code prefix', () {
    final zhejiang = provinces.firstWhere((item) => item.code == '330000');
    expect(zhejiang.name, '浙江省');
    expect(zhejiang.cities.map((item) => item.code), contains('330100'));
    expect(cityByCode(zhejiang, '330100')?.name, '杭州市');
    expect(cityByCode(zhejiang, '110100'), isNull);
    expect(provinceByCode('330000')?.name, '浙江省');
    expect(provinceByCode(null), isNull);
  });
}
