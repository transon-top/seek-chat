import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/data/database.dart';
import 'package:open_chat/data/chat_repository.dart';
import 'package:open_chat/models/types.dart';

void main() {
  late AppDatabase db;
  late ChatRepository repository;
  var tick = 1000;

  setUp(() {
    tick = 1000;
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db, clock: () => tick++);
  });

  tearDown(() => db.close());

  Future<(Session, UserMessage, AssistantMessage)> seeded() async {
    final session = await repository.createSession();
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: 'question',
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    return (session, user, reply);
  }

  group('sessions', () {
    test('creates empty sessions and lists them newest first', () async {
      final first = await repository.createSession();
      final second = await repository.createSession();
      await repository.renameSession(second.id, 'Second');

      final summaries = await repository.listSessions();

      expect(summaries.map((s) => s.id), [second.id, first.id]);
      expect(summaries.first.title, 'Second');
      expect(summaries.last.title, '');
    });

    test('renaming does not change updated_at', () async {
      final session = await repository.createSession();
      final before = (await repository.getSession(session.id))!;

      await repository.renameSession(session.id, 'Renamed');
      final after = (await repository.getSession(session.id))!;

      expect(after.title, 'Renamed');
      expect(after.updatedAt, before.updatedAt);
    });

    test('appending a question sets the root and selects the reply', () async {
      final session = await repository.createSession();
      final user = await repository.addUserMessage(
        sessionId: session.id,
        text: 'hi',
      );

      var loaded = (await repository.getSession(session.id))!;
      expect(loaded.rootMessageId, user.id);
      expect(user.parentId, isNull);
      expect(user.selectedChildId, isNull);

      tick += 10;
      final reply = await repository.createReply(
        sessionId: session.id,
        userMessageId: user.id,
        model: ChatModel.deepseekFlash,
        thinking: true,
        search: true,
      );

      loaded = (await repository.getSession(session.id))!;
      expect(loaded.updatedAt.millisecondsSinceEpoch, greaterThan(session.updatedAt.millisecondsSinceEpoch));

      final path = await repository.visiblePath(session.id);
      expect(path.map((m) => m.id), [user.id, reply.id]);
      expect(reply.status, ReplyStatus.pending);
      expect(reply.thinking, isTrue);
      expect(reply.search, isTrue);
      expect(reply.model, ChatModel.deepseekFlash);
    });
  });

  group('branches', () {
    test('regenerating adds a version and switching restores each branch', () async {
      final (session, user, firstReply) = await seeded();
      final secondReply = await repository.createReply(
        sessionId: session.id,
        userMessageId: user.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );

      expect(
        (await repository.visiblePath(session.id)).map((m) => m.id),
        [user.id, secondReply.id],
      );
      expect(
        (await repository.siblings(session.id, user.id)).map((m) => m.id),
        [firstReply.id, secondReply.id],
      );

      await repository.selectVersion(
        sessionId: session.id,
        messageId: firstReply.id,
      );
      expect(
        (await repository.visiblePath(session.id)).map((m) => m.id),
        [user.id, firstReply.id],
      );
    });

    test('editing a root question creates a new root version with attachments', () async {
      final session = await repository.createSession();
      const attachment = Attachment(
        id: 'att-1',
        name: 'photo.jpg',
        size: 10,
        isImage: true,
        localPath: 'attachments/att-1',
      );
      final original = await repository.addUserMessage(
        sessionId: session.id,
        text: 'original',
        attachments: const [attachment],
      );
      final originalReply = await repository.createReply(
        sessionId: session.id,
        userMessageId: original.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );

      final (edited, editedReply) = await repository.editUserMessage(
        sessionId: session.id,
        originalMessageId: original.id,
        text: 'edited',
        model: ChatModel.deepseekFlash,
        thinking: true,
        search: true,
        latestReminder: 'snapshot',
      );

      expect(edited.parentId, isNull);
      expect(edited.text, 'edited');
      expect(edited.attachments.single.id, 'att-1');
      expect(editedReply.status, ReplyStatus.pending);
      expect(editedReply.model, ChatModel.deepseekFlash);
      expect(editedReply.thinking, isTrue);
      expect(editedReply.search, isTrue);
      expect(editedReply.latestReminder, 'snapshot');

      final loaded = (await repository.getSession(session.id))!;
      expect(loaded.rootMessageId, edited.id);
      expect(
        (await repository.visiblePath(session.id)).map((m) => m.id),
        [edited.id, editedReply.id],
      );
      expect(
        (await repository.siblings(session.id, null)).map((m) => m.id),
        [original.id, edited.id],
      );

      await repository.selectVersion(
        sessionId: session.id,
        messageId: original.id,
      );
      expect(
        (await repository.visiblePath(session.id)).map((m) => m.id),
        [original.id, originalReply.id],
      );
    });

    test('editing a follow-up question keeps the rest of the tree', () async {
      final (session, firstUser, firstReply) = await seeded();
      final secondUser = await repository.addUserMessage(
        sessionId: session.id,
        text: 'follow-up',
      );
      final secondReply = await repository.createReply(
        sessionId: session.id,
        userMessageId: secondUser.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );

      final (edited, editedReply) = await repository.editUserMessage(
        sessionId: session.id,
        originalMessageId: secondUser.id,
        text: 'edited follow-up',
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );

      expect(edited.parentId, firstReply.id);
      expect(
        (await repository.visiblePath(session.id)).map((m) => m.id),
        [firstUser.id, firstReply.id, edited.id, editedReply.id],
      );
      expect(
        (await repository.siblings(session.id, firstReply.id)).map((m) => m.id),
        [secondUser.id, edited.id],
      );
      expect(
        (await repository.siblings(session.id, edited.id)).map((m) => m.id),
        [editedReply.id],
      );
      expect(secondReply.id, isNot(editedReply.id));
    });
  });

  group('replies', () {
    test('stores blocks, usage, stop details and error and reads them back', () async {
      final (session, _, reply) = await seeded();
      const citation = TextCitation(
        url: 'https://example.com',
        title: null,
        citedText: 'quote',
        encryptedIndex: '',
      );
      final blocks = <ReplyBlock>[
        const ThinkingBlock(
          thinking: 'thought',
          signature: 'sig',
          startedAt: 1000,
          endedAt: 2500,
        ),
        const TextBlock(text: 'answer', citations: [citation]),
        const ServerToolUseBlock(
          id: 'tool-1',
          name: 'deepseek_web_search',
          input: SearchInput(queries: ['q'], query: 'q'),
          kind: ServerToolKind.search,
        ),
        const WebSearchToolResultBlock(
          toolUseId: 'tool-1',
          content: [
            WebSearchResult(
              title: 'Result',
              url: 'https://example.com',
              snippet: 'snippet',
              siteIcon: null,
              siteName: null,
              encryptedContent: 'cipher',
              pageAge: null,
            ),
          ],
          kind: ServerToolKind.search,
        ),
      ];

      await repository.updateReply(
        messageId: reply.id,
        status: ReplyStatus.done,
        blocks: blocks,
        stopReason: StopReason.endTurn,
        stopDetails: const StopDetails(type: 'refusal'),
        usage: const Usage(
          inputTokens: 10,
          cacheCreationInputTokens: 1,
          cacheReadInputTokens: 2,
          outputTokens: 20,
          webSearchRequests: 1,
          toolSearch: 0,
        ),
        prefix: false,
      );

      final loaded = (await repository.loadMessages(session.id))
          .singleWhere((m) => m.id == reply.id) as AssistantMessage;

      expect(loaded.status, ReplyStatus.done);
      expect(loaded.prefix, isFalse);
      expect(loaded.stopReason, StopReason.endTurn);
      expect(loaded.stopDetails!.type, 'refusal');
      expect(loaded.usage!.outputTokens, 20);
      expect(loaded.usage!.webSearchRequests, 1);
      expect(loaded.blocks, hasLength(4));
      final thinking = loaded.blocks[0] as ThinkingBlock;
      expect(thinking.signature, 'sig');
      expect(thinking.startedAt, 1000);
      expect(thinking.endedAt, 2500);
      final text = loaded.blocks[1] as TextBlock;
      expect(text.citations.single.url, 'https://example.com');
      final tool = loaded.blocks[2] as ServerToolUseBlock;
      expect((tool.input as SearchInput).queries, ['q']);
      final result = loaded.blocks[3] as WebSearchToolResultBlock;
      expect((result.content.single as WebSearchResult).title, 'Result');
    });

    test('persists an error payload', () async {
      final (session, _, reply) = await seeded();

      await repository.updateReply(
        messageId: reply.id,
        status: ReplyStatus.error,
        blocks: const [],
        error: const ReplyError(
          kind: ApiErrorKind.upload,
          message: 'upload failed',
          localMessage: LocalMessage(key: 'uploadParseFailed'),
          retryable: true,
        ),
      );

      final loaded = (await repository.loadMessages(session.id))
          .singleWhere((m) => m.id == reply.id) as AssistantMessage;
      expect(loaded.error!.kind, ApiErrorKind.upload);
      expect(loaded.error!.localMessage!.key, 'uploadParseFailed');
      expect(loaded.error!.retryable, isTrue);
    });

    test('opening a session treats leftover generation as stopped without writing', () async {
      final (session, _, reply) = await seeded();
      await repository.updateReply(
        messageId: reply.id,
        status: ReplyStatus.streaming,
        blocks: const [ThinkingBlock(thinking: 'hmm', startedAt: 1000)],
      );
      final updatedAt = (await repository.getSession(session.id))!.updatedAt;

      final shown = (await repository.loadMessagesForDisplay(session.id))
          .singleWhere((m) => m.id == reply.id) as AssistantMessage;

      expect(shown.status, ReplyStatus.stopped);
      expect(
        (shown.blocks.single as ThinkingBlock).endedAt,
        updatedAt.millisecondsSinceEpoch,
      );

      final stored = (await repository.loadMessages(session.id))
          .singleWhere((m) => m.id == reply.id) as AssistantMessage;
      expect(stored.status, ReplyStatus.streaming);
    });

    test('writes the reminder snapshot before the request', () async {
      final (session, _, reply) = await seeded();

      await repository.setLatestReminder(reply.id, 'snapshot');

      final loaded = (await repository.loadMessages(session.id))
          .singleWhere((m) => m.id == reply.id) as AssistantMessage;
      expect(loaded.latestReminder, 'snapshot');
    });

    test('continuation reuses the row and its snapshots', () async {
      final session = await repository.createSession();
      final user = await repository.addUserMessage(
        sessionId: session.id,
        text: 'question',
      );
      final reply = await repository.createReply(
        sessionId: session.id,
        userMessageId: user.id,
        model: ChatModel.deepseekV4Pro,
        thinking: true,
        search: true,
        latestReminder: 'snapshot',
      );
      await repository.updateReply(
        messageId: reply.id,
        status: ReplyStatus.stopped,
        blocks: const [TextBlock(text: 'partial')],
        stopReason: StopReason.endTurn,
        usage: const Usage(
          inputTokens: 1,
          cacheCreationInputTokens: 0,
          cacheReadInputTokens: 0,
          outputTokens: 2,
        ),
      );
      final before = (await repository.getSession(session.id))!;

      await repository.beginContinuation(reply.id);

      final after = (await repository.getSession(session.id))!;
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
      final messages = await repository.loadMessages(session.id);
      final continued = messages.singleWhere((m) => m.id == reply.id) as AssistantMessage;
      expect(continued.status, ReplyStatus.pending);
      expect(continued.model, ChatModel.deepseekV4Pro);
      expect(continued.thinking, isTrue);
      expect(continued.search, isTrue);
      expect(continued.latestReminder, 'snapshot');
      expect(continued.stopReason, isNull);
      expect(continued.stopDetails, isNull);
      expect(continued.usage!.outputTokens, 2);
      expect((continued.blocks.single as TextBlock).text, 'partial');
    });

    test('startup marks pending and streaming replies as stopped', () async {
      final (session, user, pending) = await seeded();
      final streaming = await repository.createReply(
        sessionId: session.id,
        userMessageId: user.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );
      final done = await repository.createReply(
        sessionId: session.id,
        userMessageId: user.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );
      await repository.updateReply(
        messageId: streaming.id,
        status: ReplyStatus.streaming,
        blocks: const [],
      );
      await repository.updateReply(
        messageId: done.id,
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'done')],
        stopReason: StopReason.endTurn,
      );

      final changed = await repository.resetInterruptedReplies();

      expect(changed, 2);
      final messages = await repository.loadMessages(session.id);
      expect(messages.singleWhere((m) => m.id == pending.id), isA<AssistantMessage>().having((m) => m.status, 'status', ReplyStatus.stopped));
      expect(messages.singleWhere((m) => m.id == streaming.id), isA<AssistantMessage>().having((m) => m.status, 'status', ReplyStatus.stopped));
      expect(messages.singleWhere((m) => m.id == done.id), isA<AssistantMessage>().having((m) => m.status, 'status', ReplyStatus.done));
    });
  });

  group('attachments', () {
    test('shares a server id across every message that references the file', () async {
      final session = await repository.createSession();
      const attachment = Attachment(id: 'att-1', name: 'a.png', size: 3, isImage: true);
      await repository.addUserMessage(sessionId: session.id, text: 'one', attachments: const [attachment]);
      await repository.addUserMessage(sessionId: session.id, text: 'two', attachments: const [attachment]);

      await repository.setAttachmentServerId('att-1', 'file-1');

      final messages = await repository.loadMessages(session.id);
      for (final message in messages.whereType<UserMessage>()) {
        expect(message.attachments.single.serverId, 'file-1');
      }
    });

    test('deleting a session removes only unreferenced attachments', () async {
      final first = await repository.createSession();
      final second = await repository.createSession();
      const shared = Attachment(
        id: 'shared',
        name: 'shared.png',
        size: 1,
        localPath: 'attachments/shared',
      );
      const orphan = Attachment(
        id: 'orphan',
        name: 'orphan.png',
        size: 1,
        localPath: 'attachments/orphan',
      );
      await repository.addUserMessage(
        sessionId: first.id,
        text: 'one',
        attachments: const [shared, orphan],
      );
      await repository.addUserMessage(
        sessionId: second.id,
        text: 'two',
        attachments: const [shared],
      );

      final deleted = await repository.deleteSession(first.id);

      expect(deleted.map((a) => a.id), ['orphan']);
      expect(await repository.getSession(first.id), isNull);
      expect(await repository.loadMessages(first.id), isEmpty);
      final remaining = await repository.loadMessages(second.id);
      expect((remaining.single as UserMessage).attachments.single.id, 'shared');
      expect(await repository.attachmentLocalPaths(), {'attachments/shared'});
    });
  });
}
