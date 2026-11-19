import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
    final english = buildAppTheme(brightness: Brightness.light, chinese: false);

    expect(chinese.textTheme.bodyMedium?.height, 1.6);
    expect(english.textTheme.bodyMedium?.height, isNot(1.6));
  });

  test('maps the app seed into the shadcn color scheme', () {
    final light = buildShadTheme(brightness: Brightness.light, chinese: false);
    final dark = buildShadTheme(brightness: Brightness.dark, chinese: true);
    final material = buildAppTheme(
      brightness: Brightness.light,
      chinese: false,
    );

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, material.colorScheme.primary);
    expect(light.colorScheme.background, material.colorScheme.surface);
    expect(
      light.colorScheme.muted,
      material.colorScheme.surfaceContainerHighest,
    );
    expect(light.radius, const BorderRadius.all(Radius.circular(10)));
  });

  test('overrides all shadcn text styles with the system font', () {
    final theme = buildShadTheme(brightness: Brightness.light, chinese: true);
    final text = theme.textTheme;

    for (final style in [
      text.h1Large,
      text.h1,
      text.h2,
      text.h3,
      text.h4,
      text.p,
      text.blockquote,
      text.table,
      text.list,
      text.lead,
      text.large,
      text.small,
      text.muted,
    ]) {
      expect(style.fontFamily, isNull);
    }
    expect(text.p.height, 1.6);
    expect(text.p.fontSize, 16);
  });
}
