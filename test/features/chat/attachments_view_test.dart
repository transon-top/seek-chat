import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets('draft strip shows uploading, retryable failure and remove',
      (tester) async {
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

    await tester.tap(find.byIcon(Icons.refresh));
    expect(retried, ['doc']);

    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, ['img']);
  });
}
