import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/app/theme.dart';

void main() {
  test('builds light and dark themes with readable status bars', () {
    final light = buildAppTheme(brightness: Brightness.light, chinese: false);
    final dark = buildAppTheme(brightness: Brightness.dark, chinese: false);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.appBarTheme.systemOverlayStyle, SystemUiOverlayStyle.dark);
    expect(dark.appBarTheme.systemOverlayStyle, SystemUiOverlayStyle.light);
  });

  test('raises body line height for Chinese only', () {
    final chinese = buildAppTheme(brightness: Brightness.light, chinese: true);
    final english = buildAppTheme(
      brightness: Brightness.light,
      chinese: false,
    );

    expect(chinese.textTheme.bodyMedium?.height, 1.6);
    expect(english.textTheme.bodyMedium?.height, isNot(1.6));
  });
}
