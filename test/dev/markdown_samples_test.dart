import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/dev/markdown_samples.dart';
import 'package:seek_chat/features/chat/markdown_view.dart';
import 'package:seek_chat/shared/models/types.dart';

void main() {
  Future<void> pumpText(
    WidgetTester tester,
    String text, {
    bool dense = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownView(text: text, dense: dense, disableLinks: dense),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('samples cover every category with unique labels', () {
    final samples = [...markdownSamples, longTextSample];
    expect(samples, hasLength(14));
    final labels = samples.map((sample) => sample.label).toSet();
    expect(labels, hasLength(samples.length));
  });

  testWidgets('every sample renders without throwing', (tester) async {
    for (final sample in [...markdownSamples, longTextSample]) {
      for (final block in sample.blocks) {
        final text = switch (block) {
          TextBlock block => block.text,
          ThinkingBlock block => block.thinking,
          _ => null,
        };
        if (text == null) continue;
        await pumpText(tester, text, dense: block is ThinkingBlock);
        expect(tester.takeException(), isNull, reason: sample.label);
      }
    }
  });

  testWidgets('inline styles render without raw markers', (tester) async {
    final text = markdownSamples.first.blocks.first as TextBlock;
    await pumpText(tester, text.text);

    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('标题', findRichText: true), findsWidgets);
  });
}
