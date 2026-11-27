import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/dev/mock_stream_client.dart';
import 'package:seek_chat/shared/api/client.dart';
import 'package:seek_chat/shared/api/reply_accumulator.dart';
import 'package:seek_chat/shared/api/request.dart';
import 'package:seek_chat/shared/models/types.dart';

void main() {
  test('mock 流产出思考块、正文块与标题', () async {
    final client = DeepSeekApiClient(
      httpClient: MockStreamClient(
        ttfb: Duration.zero,
        chunkDelay: Duration.zero,
      ),
      origin: Uri.parse('https://mock.test'),
    );
    final request = buildMessageRequest(
      history: const [],
      question: UserMessage(
        id: 'u1',
        createdAt: DateTime(2026, 1, 1),
        text: '你好',
      ),
      thinking: true,
      search: false,
      titleEnabled: true,
    );

    final accumulator = ReplyAccumulator();
    await for (final event in client.streamMessage(
      request: request,
      apiKey: 'mock',
    )) {
      accumulator.apply(event);
    }
    accumulator.settle(ReplyStatus.done);

    expect(accumulator.stopReason, StopReason.endTurn);
    expect(accumulator.title, '慢速流式 Mock');
    expect(
      accumulator.blocks.whereType<ThinkingBlock>().single.thinking,
      contains('慢速流式'),
    );
    expect(
      accumulator.blocks.whereType<TextBlock>().single.text,
      contains('slow stream'),
    );
  });
}
