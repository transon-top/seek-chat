import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/attachment_panel.dart';
import 'package:open_chat/features/chat/composer.dart';
import 'package:open_chat/features/chat/photo_strip.dart';
import 'package:open_chat/features/chat/speech/recording_overlay.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/features/chat/upload_tasks.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/photo_fakes.dart';

/// 票 07 第 4 项：双语 × 320 宽 × 动态字体 2.0 的输入区文本不溢出。
void main() {
  late TextEditingController input;
  late FocusNode focus;

  setUp(() {
    input = TextEditingController();
    focus = FocusNode();
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
  });

  File tempImage() {
    final temp = Directory.systemTemp.createTempSync('composer-scale-test');
    addTearDown(() => temp.deleteSync(recursive: true));
    return File('${temp.path}/photo.png')..writeAsBytesSync([1]);
  }

  DraftAttachment imageAttachment(String path) => DraftAttachment(
    id: 'img',
    path: path,
    name: 'photo.png',
    size: 1,
    isImage: true,
    mimeType: 'image/png',
  );

  DraftAttachment documentAttachment(String id, String name) => DraftAttachment(
    id: id,
    path: '/missing/$name',
    name: name,
    size: 2048,
    isImage: false,
    mimeType: '',
  );

  AttachmentPanel panel(PhotoLibrary library) => AttachmentPanel(
    attachmentCount: 0,
    photoStrip: PhotoStrip(
      library: library,
      selectedAssetIds: const {},
      full: false,
      onToggle: (_) {},
      onLimitReached: () {},
    ),
    onTakePhoto: () {},
    onPickPhotos: () {},
    onPickFiles: () {},
    onLimitReached: () {},
  );

  Widget app({
    required Locale locale,
    required Brightness brightness,
    required Widget home,
  }) => ShadApp(
    theme: buildShadTheme(
      brightness: brightness,
      chinese: locale.languageCode == 'zh',
    ),
    themeMode: ThemeMode.light,
    locale: locale,
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Widget host({
    required Locale locale,
    required Brightness brightness,
    required Widget attachmentPanel,
    bool panelOpen = false,
    bool busy = false,
    SpeechPhase phase = SpeechPhase.idle,
    List<DraftAttachment> attachments = const [],
    Map<String, UploadTask> tasks = const {},
  }) => app(
    locale: locale,
    brightness: brightness,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Composer(
          input: input,
          inputFocus: focus,
          busy: busy,
          phase: phase,
          thinking: false,
          search: false,
          attachments: attachments,
          tasks: tasks,
          panelOpen: panelOpen,
          attachmentPanel: attachmentPanel,
          onThinkingChanged: (_) {},
          onSearchChanged: (_) {},
          onTogglePanel: () {},
          onRetryAttachment: (_) {},
          onRemoveAttachment: (_) {},
          onSend: () {},
          onStop: () {},
          onVoiceStart: () {},
          onVoiceEnd: () {},
          onVoicePointerCancel: () {},
          onVoiceCancelArmed: (_) {},
          onVoiceCancel: () {},
        ),
      ),
    ),
  );

  Widget overlayHost({
    required Locale locale,
    required Brightness brightness,
    required SpeechPhase phase,
  }) => ProviderScope(
    child: app(
      locale: locale,
      brightness: brightness,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 320,
            height: 432,
            child: RecordingOverlay(phase: phase),
          ),
        ),
      ),
    ),
  );

  void expectNoOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  for (final locale in const [Locale('zh'), Locale('en')]) {
    for (final brightness in const [Brightness.light, Brightness.dark]) {
      final label = '${locale.languageCode}-${brightness.name}';
      testWidgets('input area never overflows at 320pt and 2x ($label)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final library = FakePhotoLibrary();

        // 空态：占位、开关胶囊、按钮矩阵。
        await tester.pumpWidget(
          host(
            locale: locale,
            brightness: brightness,
            attachmentPanel: panel(library),
          ),
        );
        await tester.pumpAndSettle();
        expectNoOverflow(tester);

        // 有文本：麦克风隐藏，发送可用。
        input.text =
            'Message with a long line that must wrap instead of overflowing.';
        await tester.pumpAndSettle();
        expectNoOverflow(tester);

        // 生成中：`+` 禁用、发送变停止、无麦克风。
        await tester.pumpWidget(
          host(
            locale: locale,
            brightness: brightness,
            attachmentPanel: panel(library),
            busy: true,
          ),
        );
        await tester.pumpAndSettle();
        expectNoOverflow(tester);

        // 草稿：图片 + 长文件名 + 失败原因。
        await tester.pumpWidget(
          host(
            locale: locale,
            brightness: brightness,
            attachmentPanel: panel(library),
            attachments: [
              imageAttachment(tempImage().path),
              documentAttachment('failed', 'report.xlsx'),
              documentAttachment(
                'doc',
                'a-very-long-file-name-for-narrow-screens.pdf',
              ),
            ],
            tasks: const {
              'failed': UploadTask.failed(
                error: LocalMessage(key: LocalMessageKeys.uploadServerBusy),
                retryable: true,
              ),
              'doc': UploadTask.done('file_1'),
            },
          ),
        );
        await tester.pumpAndSettle();
        expectNoOverflow(tester);
        // 固定 64 高卡片的文字封顶生效，而不是被整体压到不可读。
        expect(
          MediaQuery.textScalerOf(tester.element(find.text('report.xlsx')))
              .scale(10),
          13,
        );

        // 面板：横条四态 + 三宫格，均在 320 宽内。
        final states = <String, PhotoLibrary>{
          'ready': FakePhotoLibrary(assets: [FakePhotoAsset(id: 'a0')]),
          'denied': FakePhotoLibrary(status: PhotoAccessStatus.denied),
          'limited': FakePhotoLibrary(
            status: PhotoAccessStatus.limited,
            assets: [FakePhotoAsset(id: 'a0')],
          ),
          'empty': FakePhotoLibrary(),
          'failed': FakePhotoLibrary(fail: true),
        };
        for (final entry in states.entries) {
          await tester.pumpWidget(
            host(
              locale: locale,
              brightness: brightness,
              attachmentPanel: panel(entry.value),
              panelOpen: true,
            ),
          );
          await tester.pumpAndSettle();
          expectNoOverflow(tester);
        }

        // 浮层三态：录音、取消、识别中。
        for (final phase in const [
          SpeechPhase.recording,
          SpeechPhase.cancelling,
          SpeechPhase.transcribing,
        ]) {
          await tester.pumpWidget(
            overlayHost(locale: locale, brightness: brightness, phase: phase),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expectNoOverflow(tester);
        }
      });
    }
  }
}
