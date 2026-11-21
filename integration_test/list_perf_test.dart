// 列表性能基线测量（wayfinder 票「列表基线测量」）。
//
// 在真实渲染管线（profile 模式）下打开 1000 条消息的长会话与 1000 条会话的
// 抽屉，采集帧耗时、打开耗时与内存。结果以 `BASELINE ` 前缀的 JSON 行输出，
// 由 `flutter drive` 的日志捕获。
//
// 运行：
//   flutter drive --profile -d emulator-5554 \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/list_perf_test.dart
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_chat/app/app.dart';
import 'package:open_chat/dev/mock_seed.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/shared/security/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/pump.dart';

final List<FrameTiming> _frames = <FrameTiming>[];
bool _mockStreamDone = false;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('列表性能基线：1000 条消息与 1000 个会话', (tester) async {
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);

    final db = AppDatabase.open();
    final prefs = await SharedPreferences.getInstance();
    final seedWatch = Stopwatch()..start();
    await seedStressSamples(db, prefs);
    final seedMs = seedWatch.elapsedMilliseconds;

    final repository = ChatRepository(db);
    final sessions = await repository.listSessions();
    final longSession = sessions.firstWhere(
      (session) => session.title == longSessionSampleTitle,
    );
    final conversation = await repository.loadConversation(longSession.id);
    final lastMessageId = conversation.messages.last.id;
    // 对照：只有两条消息的会话，用于区分「长会话成本」与「模拟器基线成本」。
    final smallSession = sessions.firstWhere(
      (session) => session.title == '$stressSessionTitlePrefix 0001',
    );
    final smallLastId = (await repository.loadConversation(smallSession.id))
        .messages
        .last
        .id;

    final apiClient = DeepSeekApiClient(
      httpClient: MockClient.streaming(_respondWithStream),
      origin: Uri.parse('https://mock.open-chat.test'),
    );

    final startWatch = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chatRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiKeyStoreProvider.overrideWithValue(_TestApiKeyStore()),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const OpenChatApp(),
      ),
    );
    // 冷启动直接打开最近会话（长会话）：等首屏消息出现。
    await pumpUntil(
      tester,
      () => find.byKey(const Key('chat-new')).evaluate().isNotEmpty,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    _report('cold_start_long_session', {
      'seed_ms': seedMs,
      'sessions': sessions.length,
      'messages': conversation.messages.length,
      'ms': startWatch.elapsedMilliseconds,
    });

    // 离开长会话，保证接下来的打开是冷加载。
    await tester.tap(find.byKey(const Key('chat-new')));
    await pumpFor(tester, const Duration(milliseconds: 400));

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    // 对照：空对话静止 1 秒的帧成本即模拟器基线。
    var mark = _frames.length;
    await pumpFor(tester, const Duration(seconds: 1));
    _report('control_idle_new_chat', _frameStats(_frames.sublist(mark)));

    // 抽屉打开：1000 条会话首屏 + 分组。
    mark = _frames.length;
    final drawerWatch = Stopwatch()..start();
    await tester.tap(find.byKey(const Key('chat-open-drawer')));
    final drawerMs = await pumpUntil(
      tester,
      () => find.text(longSessionSampleTitle).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 8),
    );
    await pumpFor(tester, const Duration(milliseconds: 400));
    _report('drawer_open_1000_sessions', {
      ..._frameStats(_frames.sublist(mark)),
      'first_row_ms': drawerMs,
      'total_ms': drawerWatch.elapsedMilliseconds,
    });

    // 对照：打开两条消息的小会话。
    mark = _frames.length;
    await tester.tap(find.text('$stressSessionTitlePrefix 0001').first);
    final smallWatch = Stopwatch()..start();
    await pumpUntil(
      tester,
      () => find.byKey(ValueKey(smallLastId)).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    final smallOpenMs = smallWatch.elapsedMilliseconds;
    await pumpFor(tester, const Duration(milliseconds: 500));
    _report('control_open_small_session', {
      ..._frameStats(_frames.sublist(mark)),
      'first_screen_ms': smallOpenMs,
    });
    mark = _frames.length;
    for (var i = 0; i < 3; i++) {
      await tester.flingFrom(
        Offset(size.width / 2, size.height * 0.72),
        Offset(0, -size.height * 0.45),
        2500,
      );
      await pumpFor(tester, const Duration(milliseconds: 350));
    }
    _report('control_scroll_small_session', _frameStats(_frames.sublist(mark)));

    // 从抽屉打开长会话：首屏时间。
    await tester.tap(find.byKey(const Key('chat-open-drawer')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    mark = _frames.length;
    await tester.tap(find.text(longSessionSampleTitle).first);
    final openWatch = Stopwatch()..start();
    await pumpUntil(
      tester,
      () => find.byKey(ValueKey(lastMessageId)).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    final openMs = openWatch.elapsedMilliseconds;
    await pumpFor(tester, const Duration(milliseconds: 800));
    _report('open_long_session', {
      ..._frameStats(_frames.sublist(mark)),
      'first_screen_ms': openMs,
    });
    _report('memory_after_open', {});

    // 滚动 1000 条消息。
    mark = _frames.length;
    for (var i = 0; i < 10; i++) {
      await tester.flingFrom(
        Offset(size.width / 2, size.height * 0.72),
        Offset(0, -size.height * 0.45),
        2500,
      );
      await pumpFor(tester, const Duration(milliseconds: 350));
    }
    _report('chat_scroll_1000', _frameStats(_frames.sublist(mark)));

    // 流式输出期间：先静止观察重建成本，再滚动观察是否阻塞。
    _mockStreamDone = false;
    await tester.enterText(
      find.byKey(const Key('composer-input')),
      '压测：流式输出期间滚动',
    );
    await pumpFor(tester, const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('send-button')));
    await pumpFor(tester, const Duration(milliseconds: 400));

    mark = _frames.length;
    final streamWatch = Stopwatch()..start();
    var idleFrames = -1;
    var flings = 0;
    while (!_mockStreamDone &&
        streamWatch.elapsed < const Duration(seconds: 15)) {
      if (idleFrames < 0 && streamWatch.elapsed > const Duration(seconds: 2)) {
        idleFrames = _frames.length;
      }
      if (flings < 8 && streamWatch.elapsed > const Duration(seconds: 2)) {
        await tester.flingFrom(
          Offset(size.width / 2, size.height * 0.72),
          Offset(0, -size.height * 0.3),
          2200,
        );
        flings++;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    final streamFrames = _frames.sublist(mark);
    _report('streaming_idle', {
      ..._frameStats(
        idleFrames < 0 ? streamFrames : _frames.sublist(mark, idleFrames),
      ),
      'stream_ms': streamWatch.elapsedMilliseconds,
    });
    _report('streaming_scroll', {
      ..._frameStats(streamFrames),
      'flings': flings,
    });
    await pumpFor(tester, const Duration(milliseconds: 600));
    _report('memory_after_streaming', {});

    // 会话列表滚动：1000 个会话。
    await tester.tap(find.byKey(const Key('chat-open-drawer')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    mark = _frames.length;
    for (var i = 0; i < 10; i++) {
      await tester.flingFrom(
        Offset(150, size.height * 0.65),
        Offset(0, -size.height * 0.35),
        2200,
      );
      await pumpFor(tester, const Duration(milliseconds: 350));
    }
    _report('drawer_scroll_1000_sessions', _frameStats(_frames.sublist(mark)));
    _report('memory_after_drawer_scroll', {});

    // 截图留档不作为证据：数字以 BASELINE 行为准。
    expect(sessions.length, greaterThanOrEqualTo(1000));
    expect(conversation.messages.length, greaterThanOrEqualTo(1000));
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Map<String, Object?> _frameStats(List<FrameTiming> slice) {
  if (slice.isEmpty) return {'frames': 0};
  double ms(Duration d) => d.inMicroseconds / 1000.0;
  final build = [for (final f in slice) ms(f.buildDuration)]..sort();
  final raster = [for (final f in slice) ms(f.rasterDuration)]..sort();
  final total = [for (final f in slice) ms(f.buildDuration + f.rasterDuration)]
    ..sort();
  final slow = total.where((value) => value > 16.7).length;
  return {
    'frames': slice.length,
    'build_p50_ms': _round(_percentile(build, 0.5)),
    'build_p90_ms': _round(_percentile(build, 0.9)),
    'build_max_ms': _round(build.last),
    'raster_p50_ms': _round(_percentile(raster, 0.5)),
    'raster_p90_ms': _round(_percentile(raster, 0.9)),
    'raster_max_ms': _round(raster.last),
    'total_p50_ms': _round(_percentile(total, 0.5)),
    'total_p90_ms': _round(_percentile(total, 0.9)),
    'total_max_ms': _round(total.last),
    'slow_over_16_7_pct': _round(100 * slow / total.length),
  };
}

double _percentile(List<double> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

double _round(double value) => double.parse(value.toStringAsFixed(2));

void _report(String scenario, Map<String, Object?> stats) {
  print(
    'BASELINE ${jsonEncode({'scenario': scenario, ...stats, 'rss_mb': _round(ProcessInfo.currentRss / 1024 / 1024)})}',
  );
}

Future<http.StreamedResponse> _respondWithStream(
  http.BaseRequest request,
  http.ByteStream bodyStream,
) async {
  return http.StreamedResponse(
    _sseStream(),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// 25ms 一个增量、共 200 个，模拟约 5 秒的流式输出。
Stream<List<int>> _sseStream() async* {
  String frame(String event, Map<String, Object?> data) =>
      'event: $event\ndata: ${jsonEncode(data)}\n\n';

  yield utf8.encode(
    frame('message_start', {
      'type': 'message_start',
      'message': {
        'id': 'msg_mock',
        'model': 'deepseek-flash',
        'usage': {'input_tokens': 10, 'output_tokens': 0},
      },
    }),
  );
  yield utf8.encode(
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }),
  );
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    yield utf8.encode(
      frame('content_block_delta', {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': '流式增量 $i，'},
      }),
    );
  }
  yield utf8.encode(
    frame('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
  );
  yield utf8.encode(
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 200},
    }),
  );
  yield utf8.encode(frame('message_stop', {'type': 'message_stop'}));
  _mockStreamDone = true;
}

class _TestApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read() async => 'test-key';

  @override
  Future<void> write(String apiKey) async {}

  @override
  Future<void> clear() async {}
}
