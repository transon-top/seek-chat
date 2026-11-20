import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/features/chat/attachments_view.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/features/chat/upload_tasks.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: const [Locale('zh')],
    home: Scaffold(body: child),
  );

  testWidgets('draft strip shows uploading, retryable failure and remove', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('draft-strip-test');
    final image = File('${temp.path}/photo.png')..writeAsBytesSync([1]);
    addTearDown(() => temp.deleteSync(recursive: true));

    final retried = <String>[];
    final removed = <String>[];
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            DraftAttachment(
              id: 'img',
              path: image.path,
              name: 'photo.png',
              size: 1,
              isImage: true,
              mimeType: 'image/png',
            ),
            DraftAttachment(
              id: 'doc',
              path: '${temp.path}/notes.txt',
              name: 'notes.txt',
              size: 2048,
              isImage: false,
              mimeType: 'text/plain',
            ),
          ],
          tasks: const {
            'img': UploadTask.uploading(),
            'doc': UploadTask.failed(
              error: LocalMessage(key: LocalMessageKeys.uploadServerBusy),
              retryable: true,
            ),
          },
          onRetry: retried.add,
          onRemove: removed.add,
        ),
      ),
    );

    expect(find.text('上传中...'), findsNothing);
    expect(find.text('服务器繁忙'), findsOneWidget);

    // 缩略图按显示尺寸解码：64 逻辑像素 × 测试设备 3x，等比内切不拉伸。
    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>());
    final resize = provider as ResizeImage;
    expect((resize.width, resize.height), (192, 192));
    expect(resize.policy, ResizeImagePolicy.fit);

    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    expect(retried, ['doc']);

    await tester.tap(find.byIcon(LucideIcons.x).first);
    expect(removed, ['img']);
  });
}
