import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/code_field.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:open_chat/app/markdown_theme.dart';
import 'package:open_chat/features/chat/markdown_view.dart';
import 'package:open_chat/features/chat/reply_view.dart';
import 'package:open_chat/shared/widgets/horizontal_fade_scroll.dart';
import 'package:val_latex_flutter/val_latex_flutter.dart' show Math;

Source _source(int index) => Source(
  index: index,
  url: 'https://source$index.example',
  title: 'Source $index',
  siteName: 'source$index.example',
  publishedAt: null,
  snippet: null,
  siteIcon: null,
);

void main() {
  Widget app(
    String text, {
    bool streaming = false,
    List<Source>? sources,
    bool disableLinks = false,
  }) => MaterialApp(
    home: Scaffold(
      body: MarkdownView(
        text: text,
        streaming: streaming,
        sources: sources,
        disableLinks: disableLinks,
      ),
    ),
  );

  Future<void> pumpMarkdown(
    WidgetTester tester,
    String data, {
    bool streaming = false,
    List<Source>? sources,
    bool disableLinks = false,
  }) async {
    await tester.pumpWidget(
      app(
        data,
        streaming: streaming,
        sources: sources,
        disableLinks: disableLinks,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wraps a table in a horizontally fading scroller', (
    tester,
  ) async {
    await pumpMarkdown(tester, '| 左 | 右 |\n| --- | --- |\n| 1 | 2 |');

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(HorizontalFadeScroll), findsOneWidget);
  });

  testWidgets('renders table cells as plain text without nested markdown', (
    tester,
  ) async {
    await pumpMarkdown(tester, '| **标题** | 值 |\n| --- | --- |\n| 1 | 2 |');

    expect(
      find.descendant(
        of: find.byType(Table),
        matching: find.byType(GptMarkdown),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(Table), matching: find.text('标题')),
      findsOneWidget,
    );
  });

  testWidgets('drops the fade mask when the table fits', (tester) async {
    await pumpMarkdown(tester, '| 左 | 右 |\n| --- | --- |\n| 1 | 2 |');

    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('keeps the fade mask when the table overflows', (tester) async {
    final header = List.generate(9, (index) => '列$index').join(' | ');
    final divider = List.filled(9, '---').join(' | ');
    final body = List.generate(9, (index) => '$index').join(' | ');
    await pumpMarkdown(tester, '| $header |\n| $divider |\n| $body |');

    expect(find.byType(ShaderMask), findsNWidgets(2));
  });

  testWidgets('renders markdown syntax as text', (tester) async {
    await pumpMarkdown(tester, '# 标题\n\n**粗体**');

    expect(find.textContaining('标题', findRichText: true), findsWidgets);
    expect(find.textContaining('粗体', findRichText: true), findsWidgets);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('# ', findRichText: true), findsNothing);
  });

  testWidgets('renders task items as checkboxes without list bullets', (
    tester,
  ) async {
    await pumpMarkdown(tester, '- [x] 已完成任务\n- [ ] 未完成任务');

    expect(find.byType(Checkbox), findsNothing);
    // 选中态自绘（☑ 在 Android 会变成彩色 emoji），未选中用 □ 字形。
    expect(find.text('□'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_CheckedBox',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('[x]', findRichText: true), findsNothing);
    expect(find.textContaining('已完成任务', findRichText: true), findsWidgets);
  });

  testWidgets('spaces list items 6px apart like the official app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            text: '1. alpha\n2. beta\n\n- [ ] task a\n- [ ] task b',
            textStyle: TextStyle(fontSize: 16, height: 28 / 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double top(String text) => tester
        .getTopLeft(find.textContaining(text, findRichText: true).first)
        .dy;
    expect(top('beta') - top('alpha'), 28 + 6);
    expect(top('task b') - top('task a'), 28 + 6);

    final marker = tester.widget<Text>(find.text('1.'));
    expect(marker.style?.color, AppMarkdownColors.light.labelTertiary);
    expect(marker.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('renders LaTeX written with \\(...\\)', (tester) async {
    await pumpMarkdown(tester, r'公式 \(x^2 + y^2\)');

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\(', findRichText: true), findsNothing);
  });

  testWidgets(r'renders LaTeX written with \[...\]', (tester) async {
    await pumpMarkdown(tester, r'\[\frac{a}{b}\]');

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\[', findRichText: true), findsNothing);
  });

  testWidgets(r'keeps a dollar amount as text instead of maths', (
    tester,
  ) async {
    await pumpMarkdown(tester, r'It costs $5 and \(x\) is maths');

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'$5', findRichText: true), findsWidgets);
  });

  testWidgets('does not crash on a half-streamed formula', (tester) async {
    await pumpMarkdown(tester, r'half \(\frac{a}{');

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a citation token as a numbered badge', (tester) async {
    await pumpMarkdown(
      tester,
      'answer[citation:2]',
      sources: [_source(1), _source(2)],
    );

    expect(find.textContaining('[citation:', findRichText: true), findsNothing);
    expect(find.textContaining('answer', findRichText: true), findsWidgets);
    expect(find.textContaining('2', findRichText: true), findsWidgets);
  });

  testWidgets('removes citation tokens without a matching source', (
    tester,
  ) async {
    await pumpMarkdown(
      tester,
      'answer[citation:99] and [citation:1]',
      sources: [_source(1)],
    );

    expect(
      find.textContaining('[citation:99]', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('[citation:1]', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('1', findRichText: true), findsWidgets);
  });

  testWidgets('keeps citation tokens as text when no sources are given', (
    tester,
  ) async {
    await pumpMarkdown(tester, 'answer[citation:1]');

    expect(
      find.textContaining('[citation:1]', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('does not parse citation tokens inside code', (tester) async {
    await pumpMarkdown(
      tester,
      '`[citation:1]`\n\n```\n[citation:1]\n```',
      sources: [_source(1)],
    );

    expect(
      find.textContaining('[citation:1]', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('renders links as plain text when links are disabled', (
    tester,
  ) async {
    await pumpMarkdown(
      tester,
      '[label](https://example.com)',
      disableLinks: true,
    );

    expect(find.textContaining('label', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a mermaid fence as an interactive diagram', (
    tester,
  ) async {
    await pumpMarkdown(tester, '''
```mermaid
graph TD
  A --> B
```
''');

    expect(find.byType(MermaidView), findsOneWidget);
  });

  testWidgets('renders an unclosed mermaid fence as code', (tester) async {
    await pumpMarkdown(tester, '```mermaid\ngraph TD\n  A --> B');

    expect(find.byType(MermaidView), findsNothing);
    expect(find.byType(CodeField), findsOneWidget);
  });

  testWidgets('switches a mermaid fence to a diagram once it closes', (
    tester,
  ) async {
    await pumpMarkdown(
      tester,
      '```mermaid\ngraph TD\n  A --> B',
      streaming: true,
    );
    expect(find.byType(MermaidView), findsNothing);

    await pumpMarkdown(
      tester,
      '```mermaid\ngraph TD\n  A --> B\n```',
      streaming: true,
    );
    expect(find.byType(MermaidView), findsOneWidget);
  });

  testWidgets('keeps non-mermaid fences as code', (tester) async {
    await pumpMarkdown(tester, '```dart\nfinal x = 1;\n```');

    expect(find.byType(MermaidView), findsNothing);
    expect(find.byType(CodeField), findsOneWidget);
  });

  testWidgets('updates when the streamed text grows', (tester) async {
    await tester.pumpWidget(app('**hel'));
    await tester.pumpWidget(app('**hello** world'));
    await tester.pumpAndSettle();

    expect(find.textContaining('hello', findRichText: true), findsWidgets);
    expect(find.textContaining('world', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders markdown images as links instead of loading them', (
    tester,
  ) async {
    await pumpMarkdown(tester, '![chart](https://example.com/a.png)');

    expect(find.byType(Image), findsNothing);
    expect(
      find.textContaining('https://example.com/a.png', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('renders a scheme-less image address as an https link', (
    tester,
  ) async {
    await pumpMarkdown(tester, '![chart](example.com/a.png)');

    expect(
      find.textContaining('https://example.com/a.png', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('falls back to plain text for an oversized block', (
    tester,
  ) async {
    final oversized = 'a' * (MarkdownView.plainTextLimit + 1);
    await pumpMarkdown(tester, oversized);

    expect(find.byType(GptMarkdown), findsNothing);
    expect(find.textContaining('aaaa', findRichText: true), findsWidgets);
  });

  testWidgets('coalesces streaming updates and shows the final text at once', (
    tester,
  ) async {
    await tester.pumpWidget(app('a', streaming: true));
    await tester.pumpWidget(app('ab', streaming: true));
    // 逐字淡入会把新追加的字符推迟到后续帧。
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.textContaining('ab', findRichText: true), findsWidgets);

    await tester.pumpWidget(app('abc', streaming: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.textContaining('abc', findRichText: true), findsNothing);

    await tester.pumpWidget(app('abcd', streaming: true));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('abcd', findRichText: true), findsWidgets);

    await tester.pumpWidget(app('abcde'));
    expect(find.textContaining('abcde', findRichText: true), findsWidgets);
  });

  testWidgets('builds no citation pattern for an empty source list', (
    tester,
  ) async {
    await pumpMarkdown(tester, 'answer[citation:1]', sources: const []);

    expect(
      tester.widget<GptMarkdown>(find.byType(GptMarkdown)).inlinePatterns,
      isNull,
    );
    expect(
      find.textContaining('[citation:1]', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('reuses the rendered markdown until a source changes', (
    tester,
  ) async {
    const text = 'answer[citation:1]';
    final sources = [_source(1)];
    await tester.pumpWidget(app(text, sources: sources));
    await tester.pumpAndSettle();
    final first = tester.widget<GptMarkdown>(find.byType(GptMarkdown));

    await tester.pumpWidget(app(text, sources: sources));
    expect(
      identical(first, tester.widget<GptMarkdown>(find.byType(GptMarkdown))),
      isTrue,
    );

    await tester.pumpWidget(
      app(text, sources: [_source(1)..title = 'Renamed']),
    );
    await tester.pumpAndSettle();
    expect(
      identical(first, tester.widget<GptMarkdown>(find.byType(GptMarkdown))),
      isFalse,
    );
  });

  testWidgets('passes the streaming flag to the markdown renderer', (
    tester,
  ) async {
    await tester.pumpWidget(app('partial', streaming: true));
    expect(
      tester.widget<GptMarkdown>(find.byType(GptMarkdown)).isStreaming,
      isTrue,
    );

    await tester.pumpWidget(app('partial'));
    expect(
      tester.widget<GptMarkdown>(find.byType(GptMarkdown)).isStreaming,
      isFalse,
    );
  });

  testWidgets('falls back to the mermaid source as a code block', (
    tester,
  ) async {
    await pumpMarkdown(tester, '```mermaid\nnot a diagram\n```');

    expect(tester.takeException(), isNull);
    expect(find.byType(MermaidView), findsNothing);
    expect(find.byType(CodeField), findsOneWidget);
    expect(
      find.textContaining('not a diagram', findRichText: true),
      findsWidgets,
    );
  });
}
