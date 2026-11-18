import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/code_field.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:open_chat/ui/markdown_view.dart';
import 'package:val_latex_flutter/val_latex_flutter.dart' show Math;

void main() {
  Widget app(String text, {bool streaming = false}) => MaterialApp(
    home: Scaffold(
      body: MarkdownView(text: text, streaming: streaming),
    ),
  );

  Future<void> pumpMarkdown(
    WidgetTester tester,
    String data, {
    bool streaming = false,
  }) async {
    await tester.pumpWidget(app(data, streaming: streaming));
    await tester.pumpAndSettle();
  }

  testWidgets('renders markdown syntax as text', (tester) async {
    await pumpMarkdown(tester, '# 标题\n\n**粗体**');

    expect(find.textContaining('标题', findRichText: true), findsWidgets);
    expect(find.textContaining('粗体', findRichText: true), findsWidgets);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('# ', findRichText: true), findsNothing);
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
    expect(find.textContaining('ab', findRichText: true), findsWidgets);

    await tester.pumpWidget(app('abc', streaming: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.textContaining('abc', findRichText: true), findsNothing);

    await tester.pumpWidget(app('abcd', streaming: true));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('abcd', findRichText: true), findsWidgets);

    await tester.pumpWidget(app('abcde'));
    expect(find.textContaining('abcde', findRichText: true), findsWidgets);
  });

  testWidgets('falls back to the mermaid source when parsing fails', (
    tester,
  ) async {
    await pumpMarkdown(tester, '```mermaid\nnot a diagram\n```');

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('not a diagram', findRichText: true),
      findsWidgets,
    );
  });
}
