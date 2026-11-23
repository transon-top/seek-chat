import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/features/history/history_service.dart';
import 'package:seek_chat/features/history/history_zip.dart';
import 'package:seek_chat/shared/data/attachment_store.dart';
import 'package:seek_chat/shared/data/chat_repository.dart';
import 'package:seek_chat/shared/data/database.dart';
import 'package:seek_chat/shared/models/types.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory support;
  late AppDatabase db;
  late ChatRepository repository;
  late AttachmentStore store;
  late HistoryService service;
  var nextId = 0;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('seek_chat_history_');
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    store = AttachmentStore(supportDirectory: () async => support);
    nextId = 0;
    service = HistoryService(
      repository,
      store,
      newId: () => 'local-${++nextId}',
      now: () => DateTime(2026, 1, 2),
    );
  });

  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

  Future<(Session, String)> seedConversation() async {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ]);
    final localPath = await store.saveBytes('img-1', png);
    final session = await repository.createSession();
    await repository.renameSession(session.id, 'Seeded');
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: 'question',
      attachments: [
        Attachment(
          id: 'img-1',
          name: 'photo.png',
          size: png.length,
          isImage: true,
          mimeType: 'image/png',
          localPath: localPath,
        ),
      ],
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: true,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'answer')],
    );
    return (session, localPath);
  }

  test('exports and reimports a full conversation with its image', () async {
    final (session, _) = await seedConversation();

    final exported = await service.exportArchive(notice: (_) => null);

    expect(exported.fileName, 'deepseek_data-2026-01-02.zip');
    expect(exported.bytes, isNotEmpty);

    var stopped = 0;
    final count = await service.importArchive(
      exported.bytes,
      stopGeneration: () => stopped++,
    );

    expect(count, 1);
    expect(stopped, 1);
    final summaries = await repository.listSessions();
    expect(summaries.single.id, session.id);
    expect(summaries.single.title, 'Seeded');

    final path = await repository.visiblePath(session.id);
    expect(path, hasLength(2));
    final user = path.first as UserMessage;
    expect(user.text, 'question');
    final attachment = user.attachments.single;
    expect(attachment.id, isNot('img-1'));
    expect(attachment.mimeType, 'image/png');
    expect(attachment.localPath, 'attachments/${attachment.id}');
    expect(
      File(p.join(support.path, attachment.localPath!)).readAsBytesSync(),
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    );

    final reply = path.last as AssistantMessage;
    expect(reply.status, ReplyStatus.done);
    expect(reply.prefix, isFalse);
    expect(reply.thinking, isTrue);
    expect((reply.blocks.single as TextBlock).text, 'answer');
  });

  test('exports and reimports sessions without messages', () async {
    final session = await repository.createSession();
    await repository.renameSession(session.id, 'Empty');

    final exported = await service.exportArchive(notice: (_) => null);
    final decoded = decodeHistoryZip(exported.bytes, newId: () => 'unused');
    expect(decoded.sessions, hasLength(1));
    expect(decoded.sessions.single.session.id, session.id);
    expect(decoded.sessions.single.messages, isEmpty);

    await service.importArchive(exported.bytes, stopGeneration: () {});
    final restored = await repository.listSessions(includeEmpty: true);
    expect(restored.single.id, session.id);
    expect(restored.single.title, 'Empty');
  });

  test('round-trips the pinned flag', () async {
    final (session, _) = await seedConversation();
    await repository.setSessionsPinned([session.id], true);

    final exported = await service.exportArchive(notice: (_) => null);
    final decoded = decodeHistoryZip(exported.bytes, newId: () => 'unused');
    expect(decoded.sessions.single.session.pinned, isTrue);

    await service.importArchive(exported.bytes, stopGeneration: () {});
    expect((await repository.getSession(session.id))!.pinned, isTrue);
  });

  test('import replaces other sessions and keeps the restored image file',
      () async {
    final (seeded, _) = await seedConversation();
    final exported = await service.exportArchive(notice: (_) => null);

    final other = await repository.createSession();
    final otherFile = await store.saveBytes('old-file', [9, 9]);
    await repository.addUserMessage(
      sessionId: other.id,
      text: 'old',
      attachments: [
        Attachment(
          id: 'old-file',
          name: 'old.bin',
          size: 2,
          localPath: otherFile,
        ),
      ],
    );

    await service.importArchive(exported.bytes, stopGeneration: () {});

    expect((await repository.listSessions()).single.id, seeded.id);
    expect(await repository.getSession(other.id), isNull);
    expect(
      File(p.join(support.path, otherFile)).existsSync(),
      isFalse,
    );
    final restored = (await repository.visiblePath(seeded.id))
        .whereType<UserMessage>()
        .single
        .attachments
        .single;
    expect(
      File(p.join(support.path, restored.localPath!)).existsSync(),
      isTrue,
    );
  });

  test('rejects a corrupt archive before stopping generation or changing data',
      () async {
    final (session, _) = await seedConversation();
    var stopped = 0;

    await expectLater(
      service.importArchive(
        Uint8List.fromList([1, 2, 3, 4]),
        stopGeneration: () => stopped++,
      ),
      throwsA(
        isA<HistoryException>().having(
          (error) => error.code,
          'code',
          HistoryError.unrecognized,
        ),
      ),
    );

    expect(stopped, 0);
    expect((await repository.listSessions()).single.id, session.id);
    expect(await repository.visiblePath(session.id), hasLength(2));
  });

  test('seeds archives with the export-time error notice', () async {
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
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.error,
      blocks: const [],
      error: const ReplyError(
        kind: ApiErrorKind.network,
        message: 'offline',
      ),
    );

    final exported = await service.exportArchive(
      notice: (item) => 'NETWORK ERROR',
    );
    await service.importArchive(exported.bytes, stopGeneration: () {});

    final imported = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(imported.status, ReplyStatus.error);
    expect((imported.blocks.single as TextBlock).text, 'NETWORK ERROR');
    expect((imported.blocks.single as TextBlock).isTemplate, isTrue);
  });
}
