import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/shared/api/request.dart';
import 'package:seek_chat/shared/models/reply_rules.dart';
import 'package:seek_chat/shared/models/types.dart';

UserMessage user(
  String id,
  String text, {
  List<Attachment> attachments = const [],
}) =>
    UserMessage(
      id: id,
      createdAt: DateTime(2026, 1, 1),
      text: text,
      attachments: attachments,
    );

AssistantMessage assistant(
  String id,
  String text, {
  ReplyStatus status = ReplyStatus.done,
  StopReason? stopReason = StopReason.endTurn,
  List<ReplyBlock>? blocks,
  String? latestReminder,
  bool prefix = true,
}) =>
    AssistantMessage(
      id: id,
      createdAt: DateTime(2026, 1, 1),
      status: status,
      stopReason: stopReason,
      blocks: blocks ?? [TextBlock(text: text)],
      latestReminder: latestReminder,
      prefix: prefix,
    );

TextCitation citation() => const TextCitation(
      url: 'https://example.com',
      title: 'Example',
      citedText: 'quote',
      encryptedIndex: '',
    );

void main() {
  group('buildMessageRequest', () {
    test('builds the fixed request envelope', () {
      final request = buildMessageRequest(
        history: const [],
        question: user('u1', 'Hello'),
        thinking: true,
        search: false,
      );

      expect(request.toJson(), {
        'model': 'deepseek-flash',
        'system': '该助手为DeepSeek，由深度求索公司创造。',
        'messages': [
          {
            'role': 'user',
            'content': 'Hello',
          },
        ],
        'thinking': {'type': 'enabled'},
        'tools': [
          {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'},
        ],
        'safety_check': {'level': 'high'},
        'stream': true,
      });
    });

    test('adds web search and title flags when requested', () {
      final request = buildMessageRequest(
        history: const [],
        question: user('u1', 'Hello'),
        thinking: false,
        search: true,
        titleEnabled: true,
      );

      final json = request.toJson();
      expect(json['thinking'], {'type': 'disabled'});
      expect(json['tools'], [
        {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'},
        {'type': 'deepseek_web_search', 'name': 'deepseek_web_search'},
      ]);
      expect(json['title'], {'enabled': true});
    });

    test('keeps only usable rounds and appends the current question', () {
      final history = [
        user('u1', 'first'),
        assistant('a1', 'answer one'),
        user('u2', 'second'),
        assistant('a2', '', status: ReplyStatus.error),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u3', 'third'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': 'first',
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'answer one'},
          ],
        },
        {
          'role': 'user',
          'content': 'third',
        },
      ]);
    });

    test('skips refusal, template and empty replies from history', () {
      final history = [
        user('u1', 'a'),
        assistant('a1', 'refused', stopReason: StopReason.refusal),
        user('u2', 'b'),
        assistant('a2', 'template', blocks: const [
          TextBlock(text: 'template', isTemplate: true),
        ]),
        user('u3', 'c'),
        assistant('a3', '', blocks: const [TextBlock(text: '')]),
        user('u4', 'kept'),
        assistant('a4', 'answer'),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u5', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': 'kept',
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'answer'},
          ],
        },
        {
          'role': 'user',
          'content': 'next',
        },
      ]);
    });

    test('sends files before text and only attachments with a server id', () {
      final question = user(
        'u1',
        'describe',
        attachments: const [
          Attachment(
            id: 'att-1',
            name: 'photo.jpg',
            size: 10,
            isImage: true,
            serverId: 'file-1',
          ),
          Attachment(
            id: 'att-2',
            name: 'notes.pdf',
            size: 20,
            serverId: 'file-2',
          ),
          Attachment(id: 'att-3', name: 'local.png', size: 30, isImage: true),
        ],
      );

      final json = buildMessageRequest(
        history: const [],
        question: question,
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {'type': 'file', 'file_id': 'file-1'},
            },
            {
              'type': 'document',
              'source': {'type': 'file', 'file_id': 'file-2'},
            },
            {'type': 'text', 'text': 'describe'},
          ],
        },
      ]);
    });

    test('keeps files without a text block when the text is empty', () {
      final question = user(
        'u1',
        '',
        attachments: const [
          Attachment(
            id: 'att-1',
            name: 'photo.jpg',
            size: 10,
            isImage: true,
            serverId: 'file-1',
          ),
        ],
      );

      final json = buildMessageRequest(
        history: const [],
        question: question,
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {'type': 'file', 'file_id': 'file-1'},
            },
          ],
        },
      ]);
    });

    test('drops a round whose question has no text and no files', () {
      final history = [
        user('u1', ''),
        assistant('a1', 'orphan answer'),
        user('u2', 'kept'),
        assistant('a2', 'answer'),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u3', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': 'kept',
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'answer'},
          ],
        },
        {
          'role': 'user',
          'content': 'next',
        },
      ]);
    });

    test('converts assistant history: thoughts dropped, text joined with blank lines', () {
      final history = [
        user('u1', 'question'),
        assistant(
          'a1',
          '',
          blocks: [
            const ThinkingBlock(thinking: 'history thought', signature: 'sig'),
            const TextBlock(text: 'part one'),
            const ServerToolUseBlock(
              id: 'tool-1',
              name: 'deepseek_web_search',
              input: SearchInput(queries: ['q']),
              kind: ServerToolKind.search,
            ),
            const WebSearchToolResultBlock(
              toolUseId: 'tool-1',
              content: [],
              kind: ServerToolKind.search,
            ),
            const TextBlock(text: 'part two'),
            const TextBlock(text: 'part three'),
          ],
        ),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u2', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'][1], {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'part one'},
          {'type': 'text', 'text': '\n\npart twopart three'},
        ],
      });
    });

    test('keeps read_link calls and signed results, drops unsigned ones', () {
      final history = [
        user('u1', 'question'),
        assistant(
          'a1',
          '',
          blocks: [
            const ServerToolUseBlock(
              id: 'call-signed',
              name: 'deepseek_read_url',
              input: ReadLinkInput('https://signed.example'),
              kind: ServerToolKind.readLink,
            ),
            const WebFetchToolResultBlock(
              toolUseId: 'call-signed',
              kind: ServerToolKind.readLink,
              signature: 'sig',
              content: WebFetchResult(
                url: 'https://signed.example',
                content: {'title': 'Signed'},
              ),
            ),
            const ServerToolUseBlock(
              id: 'call-unsigned',
              name: 'deepseek_read_url',
              input: ReadLinkInput('https://unsigned.example'),
              kind: ServerToolKind.readLink,
            ),
            const WebFetchToolResultBlock(
              toolUseId: 'call-unsigned',
              kind: ServerToolKind.readLink,
              content: WebFetchResult(
                url: 'https://unsigned.example',
                content: {},
              ),
            ),
            const ServerToolUseBlock(
              id: 'call-orphan',
              name: 'deepseek_read_url',
              input: ReadLinkInput('https://orphan.example'),
              kind: ServerToolKind.readLink,
            ),
            const TextBlock(text: 'answer'),
          ],
        ),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u2', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'][1], {
        'role': 'assistant',
        'content': [
          {
            'type': 'server_tool_use',
            'id': 'call-signed',
            'name': 'deepseek_read_url',
            'input': {'action': 'read_link', 'url': 'https://signed.example'},
            'kind': 'read_link',
          },
          {
            'type': 'web_fetch_tool_result',
            'tool_use_id': 'call-signed',
            'kind': 'read_link',
            'content': {
              'type': 'web_fetch_result',
              'url': 'https://signed.example',
              'content': {'title': 'Signed'},
              'published_at': null,
            },
            'signature': 'sig',
          },
          {
            'type': 'server_tool_use',
            'id': 'call-orphan',
            'name': 'deepseek_read_url',
            'input': {'action': 'read_link', 'url': 'https://orphan.example'},
            'kind': 'read_link',
          },
          {'type': 'text', 'text': 'answer'},
        ],
      });
    });

    test('drops search tools, results and deep search pages from history', () {
      final history = [
        user('u1', 'question'),
        assistant(
          'a1',
          '',
          blocks: [
            const ServerToolUseBlock(
              id: 'search-1',
              name: 'deepseek_web_search',
              input: SearchInput(queries: ['q']),
              kind: ServerToolKind.deepSearch,
            ),
            const WebSearchToolResultBlock(
              toolUseId: 'search-1',
              kind: ServerToolKind.deepSearch,
              content: [
                WebSearchResult(
                  title: 'Result',
                  url: 'https://result.example',
                  snippet: '',
                  encryptedContent: '',
                ),
              ],
            ),
            const ServerToolUseBlock(
              id: 'open-1',
              name: 'deepseek_web_search',
              input: OpenPageInput('https://page.example'),
              kind: ServerToolKind.deepSearch,
            ),
            const WebFetchToolResultBlock(
              toolUseId: 'open-1',
              kind: ServerToolKind.deepSearch,
              signature: 'sig',
              content: WebFetchResult(
                url: 'https://page.example',
                content: {'title': 'Page'},
              ),
            ),
            const TextBlock(text: 'answer'),
          ],
        ),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u2', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'][1], {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'answer'},
        ],
      });
    });

    test('drops citations and empty text blocks from assistant history', () {
      final history = [
        user('u1', 'question'),
        assistant(
          'a1',
          '',
          blocks: [
            TextBlock(text: 'cited', citations: [citation()]),
            const TextBlock(text: ''),
          ],
        ),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u2', 'next'),
        thinking: false,
        search: false,
      ).toJson();

      expect(json['messages'][1], {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'cited'},
        ],
      });
    });

    test('inserts latest reminders only when the snapshot changes', () {
      final history = [
        user('u1', 'one'),
        assistant('a1', 'answer one', latestReminder: 'snapshot A'),
        user('u2', 'two'),
        assistant('a2', 'answer two', latestReminder: 'snapshot A'),
        user('u3', 'three'),
        assistant('a3', 'answer three', latestReminder: 'snapshot B'),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u4', 'four'),
        thinking: false,
        search: false,
        latestReminder: 'snapshot B',
      ).toJson();

      final roles =
          (json['messages'] as List).map((m) => (m as Map)['role']).toList();
      expect(roles, [
        'latest_reminder',
        'user',
        'assistant',
        'user',
        'assistant',
        'latest_reminder',
        'user',
        'assistant',
        'user',
      ]);
      expect((json['messages'] as List)[0], {
        'role': 'latest_reminder',
        'content': 'snapshot A',
      });
      expect((json['messages'] as List)[5], {
        'role': 'latest_reminder',
        'content': 'snapshot B',
      });
    });

    test('does not insert a reminder when nothing changed', () {
      final history = [
        user('u1', 'one'),
        assistant('a1', 'answer', latestReminder: 'same'),
      ];

      final json = buildMessageRequest(
        history: history,
        question: user('u2', 'two'),
        thinking: false,
        search: false,
        latestReminder: 'same',
      ).toJson();

      final roles =
          (json['messages'] as List).map((m) => (m as Map)['role']).toList();
      expect(roles, ['latest_reminder', 'user', 'assistant', 'user']);
    });

    test('appends a continuation prefix with in-turn thinking', () {
      final prefix = AssistantMessage(
        id: 'a1',
        createdAt: DateTime(2026, 1, 1),
        status: ReplyStatus.stopped,
        stopReason: StopReason.endTurn,
        thinking: true,
        prefix: true,
        blocks: const [
          ThinkingBlock(thinking: 'turn thought', signature: 'sig'),
          TextBlock(text: 'partial answer'),
        ],
      );

      final json = buildMessageRequest(
        history: [user('u1', 'question')],
        question: user('u1', 'question'),
        thinking: true,
        search: false,
        prefix: prefix,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': 'question',
        },
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'thinking',
              'thinking': 'turn thought',
              'signature': 'sig',
            },
            {'type': 'text', 'text': 'partial answer'},
          ],
        },
      ]);
    });

    test('continuation reuses the reply snapshots over current settings', () {
      final prefix = AssistantMessage(
        id: 'a1',
        createdAt: DateTime(2026, 1, 1),
        status: ReplyStatus.stopped,
        stopReason: StopReason.endTurn,
        model: ChatModel.deepseekV4Pro,
        thinking: true,
        search: true,
        prefix: true,
        blocks: const [TextBlock(text: 'partial')],
      );

      final json = buildMessageRequest(
        history: const [],
        question: user('u1', 'question'),
        thinking: false,
        search: false,
        prefix: prefix,
      ).toJson();

      expect(json['model'], 'deepseek-v4-pro');
      expect(json['thinking'], {'type': 'enabled'});
      expect(json['tools'], [
        {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'},
        {'type': 'deepseek_web_search', 'name': 'deepseek_web_search'},
      ]);
    });

    test('omits a blank continuation thinking block without splitting text', () {
      final prefix = AssistantMessage(
        id: 'a1',
        createdAt: DateTime(2026, 1, 1),
        status: ReplyStatus.stopped,
        stopReason: StopReason.endTurn,
        thinking: true,
        prefix: true,
        blocks: const [
          TextBlock(text: 'first'),
          ThinkingBlock(thinking: '   '),
          TextBlock(text: 'second'),
        ],
      );

      final json = buildMessageRequest(
        history: const [],
        question: user('u1', 'question'),
        thinking: true,
        search: false,
        prefix: prefix,
      ).toJson();

      expect(json['messages'].last, {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'firstsecond'},
        ],
      });
    });

    test('omits the assistant prefix when it has no content', () {
      final prefix = AssistantMessage(
        id: 'a1',
        createdAt: DateTime(2026, 1, 1),
        status: ReplyStatus.stopped,
        stopReason: StopReason.endTurn,
        prefix: true,
        blocks: const [ThinkingBlock(thinking: '  ')],
      );

      final json = buildMessageRequest(
        history: const [],
        question: user('u1', 'question'),
        thinking: true,
        search: false,
        prefix: prefix,
      ).toJson();

      expect(json['messages'], [
        {
          'role': 'user',
          'content': 'question',
        },
      ]);
    });

    test('does not append a prefix when the reply is not prefixed', () {
      final prefix = AssistantMessage(
        id: 'a1',
        createdAt: DateTime(2026, 1, 1),
        status: ReplyStatus.stopped,
        stopReason: StopReason.endTurn,
        prefix: false,
        blocks: const [TextBlock(text: 'partial')],
      );

      final json = buildMessageRequest(
        history: const [],
        question: user('u1', 'question'),
        thinking: false,
        search: false,
        prefix: prefix,
      ).toJson();

      expect(json['messages'], hasLength(1));
    });
  });

  group('canContinueReply', () {
    test('allows stopped replies and max_tokens replies', () {
      expect(
        canContinueReply(assistant('a1', 'x', status: ReplyStatus.stopped)),
        isTrue,
      );
      expect(
        canContinueReply(assistant(
          'a1',
          'x',
          status: ReplyStatus.done,
          stopReason: StopReason.maxTokens,
        )),
        isTrue,
      );
    });

    test('rejects unfinished, refused, tool-calling and template replies', () {
      expect(
        canContinueReply(assistant('a1', 'x', status: ReplyStatus.streaming)),
        isFalse,
      );
      expect(
        canContinueReply(assistant(
          'a1',
          'x',
          status: ReplyStatus.stopped,
          stopReason: StopReason.refusal,
        )),
        isFalse,
      );
      expect(
        canContinueReply(assistant('a1', 'x', prefix: false)),
        isFalse,
      );
      expect(
        canContinueReply(assistant(
          'a1',
          '',
          blocks: const [
            TextBlock(text: 'answer'),
            ServerToolUseBlock(
              id: 'tool-1',
              name: 'deepseek_web_search',
              input: SearchInput(queries: ['q']),
              kind: ServerToolKind.search,
            ),
          ],
        )),
        isFalse,
      );
      expect(
        canContinueReply(assistant(
          'a1',
          '',
          blocks: const [TextBlock(text: 'notice', isTemplate: true)],
        )),
        isFalse,
      );
    });
  });

  group('replyThinkingSeconds', () {
    test('sums block durations and rounds up to at least one second', () {
      final reply = assistant(
        'a1',
        'x',
        blocks: const [
          ThinkingBlock(thinking: 'a', startedAt: 1000, endedAt: 2500),
          ThinkingBlock(thinking: 'b', startedAt: 3000, endedAt: 5000),
        ],
      );

      expect(replyThinkingSeconds(reply), 4);
    });

    test('uses imported elapsed seconds when timestamps are absent', () {
      final reply = assistant(
        'a1',
        'x',
        blocks: const [ThinkingBlock(thinking: 'a', elapsedSeconds: 3)],
      );

      expect(replyThinkingSeconds(reply), 3);
    });

    test('returns null when any block has no timing data', () {
      final reply = assistant(
        'a1',
        'x',
        blocks: const [
          ThinkingBlock(thinking: 'a', startedAt: 1000, endedAt: 2000),
          ThinkingBlock(thinking: 'b'),
        ],
      );

      expect(replyThinkingSeconds(reply), isNull);
    });
  });
}
