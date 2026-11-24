import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/features/chat/markdown_view.dart';

void main() {
  testWidgets('task checkboxes share one size and keep a gap before the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            text: '- [x] 已完成任务\n- [ ] 未完成任务',
            textStyle: TextStyle(fontSize: 16, height: 28 / 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boxes = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TaskBox',
    );
    expect(boxes, findsNWidgets(2));
    final checked = boxes.at(0);
    final unchecked = boxes.at(1);
    final checkedLabel = find
        .textContaining('已完成任务', findRichText: true)
        .first;
    final uncheckedLabel = find
        .textContaining('未完成任务', findRichText: true)
        .first;

    final checkedSize = tester.getSize(checked);
    final uncheckedSize = tester.getSize(unchecked);
    final checkedGap =
        tester.getTopLeft(checkedLabel).dx - tester.getTopRight(checked).dx;
    final uncheckedGap =
        tester.getTopLeft(uncheckedLabel).dx - tester.getTopRight(unchecked).dx;

    expect(uncheckedSize, checkedSize);
    expect(checkedSize.height, 13);
    expect(checkedGap, greaterThanOrEqualTo(4));
    expect(uncheckedGap, greaterThanOrEqualTo(4));

    // ZH
    // 方框底边贴在首行文字基线上：位置不依赖具体字体的上下行度量，
    // 否则 Android 与 iOS 的字体度量差会让方框整体偏下。
    //
    // EN
    // The box bottom sits on the first line's baseline so its position does not
    // depend on font ascent/descent, which differs between Android and iOS.
    final label = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('未完成任务'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(label.first);
    final labelTop = tester.getTopLeft(label.first).dy;
    // Baselines can only be measured during layout, so use the dry-layout API.
    final baseline = paragraph.getDryBaseline(
      paragraph.constraints,
      TextBaseline.alphabetic,
    )!;
    final boxBottom = tester.getBottomLeft(unchecked).dy;
    debugPrint(
      'labelTop=$labelTop baseline=$baseline boxBottom=$boxBottom '
      'labelBottom=${tester.getBottomLeft(label.first).dy}',
    );
    expect(boxBottom, closeTo(labelTop + baseline, 0.5));
  });

  testWidgets('scales the task checkbox with the text scaler', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: MarkdownView(
              text: '- [ ] 任务',
              textStyle: TextStyle(fontSize: 16, height: 28 / 16),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final box = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TaskBox',
    );
    expect(tester.getSize(box).height, 13 * 1.5);
  });
}
