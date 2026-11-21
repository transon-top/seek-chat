// 输入区端到端集成测试（composer-implementation 票 07 的自动化部分）。
//
// 在真实引擎与平台通道下覆盖：按住 / 上滑 / 松手、转写后插入并自动发送、
// 系统中断、进后台取消、面板展开与返回键、浮层与输入法切换。
// 系统权限弹窗、相机 / 相册 / 文件选择器、真机对图与预测性返回动画无法在
// 集成测试里可靠驱动，留给人工验收。
//
// 运行：
//   flutter test integration_test/composer_test.dart -d <device>

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_chat/app/app.dart';
import 'package:open_chat/features/chat/photo_import.dart';
import 'package:open_chat/features/chat/photo_strip.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/shared/speech/permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_api_key_store.dart';
import '../test/support/pump.dart';
import '../test/support/speech_fakes.dart';
import '../test/support/sse_fixtures.dart';

const _origin = 'https://mock.open-chat.test';

final _replyFixture =
    messageStart +
    textStart(0) +
    textDelta(0, 'Hi there') +
    textStop(0) +
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
    }) +
    messageStop;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChatRepository repository;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    SharedPreferences.setMockInitialValues({'user.locale': 'zh'});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  Future<({FakeRecorder recorder, FakeSpeechApi speechApi})> pumpApp(
    WidgetTester tester,
  ) async {
    final recorder = FakeRecorder();
    final speechApi = FakeSpeechApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chatRepositoryProvider.overrideWithValue(repository),
          attachmentStoreProvider.overrideWithValue(AttachmentStore()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiKeyStoreProvider.overrideWithValue(FakeApiKeyStore('sk-good')),
          apiClientProvider.overrideWithValue(
            DeepSeekApiClient(
              origin: Uri.parse(_origin),
              httpClient: MockClient.streaming(
                (request, _) async =>
                    sseResponse(Stream.value(utf8.encode(_replyFixture))),
              ),
            ),
          ),
          speechRecorderProvider.overrideWithValue(recorder),
          speechApiProvider.overrideWithValue(speechApi),
          speechPlayerProvider.overrideWithValue(FakePlayer()),
          microphonePermissionsProvider.overrideWithValue(
            FakeMicrophonePermissions(),
          ),
          photoLibraryProvider.overrideWithValue(_DeniedPhotoLibrary()),
        ],
        child: const OpenChatApp(),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('composer-input')).evaluate().isNotEmpty,
    );
    await pumpFor(tester, const Duration(milliseconds: 200));
    return (recorder: recorder, speechApi: speechApi);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// 在语音按钮中心按下并等浮层出现；调用方负责移动与松手。
  Future<TestGesture> startRecording(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voice-button'))),
    );
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.byKey(const Key('recording-overlay')), findsOneWidget);
    return gesture;
  }

  testWidgets('按住说话：上滑取消、回拉恢复、松手丢弃且不转写', (tester) async {
    final (:recorder, :speechApi) = await pumpApp(tester);

    final gesture = await startRecording(tester);
    expect(find.text('松手发送，上滑取消'), findsOneWidget);
    expect(recorder.starts, 1);

    await gesture.moveBy(const Offset(0, -100));
    await pumpFor(tester, const Duration(milliseconds: 100));
    expect(find.text('松开取消'), findsOneWidget);
    expect(find.text('松手发送，上滑取消'), findsNothing);

    await gesture.moveBy(const Offset(0, 100));
    await pumpFor(tester, const Duration(milliseconds: 100));
    expect(find.text('松手发送，上滑取消'), findsOneWidget);

    await gesture.moveBy(const Offset(0, -100));
    await pumpFor(tester, const Duration(milliseconds: 100));
    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.byKey(const Key('recording-overlay')), findsNothing);
    expect(recorder.session?.cancelled, isTrue);
    expect(speechApi.asrCount, 0);
    expect(await repository.listSessions(), isEmpty);

    await unmount(tester);
  });

  testWidgets('按住松手：转写后插入并自动发送', (tester) async {
    final (:recorder, :speechApi) = await pumpApp(tester);

    final gesture = await startRecording(tester);
    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('识别中'), findsOneWidget);
    expect(speechApi.asrCount, 1);

    speechApi.completeAsr('你好');
    await pumpUntil(
      tester,
      () => find.text('Hi there').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('recording-overlay')), findsNothing);
    expect(find.text('你好'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    final session = (await repository.listSessions()).single;
    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(
      stored.blocks.whereType<TextBlock>().map((block) => block.text).join(),
      'Hi there',
    );
    expect(recorder.session?.stopped, isTrue);

    await unmount(tester);
  });

  testWidgets('录音中进后台：取消录音且不转写', (tester) async {
    final (:recorder, :speechApi) = await pumpApp(tester);

    final gesture = await startRecording(tester);

    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await pumpFor(tester, const Duration(milliseconds: 100));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.byKey(const Key('recording-overlay')), findsNothing);
    expect(recorder.session?.cancelled, isTrue);
    expect(speechApi.asrCount, 0);

    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 100));
    await unmount(tester);
  });

  testWidgets('录音中系统中断：丢弃录音并提示', (tester) async {
    final (:recorder, :speechApi) = await pumpApp(tester);

    final gesture = await startRecording(tester);

    recorder.session!.interrupt();
    await pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.byKey(const Key('recording-overlay')), findsNothing);
    expect(find.text('录音已中断'), findsOneWidget);
    expect(recorder.session?.cancelled, isTrue);
    expect(speechApi.asrCount, 0);

    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 100));
    await unmount(tester);
  });

  testWidgets('面板：+ 展开、返回键先收面板、点输入框也收起', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('attach-button')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('panel-take-photo')), findsOneWidget);
    expect(find.byKey(const Key('panel-photos')), findsOneWidget);
    expect(find.byKey(const Key('panel-files')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-input')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('panel-take-photo')), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('attach-button')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('panel-take-photo')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('panel-take-photo')), findsNothing);
    expect(find.byKey(const Key('composer-input')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('输入法聚焦时按住麦克风：失焦并显示浮层', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('composer-input')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    final gesture = await startRecording(tester);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    await gesture.moveBy(const Offset(0, -100));
    await pumpFor(tester, const Duration(milliseconds: 100));
    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('recording-overlay')), findsNothing);

    await unmount(tester);
  });

  testWidgets('面板展开时按住麦克风：收起面板并显示浮层', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('attach-button')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('panel-take-photo')), findsOneWidget);

    final gesture = await startRecording(tester);
    expect(find.byKey(const Key('panel-take-photo')), findsNothing);

    await gesture.moveBy(const Offset(0, -100));
    await pumpFor(tester, const Duration(milliseconds: 100));
    await gesture.up();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('recording-overlay')), findsNothing);

    await unmount(tester);
  });
}

/// 面板测试不触达系统照片库，也不触发权限弹窗。
class _DeniedPhotoLibrary implements PhotoLibrary {
  @override
  Future<PhotoAccessStatus> access({required bool request}) async =>
      PhotoAccessStatus.denied;

  @override
  Future<List<PhotoAsset>> recentImages({int limit = 30}) async => const [];

  @override
  Future<void> presentLimited() async {}

  @override
  Future<void> openSettings() async {}
}
