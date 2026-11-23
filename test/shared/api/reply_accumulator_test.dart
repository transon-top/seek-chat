import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/shared/api/stream_events.dart';
import 'package:seek_chat/shared/api/reply_accumulator.dart';
import 'package:seek_chat/shared/models/types.dart';

TextCitation citation(String url) => TextCitation(
      url: url,
      title: null,
      citedText: 'quote',
      encryptedIndex: '',
    );

void main() {
  group('ReplyAccumulator', () {
    test('starts pending and enters streaming on the first event', () {
      final reply = ReplyAccumulator(clock: () => 1000);

      expect(reply.status, ReplyStatus.pending);

      reply.apply(MessageStart('m1', 'deepseek-flash', null));

      expect(reply.status, ReplyStatus.streaming);
      expect(reply.prefix, isTrue);
    });

    test('appends continuation blocks after the existing reply', () {
      final reply = ReplyAccumulator(
        blocks: const [TextBlock(text: 'first ')],
        clock: () => 1000,
      )
        ..apply(ContentBlockStart(0, TextBlock(text: 'second')))
        ..apply(ContentBlockDelta(0, TextDelta('!')));

      expect(
        reply.blocks.map((block) => (block as TextBlock).text),
        ['first ', 'second!'],
      );
    });

    test('appends deltas to the mapped block', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, TextBlock(text: 'Hello')))
        ..apply(ContentBlockDelta(0, TextDelta(' world')))
        ..apply(ContentBlockDelta(0, TextDelta('!')));

      final block = reply.blocks.single as TextBlock;
      expect(block.text, 'Hello world!');
    });

    test('ignores deltas for unknown indexes', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, TextBlock(text: 'a')))
        ..apply(ContentBlockDelta(7, TextDelta('ignored')));

      expect((reply.blocks.single as TextBlock).text, 'a');
    });

    test('skipped blocks do not occupy a local index', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, null))
        ..apply(ContentBlockStart(1, TextBlock(text: '')))
        ..apply(ContentBlockDelta(1, TextDelta('mapped')));

      expect(reply.blocks, hasLength(1));
      expect((reply.blocks.single as TextBlock).text, 'mapped');
    });

    test('appends signature and citations deltas', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, TextBlock(text: 'a')))
        ..apply(ContentBlockDelta(0, CitationsDelta(citation('https://one'))))
        ..apply(ContentBlockDelta(0, CitationsDelta(citation('https://two'))))
        ..apply(ContentBlockStart(1, ThinkingBlock(thinking: 'hmm')))
        ..apply(ContentBlockDelta(1, SignatureDelta('sig-1')))
        ..apply(ContentBlockDelta(1, SignatureDelta('sig-2')));

      final text = reply.blocks[0] as TextBlock;
      final thinking = reply.blocks[1] as ThinkingBlock;
      expect(text.citations.map((c) => c.url), ['https://one', 'https://two']);
      expect(thinking.signature, 'sig-1sig-2');
    });

    test('sets prefix false when a client tool_use block arrives', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, null, isClientToolUse: true));

      expect(reply.prefix, isFalse);
      expect(reply.blocks, isEmpty);
    });

    test('keeps prefix true for unknown blocks', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, null));

      expect(reply.prefix, isTrue);
    });

    test('closes a thinking block on content_block_stop', () {
      final now = [1000];
      final reply = ReplyAccumulator(clock: () => now.single)
        ..apply(ContentBlockStart(0, ThinkingBlock(thinking: '', startedAt: 1000)));

      now[0] = 2500;
      reply.apply(ContentBlockStop(0));

      final thinking = reply.blocks.single as ThinkingBlock;
      expect(thinking.startedAt, 1000);
      expect(thinking.endedAt, 2500);
    });

    test('keeps the latest non-null usage and stop details', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(MessageStart('m1', 'deepseek-flash', Usage(
          inputTokens: 1,
          cacheCreationInputTokens: 0,
          cacheReadInputTokens: 0,
          outputTokens: 0,
        )))
        ..apply(MessageDelta(
          stopReason: StopReason.endTurn,
          usage: Usage(
            inputTokens: 1,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 5,
          ),
        ))
        ..apply(MessageDelta(stopReason: StopReason.endTurn));

      expect(reply.usage!.outputTokens, 5);
      expect(reply.stopReason, StopReason.endTurn);
    });

    test('settle closes unfinished thinking blocks and keeps content when stopped', () {
      final now = [1000];
      final reply = ReplyAccumulator(clock: () => now.single)
        ..apply(ContentBlockStart(0, ThinkingBlock(thinking: 'hmm', startedAt: 1000)))
        ..apply(ContentBlockStart(1, TextBlock(text: 'answer')));
      now[0] = 4000;

      reply.settle(ReplyStatus.stopped);

      expect(reply.status, ReplyStatus.stopped);
      expect((reply.blocks[0] as ThinkingBlock).endedAt, 4000);
      expect((reply.blocks[1] as TextBlock).text, 'answer');
    });

    test('refusal drops received thinking and text but keeps tool blocks', () {
      final reply = ReplyAccumulator(clock: () => 1000)
        ..apply(ContentBlockStart(0, ThinkingBlock(thinking: 'hmm')))
        ..apply(ContentBlockStart(1, TextBlock(text: 'answer')))
        ..apply(ContentBlockStart(
          2,
          ServerToolUseBlock(
            id: 'tool-1',
            name: 'deepseek_web_search',
            input: SearchInput(queries: const ['q']),
            kind: ServerToolKind.search,
          ),
        ))
        ..apply(MessageDelta(stopReason: StopReason.refusal));

      reply.settle(ReplyStatus.done);

      expect(reply.blocks, hasLength(1));
      expect(reply.blocks.single, isA<ServerToolUseBlock>());
    });
  });
}
