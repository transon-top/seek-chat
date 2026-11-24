import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/shared/api/errors.dart';
import 'package:seek_chat/shared/api/sse.dart';
import 'package:seek_chat/shared/api/stream_events.dart';
import 'package:seek_chat/shared/models/types.dart';

void main() {
  late StreamEventParser parser;

  setUp(() {
    parser = StreamEventParser(clock: () => 1000);
  });

  StreamEvent? parse(String event, Object data) => parser.parse(
        SseEvent(event: event, data: data is String ? data : jsonEncode(data)),
      );

  Matcher streamError(String message) => throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.stream)
            .having((e) => e.message, 'message', message),
      );

  group('StreamEventParser', () {
    test('parses message_start with usage', () {
      final event = parse('message_start', {
        'type': 'message_start',
        'message': {
          'id': 'm1',
          'model': 'deepseek-flash',
          'usage': {
            'input_tokens': 10,
            'cache_creation_input_tokens': 2,
            'cache_read_input_tokens': 3,
            'output_tokens': 0,
          },
        },
      });

      expect(event, isA<MessageStart>());
      final start = event as MessageStart;
      expect(start.messageId, 'm1');
      expect(start.model, 'deepseek-flash');
      expect(start.usage!.inputTokens, 10);
      expect(start.usage!.cacheCreationInputTokens, 2);
      expect(start.usage!.cacheReadInputTokens, 3);
      expect(start.usage!.outputTokens, 0);
    });

    test('parses text block start', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'text', 'text': 'Hello', 'citations': []},
      }) as ContentBlockStart;

      expect(event.index, 0);
      final block = event.block! as TextBlock;
      expect(block.text, 'Hello');
      expect(block.citations, isEmpty);
      expect(block.isTemplate, isFalse);
    });

    test('parses thinking block start with startedAt from the clock', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''},
      }) as ContentBlockStart;

      final block = event.block! as ThinkingBlock;
      expect(block.thinking, '');
      expect(block.signature, '');
      expect(block.startedAt, 1000);
      expect(block.endedAt, isNull);
    });

    test('parses server_tool_use with complete input', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 2,
        'content_block': {
          'type': 'server_tool_use',
          'id': 'srvtoolu_s_1_abc',
          'name': 'deepseek_web_search',
          'input': {
            'action': 'search',
            'queries': ['flutter drift'],
            'query': 'flutter drift',
          },
          'caller': {'type': 'direct'},
          'kind': 'search',
        },
      }) as ContentBlockStart;

      final block = event.block! as ServerToolUseBlock;
      expect(block.id, 'srvtoolu_s_1_abc');
      expect(block.name, 'deepseek_web_search');
      expect(block.kind, ServerToolKind.search);
      expect(block.input, isA<SearchInput>());
      expect((block.input as SearchInput).queries, ['flutter drift']);
      expect(block.caller, {'type': 'direct'});
    });

    test('parses web_search_tool_result with results and errors', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 3,
        'content_block': {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_s_1_abc',
          'kind': 'search',
          'content': [
            {
              'type': 'web_search_result',
              'title': 'Flutter',
              'url': 'https://flutter.dev',
              'snippet': 'Build apps',
              'image_url': 'https://flutter.dev/img.png',
              'site_icon': 'https://flutter.dev/icon.png',
              'site_name': 'Flutter',
              'encrypted_content': 'cipher',
              'page_age': '2026-01-01T00:00:00Z',
            },
            {'type': 'web_search_tool_result_error', 'error_code': 'unavailable'},
          ],
        },
      }) as ContentBlockStart;

      final block = event.block! as WebSearchToolResultBlock;
      expect(block.toolUseId, 'srvtoolu_s_1_abc');
      expect(block.kind, ServerToolKind.search);
      expect(block.content, hasLength(2));
      final result = block.content[0] as WebSearchResult;
      expect(result.title, 'Flutter');
      expect(result.url, 'https://flutter.dev');
      expect(result.imageUrl, 'https://flutter.dev/img.png');
      expect(result.siteIcon, 'https://flutter.dev/icon.png');
      expect(result.siteName, 'Flutter');
      expect(result.encryptedContent, 'cipher');
      expect(result.pageAge, '2026-01-01T00:00:00Z');
      final error = block.content[1] as WebSearchResultError;
      expect(error.errorCode, 'unavailable');
    });

    test('parses successful web_fetch_tool_result with signature', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 4,
        'content_block': {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_rl_1_abc',
          'kind': 'read_link',
          'signature': 'sig',
          'content': {
            'type': 'web_fetch_result',
            'url': 'https://example.com',
            'published_at': '2026-01-01',
            'content': {
              'type': 'document',
              'source': {'type': 'text', 'media_type': 'text/plain', 'data': ''},
              'title': 'Example',
            },
          },
        },
      }) as ContentBlockStart;

      final block = event.block! as WebFetchToolResultBlock;
      expect(block.toolUseId, 'srvtoolu_rl_1_abc');
      expect(block.kind, ServerToolKind.readLink);
      expect(block.signature, 'sig');
      final result = block.content as WebFetchResult;
      expect(result.url, 'https://example.com');
      expect(result.publishedAt, '2026-01-01');
      expect(result.content['title'], 'Example');
    });

    test('parses failed web_fetch_tool_result', () {
      final event = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 5,
        'content_block': {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_rl_1_abc',
          'kind': 'read_link',
          'content': {
            'type': 'web_fetch_tool_result_error',
            'error_code': 'url_not_accessible',
          },
        },
      }) as ContentBlockStart;

      final block = event.block! as WebFetchToolResultBlock;
      expect(block.signature, isNull);
      expect((block.content as WebFetchResultError).errorCode, 'url_not_accessible');
    });

    test('drops tool_use and unknown block types', () {
      final toolUse = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {
          'type': 'tool_use',
          'id': 'tu_1',
          'name': 'client',
          'input': {},
        },
      }) as ContentBlockStart;
      final unknown = parse('content_block_start', {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'future_block'},
      }) as ContentBlockStart;

      expect(toolUse.index, 0);
      expect(toolUse.block, isNull);
      expect(unknown.block, isNull);
    });

    test('parses deltas', () {
      final text = parse('content_block_delta', {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'hi'},
      }) as ContentBlockDelta;
      final thinking = parse('content_block_delta', {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
      }) as ContentBlockDelta;
      final signature = parse('content_block_delta', {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'signature_delta', 'signature': 'sig'},
      }) as ContentBlockDelta;
      final citation = parse('content_block_delta', {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {
          'type': 'citations_delta',
          'citation': {
            'type': 'web_search_result_location',
            'url': 'https://example.com',
            'title': null,
            'cited_text': 'quote',
            'encrypted_index': '',
          },
        },
      }) as ContentBlockDelta;

      expect((text.delta as TextDelta).text, 'hi');
      expect((thinking.delta as ThinkingDelta).thinking, 'hmm');
      expect((signature.delta as SignatureDelta).signature, 'sig');
      final c = (citation.delta as CitationsDelta).citation;
      expect(c.url, 'https://example.com');
      expect(c.title, isNull);
      expect(c.citedText, 'quote');
      expect(c.encryptedIndex, '');
    });

    test('drops input_json_delta and unknown deltas', () {
      expect(
        parse('content_block_delta', {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{}'},
        }),
        isNull,
      );
      expect(
        parse('content_block_delta', {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'future_delta'},
        }),
        isNull,
      );
    });

    test('parses content_block_stop and message_stop', () {
      final stop = parse('content_block_stop', {
        'type': 'content_block_stop',
        'index': 3,
      }) as ContentBlockStop;
      final messageStop =
          parse('message_stop', {'type': 'message_stop'}) as MessageStop;

      expect(stop.index, 3);
      expect(messageStop, isA<MessageStop>());
    });

    test('parses message_delta with stop details, title and usage', () {
      final event = parse('message_delta', {
        'type': 'message_delta',
        'delta': {
          'stop_reason': 'refusal',
          'stop_sequence': null,
          'stop_details': {'type': 'refusal', 'category': null, 'explanation': null},
          'title': '  A title  ',
        },
        'usage': {
          'input_tokens': 10,
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': 0,
          'output_tokens': 20,
          'server_tool_use': {'web_search_requests': 1, 'tool_search': 2},
        },
      }) as MessageDelta;

      expect(event.stopReason, StopReason.refusal);
      expect(event.stopDetails!.type, 'refusal');
      expect(event.title, '  A title  ');
      expect(event.usage!.outputTokens, 20);
      expect(event.usage!.webSearchRequests, 1);
      expect(event.usage!.toolSearch, 2);
    });

    test('drops ping, unknown events and bad JSON', () {
      expect(parse('ping', {'type': 'ping'}), isNull);
      expect(parse('future_event', {'type': 'future_event'}), isNull);
      expect(parse('message_delta', '{not json'), isNull);
    });

    test('drops recognized events with malformed fields', () {
      expect(parse('content_block_delta', {'type': 'content_block_delta'}), isNull);
      expect(
        parse('message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'future_reason'},
        }),
        isNull,
      );
    });

    test('throws a stream error for an error payload', () {
      expect(
        () => parse('message', {
          'error': {'type': 'overloaded_error', 'message': 'server busy'},
        }),
        streamError('server busy'),
      );
      expect(
        () => parse('error', {
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'server busy'},
        }),
        streamError('server busy'),
      );
    });

    test('throws a stream error for a non-JSON error event', () {
      expect(() => parse('error', 'plain failure'), streamError('plain failure'));
    });
  });
}
