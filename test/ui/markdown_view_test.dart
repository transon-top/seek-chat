import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/code_field.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:open_chat/ui/markdown_view.dart';
import 'package:val_latex_flutter/val_latex_flutter.dart' show Math;

void main() {
  Future<void> pumpMarkdown(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkdownView(text: data)),
      ),
    );
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
    Widget build(String data) => MaterialApp(
      home: Scaffold(body: MarkdownView(text: data)),
    );

    await tester.pumpWidget(build('**hel'));
    await tester.pumpWidget(build('**hello** world'));
    await tester.pumpAndSettle();

    expect(find.textContaining('hello', findRichText: true), findsWidgets);
    expect(find.textContaining('world', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
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
