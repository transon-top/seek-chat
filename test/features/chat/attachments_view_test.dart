import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/features/chat/attachments_view.dart';
import 'package:seek_chat/shared/models/types.dart';
import 'package:seek_chat/features/chat/upload_tasks.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: const [Locale('zh')],
    home: Scaffold(body: child),
  );

  File tempImage() {
    final temp = Directory.systemTemp.createTempSync('draft-row-test');
    addTearDown(() => temp.deleteSync(recursive: true));
    return File('${temp.path}/photo.png')..writeAsBytesSync([1]);
  }

  DraftAttachment imageAttachment(String path, {String id = 'img'}) =>
      DraftAttachment(
        id: id,
        path: path,
        name: 'photo.png',
        size: 1,
        isImage: true,
        mimeType: 'image/png',
      );

  DraftAttachment documentAttachment(
    String id,
    String name, {
    int size = 2048,
  }) => DraftAttachment(
    id: id,
    path: '/missing/$name',
    name: name,
    size: size,
    isImage: false,
    mimeType: '',
  );

  testWidgets('draft strip shows uploading, retryable failure and remove', (
    tester,
  ) async {
    final image = tempImage();

    final retried = <String>[];
    final removed = <String>[];
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            imageAttachment(image.path),
            documentAttachment('doc', 'notes.txt'),
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

    // ZH
    // 缩略图按显示尺寸解码：64 逻辑像素 × 测试设备 3x，等比内切不拉伸。
    //
    // EN
    // Thumbnails decode at display size: 64 logical px × 3x device, contained without stretching.
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

  testWidgets('draft strip stays one row at 76 with sized cards', (
    tester,
  ) async {
    final image = tempImage();

    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            imageAttachment(image.path),
            documentAttachment('doc', 'report.pdf'),
          ],
          tasks: const {
            'img': UploadTask.done('file_1'),
            'doc': UploadTask.done('file_2'),
          },
          onRetry: (_) {},
          onRemove: (_) {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(DraftAttachmentStrip)).height, 76);
    expect(
      tester.widget<ListView>(find.byType(ListView)).scrollDirection,
      Axis.horizontal,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('draft-card-img'))),
      const Size(64, 64),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('draft-card-doc'))),
      const Size(210, 64),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('draft-card-img'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('draft-card-doc'))).dy,
    );
  });

  testWidgets('50 drafts keep the strip height fixed', (tester) async {
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            for (var i = 0; i < 50; i++)
              DraftAttachment(
                id: 'doc-$i',
                path: '/missing/file$i.txt',
                name: 'file$i.txt',
                size: 1,
                isImage: false,
                mimeType: 'text/plain',
              ),
          ],
          tasks: {
            for (var i = 0; i < 50; i++) 'doc-$i': const UploadTask.done('f'),
          },
          onRetry: (_) {},
          onRemove: (_) {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(DraftAttachmentStrip)).height, 76);
    expect(find.byKey(const ValueKey('draft-card-doc-49')), findsNothing);
  });

  testWidgets('remove badge sits inside both card types at 20', (tester) async {
    final image = tempImage();

    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            imageAttachment(image.path),
            documentAttachment('doc', 'report.pdf'),
          ],
          tasks: const {
            'img': UploadTask.done('file_1'),
            'doc': UploadTask.done('file_2'),
          },
          onRetry: (_) {},
          onRemove: (_) {},
        ),
      ),
    );

    for (final id in ['img', 'doc']) {
      final card = tester.getRect(find.byKey(ValueKey('draft-card-$id')));
      final badge = tester.getRect(find.byKey(ValueKey('draft-remove-$id')));
      expect(badge.size, const Size(20, 20));
      expect(badge.left, greaterThanOrEqualTo(card.left));
      expect(badge.top, greaterThanOrEqualTo(card.top));
      expect(badge.right, lessThanOrEqualTo(card.right));
      expect(badge.bottom, lessThanOrEqualTo(card.bottom));
    }
  });

  testWidgets('file card shows a colored 36 extension badge', (tester) async {
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [
            documentAttachment('pdf', 'report.pdf'),
            documentAttachment('xls', 'budget.xlsx'),
            documentAttachment('bare', 'README'),
          ],
          tasks: const {
            'pdf': UploadTask.done('file_1'),
            'xls': UploadTask.done('file_2'),
            'bare': UploadTask.done('file_3'),
          },
          onRetry: (_) {},
          onRemove: (_) {},
        ),
      ),
    );

    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('XLSX'), findsOneWidget);
    final pdfBadge = tester.getSize(
      find.byKey(const ValueKey('draft-extension-pdf')),
    );
    expect(pdfBadge, const Size(36, 36));
    Color badgeColor(String id) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byKey(ValueKey('draft-extension-$id')),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(badgeColor('pdf'), const Color(0xFFE5484D));
    expect(badgeColor('xls'), const Color(0xFF2E7D32));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('draft-extension-bare')),
        matching: find.byIcon(LucideIcons.fileText),
      ),
      findsOneWidget,
    );
    expect(find.text('FILE'), findsNothing);
  });

  testWidgets('uploading and failed overlays follow the upload state', (
    tester,
  ) async {
    final image = imageAttachment('/missing/photo.jpg');
    final retried = <String>[];
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [image],
          tasks: const {'img': UploadTask.uploading()},
          onRetry: retried.add,
          onRemove: (_) {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('上传中...'), findsNothing);

    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [image],
          tasks: const {
            'img': UploadTask.failed(
              error: LocalMessage(key: LocalMessageKeys.uploadServerBusy),
              retryable: true,
            ),
          },
          onRetry: retried.add,
          onRemove: (_) {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
    expect(find.text('服务器繁忙'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    expect(retried, ['img']);

    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [image],
          tasks: const {
            'img': UploadTask.failed(
              error: LocalMessage(key: LocalMessageKeys.uploadServerBusy),
              retryable: false,
            ),
          },
          onRetry: retried.add,
          onRemove: (_) {},
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.refreshCw), findsNothing);
    expect(find.text('服务器繁忙'), findsOneWidget);
  });

  testWidgets('uploading file card shows the status line', (tester) async {
    await tester.pumpWidget(
      wrap(
        DraftAttachmentStrip(
          attachments: [documentAttachment('doc', 'report.pdf')],
          tasks: const {'doc': UploadTask.uploading()},
          onRetry: (_) {},
          onRemove: (_) {},
        ),
      ),
    );

    expect(find.text('上传中...'), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsNothing);
  });
}
