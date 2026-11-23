import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/shared/models/latest_reminder.dart';
import 'package:seek_chat/shared/models/location.dart';

void main() {
  final now = DateTime(2026, 11, 18, 9, 30);

  test('uses the selected city for a Chinese location', () {
    expect(
      buildLatestReminder(
        languageCode: 'zh',
        location: const UserLocation(
          region: 'CN',
          province: '330000',
          city: '330100',
        ),
        platform: 'iOS',
        now: now,
      ),
      '2026-11-18,星期三,杭州市,iOS,中文',
    );
  });

  test('falls back to the province name, then the country name', () {
    expect(
      buildLatestReminder(
        languageCode: 'zh',
        location: const UserLocation(region: 'CN', province: '330000'),
        platform: 'Android',
        now: now,
      ),
      '2026-11-18,星期三,浙江省,Android,中文',
    );
    expect(
      buildLatestReminder(
        languageCode: 'zh',
        location: const UserLocation(region: 'CN'),
        platform: 'Android',
        now: now,
      ),
      '2026-11-18,星期三,中国,Android,中文',
    );
  });

  test('uses the localized region name outside Chinese mode', () {
    expect(
      buildLatestReminder(
        languageCode: 'en',
        location: const UserLocation(region: 'US'),
        platform: 'iOS',
        now: now,
      ),
      '2026-11-18,Wednesday,United States,iOS,English',
    );
    // ZH
    // 界面语言为英文时不展开中国省市，只发送国家名。
    //
    // EN
    // With an English UI, Chinese provinces and cities are not expanded; only the country is sent.
    expect(
      buildLatestReminder(
        languageCode: 'en',
        location: const UserLocation(
          region: 'CN',
          province: '330000',
          city: '330100',
        ),
        platform: 'iOS',
        now: now,
      ),
      '2026-11-18,Wednesday,China,iOS,English',
    );
    expect(
      buildLatestReminder(
        languageCode: 'zh',
        location: const UserLocation(region: 'TW'),
        platform: 'iOS',
        now: now,
      ),
      '2026-11-18,星期三,中国台湾,iOS,中文',
    );
  });

  test('keeps an empty location segment when no location is set', () {
    expect(
      buildLatestReminder(
        languageCode: 'zh',
        location: null,
        platform: 'Android',
        now: now,
      ),
      '2026-11-18,星期三,,Android,中文',
    );
  });
}
