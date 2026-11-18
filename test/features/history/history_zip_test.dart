import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/features/history/history_zip.dart';
import 'package:open_chat/shared/models/types.dart';

DateTime at(int second) => DateTime.utc(2026, 1, 2, 3, 4, second);

Session sessionWith({String title = 'Hello'}) => Session(
      id: 'session-1',
      title: title,
      createdAt: at(5),
      updatedAt: at(9),
      rootMessageId: 'message-1',
    );

(UserMessage, AssistantMessage) textRound() {
  final user = UserMessage(
    id: 'message-1',
    createdAt: at(5),
    text: 'Hi',
    selectedChildId: 'message-2',
  );
  final reply = AssistantMessage(
    id: 'message-2',
    parentId: 'message-1',
    createdAt: at(6),
    status: ReplyStatus.done,
    blocks: const [TextBlock(text: 'Hello there')],
    thinking: false,
    search: false,
  );
  return (user, reply);
}

Uint8List zipOf(List<(String, Object?)> entries) {
  final archive = Archive();
  for (final (name, value) in entries) {
    final bytes = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, bytes.length, bytes)..compress = false);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0)!);
}

Map<String, Object?> manifestJson(int version) => {
      'export_format_version': version,
    };

List<Map<String, Object?>> indexJson(List<String> ids) => [
      for (final id in ids)
        {
          'id': id,
          'title': null,
          'pinned': false,
          'message_count': 0,
          'inserted_at': '2026-01-02T03:04:05.000Z',
          'updated_at': '2026-01-02T03:04:05.000Z',
        },
    ];

Map<String, Object?> messageJson({
  required int id,
  int? parentId,
  String role = 'USER',
  String status = 'FINISHED',
  List<Map<String, dynamic>>? fragments,
}) =>
    {
      'id': id,
      'parent_id': parentId,
      'role': role,
      'status': status,
      'thinking_enabled': false,
      'search_enabled': false,
      'accumulated_token_usage': 0,
      'inserted_at': '2026-01-02T03:04:05.000Z',
      'fragments': fragments ?? const [],
    };

Map<String, Object?> sessionJson({
  String id = 'session-1',
  int currentMessageId = 0,
  List<Map<String, Object?>> messages = const [],
}) =>
    {
      'id': id,
      'title': null,
      'pinned': false,
      'current_message_id': currentMessageId,
      'inserted_at': '2026-01-02T03:04:05.000Z',
      'updated_at': '2026-01-02T03:04:05.000Z',
      'messages': messages,
    };


Uint8List zipOfBytes(List<(String, List<int>)> entries) {
  final archive = Archive();
  for (final (name, bytes) in entries) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes)..compress = false);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0)!);
}

/// 只含一个条目的手写 ZIP32，用于声明超限/加密而不实际分配大文件。
Uint8List declaredZip({
  required String name,
  required int uncompressedSize,
  int flags = 0,
}) {
  final nameBytes = utf8.encode(name);
  final localSize = 30 + nameBytes.length;
  final centralSize = 46 + nameBytes.length;
  final total = localSize + centralSize + 22;
  final data = ByteData(total);
  var offset = 0;

  void u16(int value) {
    data.setUint16(offset, value, Endian.little);
    offset += 2;
  }

  void u32(int value) {
    data.setUint32(offset, value, Endian.little);
    offset += 4;
  }

  void bytes(List<int> value) {
    for (final byte in value) {
      data.setUint8(offset++, byte);
    }
  }

  // local file header
  u32(0x04034b50);
  u16(20);
  u16(flags);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  u32(uncompressedSize);
  u16(nameBytes.length);
  u16(0);
  bytes(nameBytes);

  // central directory header
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(flags);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  u32(uncompressedSize);
  u16(nameBytes.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  bytes(nameBytes);

  // end of central directory
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(centralSize);
  u32(localSize);
  u16(0);

  return data.buffer.asUint8List();
}

void main() {
  group('archive format', () {
    test('round-trips a text conversation through the version 3 ZIP', () {
      final (user, reply) = textRound();
      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        notice: (_) => null,
      );

      final zip = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(zip.files.map((file) => file.name).toList(), [
        'manifest.json',
        'chat_sessions/session-1.json',
        'chat_session_index.json',
      ]);
      final manifest =
          jsonDecode(utf8.decode(zip.files.first.content)) as Map;
      expect(manifest, {'export_format_version': 3});

      final sessionJson =
          jsonDecode(utf8.decode(zip.files[1].content)) as Map<String, dynamic>;
      expect(sessionJson['id'], 'session-1');
      expect(sessionJson['title'], 'Hello');
      expect(sessionJson['current_message_id'], 2);
      expect(sessionJson['inserted_at'], '2026-01-02T03:04:05.000Z');
      final messages = sessionJson['messages'] as List;
      expect(messages[0], containsPair('role', 'USER'));
      expect(messages[0], containsPair('id', 1));
      expect(messages[0], containsPair('parent_id', null));
      expect(messages[0]['fragments'], [
        {'type': 'REQUEST', 'content': 'Hi'},
      ]);
      expect(messages[1], containsPair('role', 'ASSISTANT'));
      expect(messages[1], containsPair('parent_id', 1));
      expect(messages[1], containsPair('status', 'FINISHED'));
      expect(messages[1]['fragments'], [
        {'type': 'RESPONSE', 'content': 'Hello there'},
      ]);

      var next = 0;
      final decoded = decodeHistoryZip(bytes, newId: () => 'local-${++next}');

      expect(decoded.sessions, hasLength(1));
      final tree = decoded.sessions.single;
      expect(tree.session.title, 'Hello');
      expect(tree.session.createdAt, at(5));
      expect(tree.session.updatedAt, at(9));
      expect(tree.messages, hasLength(2));

      final decodedUser = tree.messages[0] as UserMessage;
      expect(decodedUser.id, 'local-1');
      expect(decodedUser.text, 'Hi');
      expect(decodedUser.parentId, isNull);
      expect(decodedUser.selectedChildId, 'local-2');
      expect(tree.session.rootMessageId, 'local-1');

      final decodedReply = tree.messages[1] as AssistantMessage;
      expect(decodedReply.id, 'local-2');
      expect(decodedReply.parentId, 'local-1');
      expect(decodedReply.status, ReplyStatus.done);
      expect(decodedReply.prefix, isFalse);
      expect(decodedReply.blocks, hasLength(1));
      expect((decodedReply.blocks.single as TextBlock).text, 'Hello there');
    });

    test('exports image originals and restores their MIME on import', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Look',
        selectedChildId: 'message-2',
        attachments: const [
          Attachment(
            id: 'img-1',
            name: 'photo.png',
            size: 8,
            isImage: true,
          ),
          Attachment(
            id: 'doc-1',
            name: 'notes.pdf',
            size: 3,
            mimeType: 'application/pdf',
          ),
        ],
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'Nice')],
      );
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ]);

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        imageBytes: {'img-1': png},
        notice: (_) => null,
      );

      final zip = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(zip.files.map((file) => file.name), contains(
        'chat_sessions/session-1_files/img-1_photo.png',
      ));
      final sessionJson =
          jsonDecode(utf8.decode(zip.files[1].content)) as Map<String, dynamic>;
      final filesJson = ((sessionJson['messages'] as List)[0]
          as Map<String, dynamic>)['fragments'] as List;
      final fileEntries =
          (filesJson[0] as Map<String, dynamic>)['files'] as List;
      expect(fileEntries[0]['id'], 'img-1');
      expect(
        fileEntries[0]['export_path'],
        'chat_sessions/session-1_files/img-1_photo.png',
      );
      expect(fileEntries[1]['id'], 'doc-1');
      expect(fileEntries[1]['export_path'], isNull);
      expect(fileEntries[1]['is_image'], isFalse);

      var next = 0;
      final decoded = decodeHistoryZip(bytes, newId: () => 'local-${++next}');
      final decodedUser = decoded.sessions.single.messages[0] as UserMessage;

      expect(decoded.images['img-1']?.bytes, png);
      expect(decoded.images['img-1']?.mimeType, 'image/png');
      expect(decodedUser.attachments, hasLength(2));
      expect(decodedUser.attachments[0].mimeType, 'image/png');
      expect(decodedUser.attachments[0].localPath, isNull);
      expect(decodedUser.attachments[1].isImage, isFalse);
      expect(decodedUser.attachments[1].mimeType, '');
    });

    test('missing image originals keep metadata only', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Look',
        selectedChildId: 'message-2',
        attachments: const [
          Attachment(
            id: 'img-1',
            name: 'photo.png',
            size: 8,
            isImage: true,
          ),
        ],
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'Nice')],
      );

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        notice: (_) => null,
      );

      final decoded = decodeHistoryZip(bytes, newId: () => 'local');
      final decodedUser = decoded.sessions.single.messages[0] as UserMessage;

      expect(decoded.images, isEmpty);
      expect(decodedUser.attachments.single.name, 'photo.png');
      expect(decodedUser.attachments.single.localPath, isNull);
    });

    test('round-trips thinking, search, citations and read-link blocks', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Research',
        selectedChildId: 'message-2',
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.done,
        thinking: true,
        search: true,
        blocks: const [
          ThinkingBlock(
            thinking: 'plan',
            startedAt: 1000,
            endedAt: 3500,
          ),
          ServerToolUseBlock(
            id: 'toolu-1',
            name: 'deepseek_web_search',
            input: SearchInput(queries: ['flutter']),
            kind: ServerToolKind.search,
          ),
          WebSearchToolResultBlock(
            toolUseId: 'toolu-1',
            kind: ServerToolKind.search,
            content: [
              WebSearchResult(
                title: 'One',
                url: 'https://one.example',
                snippet: 'snip',
                encryptedContent: '',
                siteName: 'Site',
                pageAge: '2026-01-02T00:00:00.000Z',
              ),
            ],
          ),
          TextBlock(text: 'See [citation:1]'),
          ServerToolUseBlock(
            id: 'toolu-2',
            name: 'deepseek_read_url',
            input: ReadLinkInput('https://two.example'),
            kind: ServerToolKind.readLink,
          ),
          WebFetchToolResultBlock(
            toolUseId: 'toolu-2',
            kind: ServerToolKind.readLink,
            content: WebFetchResult(
              url: 'https://two.example',
              content: {'title': 'Two'},
            ),
            signature: 'sig-2',
          ),
          TextBlock(text: 'after'),
        ],
      );

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        notice: (_) => null,
      );
      var next = 0;
      final decoded = decodeHistoryZip(bytes, newId: () => 'local-${++next}');
      final decodedReply = decoded.sessions.single.messages[1]
          as AssistantMessage;

      expect(decodedReply.thinking, isTrue);
      expect(decodedReply.search, isTrue);
      expect(decodedReply.status, ReplyStatus.done);
      final blocks = decodedReply.blocks;
      expect(blocks, hasLength(7));
      final thinking = blocks[0] as ThinkingBlock;
      expect(thinking.thinking, 'plan');
      expect(thinking.elapsedSeconds, 2);

      final searchUse = blocks[1] as ServerToolUseBlock;
      expect(searchUse.kind, ServerToolKind.search);
      expect((searchUse.input as SearchInput).queries, ['flutter']);
      final searchResult = blocks[2] as WebSearchToolResultBlock;
      expect(searchResult.toolUseId, searchUse.id);
      expect(searchResult.kind, ServerToolKind.search);
      final item = searchResult.content.single as WebSearchResult;
      expect(item.url, 'https://one.example');
      expect(item.pageAge, '2026-01-02T00:00:00.000Z');
      expect((blocks[3] as TextBlock).text, 'See ');

      final readUse = blocks[4] as ServerToolUseBlock;
      expect(readUse.kind, ServerToolKind.readLink);
      expect((readUse.input as ReadLinkInput).url, 'https://two.example');
      final fetch = blocks[5] as WebFetchToolResultBlock;
      expect(fetch.toolUseId, readUse.id);
      expect(fetch.kind, ServerToolKind.readLink);
      expect(fetch.signature, 'sig-2');
      expect((fetch.content as WebFetchResult).title, 'Two');
      expect((blocks[6] as TextBlock).text, 'after');
    });

    test('restores only the current branch selection', () {
      final root = UserMessage(
        id: 'root',
        createdAt: at(5),
        text: 'Question',
        selectedChildId: 'answer-2',
      );
      final first = AssistantMessage(
        id: 'answer-1',
        parentId: 'root',
        createdAt: at(6),
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'First')],
      );
      final second = AssistantMessage(
        id: 'answer-2',
        parentId: 'root',
        createdAt: at(7),
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'Second')],
      );

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: Session(
              id: 'session-1',
              title: 'Hello',
              createdAt: at(5),
              updatedAt: at(9),
              rootMessageId: 'root',
            ),
            messages: [root, first, second],
          ),
        ],
        notice: (_) => null,
      );
      var next = 0;
      final decoded = decodeHistoryZip(bytes, newId: () => 'local-${++next}');
      final messages = decoded.sessions.single.messages;

      expect(messages, hasLength(3));
      final decodedRoot = messages.whereType<UserMessage>().single;
      final assistants = messages.whereType<AssistantMessage>().toList();
      expect(decodedRoot.selectedChildId, assistants.last.id);
      expect(assistants.map((item) => item.parentId), everyElement(decodedRoot.id));
      expect(decoded.sessions.single.session.rootMessageId, decodedRoot.id);
      expect(
        (assistants.last.blocks.single as TextBlock).text,
        'Second',
      );
    });

    test('refusals keep only the template and import as refusal', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Bad',
        selectedChildId: 'message-2',
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.done,
        stopReason: StopReason.refusal,
        thinking: true,
        blocks: const [
          ThinkingBlock(thinking: 'secret reasoning'),
          TextBlock(text: 'must not export'),
        ],
      );

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        notice: (_) => 'REFUSED',
      );
      final zip = ZipDecoder().decodeBytes(bytes, verify: true);
      final sessionJson =
          jsonDecode(utf8.decode(zip.files[1].content)) as Map<String, dynamic>;
      final replyJson = (sessionJson['messages'] as List)[1]
          as Map<String, dynamic>;
      expect(replyJson['status'], 'CONTENT_FILTER');
      expect((replyJson['fragments'] as List).last, {
        'type': 'TEMPLATE_RESPONSE',
        'content': 'REFUSED',
      });

      var next = 0;
      final decoded = decodeHistoryZip(bytes, newId: () => 'local-${++next}');
      final decodedReply = decoded.sessions.single.messages[1]
          as AssistantMessage;
      expect(decodedReply.status, ReplyStatus.done);
      expect(decodedReply.stopReason, StopReason.refusal);
      expect(decodedReply.blocks, hasLength(1));
      expect((decodedReply.blocks.single as TextBlock).isTemplate, isTrue);
      expect((decodedReply.blocks.single as TextBlock).text, 'REFUSED');
    });

    test('errors export a localized template and import as failed', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Question',
        selectedChildId: 'message-2',
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.error,
        blocks: const [TextBlock(text: 'partial')],
        error: const ReplyError(
          kind: ApiErrorKind.network,
          message: 'offline',
        ),
      );

      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        notice: (_) => 'BOOM',
      );
      final decoded = decodeHistoryZip(bytes, newId: () => 'local');

      final decodedReply = decoded.sessions.single.messages[1]
          as AssistantMessage;
      expect(decodedReply.status, ReplyStatus.error);
      expect(decodedReply.blocks, hasLength(2));
      expect((decodedReply.blocks[0] as TextBlock).text, 'partial');
      expect((decodedReply.blocks[1] as TextBlock).isTemplate, isTrue);
      expect((decodedReply.blocks[1] as TextBlock).text, 'BOOM');
    });

    test('empty sessions round-trip with a null root', () {
      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: Session(
              id: 'empty',
              title: '',
              createdAt: at(1),
              updatedAt: at(1),
            ),
            messages: const [],
          ),
        ],
        notice: (_) => null,
      );

      final decoded = decodeHistoryZip(bytes, newId: () => 'unused');

      expect(decoded.sessions.single.session.title, '');
      expect(decoded.sessions.single.session.rootMessageId, isNull);
      expect(decoded.sessions.single.messages, isEmpty);
    });
  });

  group('validation', () {
    Matcher throwsHistory(HistoryError code) => throwsA(
          isA<HistoryException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        );

    Uint8List validZip({
      Object? manifest,
      List<Map<String, Object?>>? messages,
      int currentMessageId = 0,
      List<String>? indexIds,
    }) {
      final sessionMessages = messages ?? const [];
      return zipOf([
        ('manifest.json', manifest ?? manifestJson(3)),
        ('chat_sessions/session-1.json', sessionJson(
          currentMessageId: currentMessageId,
          messages: sessionMessages,
        )),
        ('chat_session_index.json', indexJson(indexIds ?? ['session-1'])),
      ]);
    }

    test('rejects newer, older and missing manifests', () {
      expect(
        () => decodeHistoryZip(
          validZip(manifest: manifestJson(4)),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.newerVersion),
      );
      expect(
        () => decodeHistoryZip(
          validZip(manifest: manifestJson(2)),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidVersion),
      );
      expect(
        () => decodeHistoryZip(
          validZip(manifest: {'version': 3}),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidVersion),
      );
      expect(
        () => decodeHistoryZip(
          zipOf([('chat_sessions/session-1.json', sessionJson())]),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.unrecognized),
      );
      expect(
        () => decodeHistoryZip(Uint8List.fromList([1, 2, 3, 4]), newId: () => 'id'),
        throwsHistory(HistoryError.unrecognized),
      );
    });

    test('rejects corrupted message branches', () {
      final duplicate = [
        messageJson(
          id: 1,
          fragments: [{'type': 'REQUEST', 'content': 'a'}],
        ),
        messageJson(
          id: 1,
          role: 'ASSISTANT',
          fragments: [{'type': 'RESPONSE', 'content': 'b'}],
        ),
      ];
      expect(
        () => decodeHistoryZip(
          validZip(messages: duplicate, currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidBranches),
      );

      final missingParent = [
        messageJson(
          id: 2,
          parentId: 1,
          role: 'ASSISTANT',
          fragments: [{'type': 'RESPONSE', 'content': 'b'}],
        ),
      ];
      expect(
        () => decodeHistoryZip(
          validZip(messages: missingParent, currentMessageId: 2),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidBranches),
      );

      final sameRole = [
        messageJson(
          id: 1,
          fragments: [{'type': 'REQUEST', 'content': 'a'}],
        ),
        messageJson(
          id: 2,
          parentId: 1,
          fragments: [{'type': 'REQUEST', 'content': 'b'}],
        ),
      ];
      expect(
        () => decodeHistoryZip(
          validZip(messages: sameRole, currentMessageId: 2),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidBranches),
      );

      final assistantRoot = [
        messageJson(
          id: 1,
          role: 'ASSISTANT',
          fragments: [{'type': 'RESPONSE', 'content': 'a'}],
        ),
      ];
      expect(
        () => decodeHistoryZip(
          validZip(messages: assistantRoot, currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidBranches),
      );

      final valid = [
        messageJson(
          id: 1,
          fragments: [{'type': 'REQUEST', 'content': 'a'}],
        ),
      ];
      expect(
        () => decodeHistoryZip(
          validZip(messages: valid, currentMessageId: 9),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidBranches),
      );
    });

    test('strict metadata fails while malformed fragments are dropped', () {
      final missingStatus = messageJson(
        id: 1,
        fragments: [{'type': 'REQUEST', 'content': 'a'}],
      )..remove('status');
      expect(
        () => decodeHistoryZip(
          validZip(messages: [missingStatus], currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.incomplete),
      );

      final dropped = [
        messageJson(
          id: 1,
          fragments: [
            {'type': 'REQUEST', 'content': 'a'},
            {'type': 'RESPONSE', 'content': 42},
            {'type': 'UNKNOWN', 'content': 'x'},
          ],
        ),
      ];
      final decoded = decodeHistoryZip(
        validZip(messages: dropped, currentMessageId: 1),
        newId: () => 'id',
      );
      expect((decoded.sessions.single.messages.single as UserMessage).text, 'a');
    });

    test('rejects a mismatched index and unsafe entry names', () {
      expect(
        () => decodeHistoryZip(
          validZip(indexIds: ['session-1', 'session-2']),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.incomplete),
      );

      expect(
        () => decodeHistoryZip(
          zipOf([
            ('manifest.json', manifestJson(3)),
            ('chat_sessions/../evil.json', sessionJson()),
          ]),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.unrecognized),
      );
    });


    test('accepts fractional think seconds and skips user.json', () {
      final user = messageJson(
        id: 1,
        fragments: [{'type': 'REQUEST', 'content': 'q'}],
      );
      final reply = messageJson(
        id: 2,
        parentId: 1,
        role: 'ASSISTANT',
        fragments: [
          {'type': 'THINK', 'content': 'plan', 'elapsed_secs': 2.5},
          {'type': 'RESPONSE', 'content': 'a'},
        ],
      );
      final bytes = zipOf([
        ('manifest.json', manifestJson(3)),
        ('user.json', {'id': 'account'}),
        ('chat_sessions/session-1.json', sessionJson(
          currentMessageId: 2,
          messages: [user, reply],
        )),
        ('chat_session_index.json', indexJson(['session-1'])),
      ]);

      final decoded = decodeHistoryZip(bytes, newId: () => 'id');

      final blocks = (decoded.sessions.single.messages.last
              as AssistantMessage)
          .blocks;
      expect((blocks.first as ThinkingBlock).elapsedSeconds, 3);
    });

    test('maps every archive reply status to the local status', () {
      final messages = [
        messageJson(id: 1, fragments: [{'type': 'REQUEST', 'content': 'q'}]),
        for (final (index, status) in const [
          (2, 'WIP'),
          (3, 'INCOMPLETE'),
          (4, 'CONTEXT_LENGTH_EXCEEDED'),
          (5, 'TIMEOUT'),
        ])
          messageJson(
            id: index,
            parentId: 1,
            role: 'ASSISTANT',
            status: status,
            fragments: [{'type': 'RESPONSE', 'content': status}],
          ),
      ];

      final decoded = decodeHistoryZip(
        zipOf([
          ('manifest.json', manifestJson(3)),
          ('chat_sessions/session-1.json', sessionJson(
            currentMessageId: 5,
            messages: messages,
          )),
          ('chat_session_index.json', indexJson(['session-1'])),
        ]),
        newId: () => 'id',
      );

      final replies = decoded.sessions.single.messages
          .whereType<AssistantMessage>()
          .toList();
      expect(replies.map((reply) => reply.status), [
        ReplyStatus.stopped,
        ReplyStatus.stopped,
        ReplyStatus.error,
        ReplyStatus.error,
      ]);
      expect(replies.every((reply) => !reply.prefix), isTrue);
    });

    test('a refused reply keeps its tool blocks', () {
      final user = messageJson(
        id: 1,
        fragments: [{'type': 'REQUEST', 'content': 'q'}],
      );
      final reply = messageJson(
        id: 2,
        parentId: 1,
        role: 'ASSISTANT',
        status: 'CONTENT_FILTER',
        fragments: [
          {'type': 'THINK', 'content': 'secret', 'elapsed_secs': 1},
          {'type': 'RESPONSE', 'content': 'hidden'},
          {
            'type': 'TOOL_SEARCH',
            'queries': ['q'],
            'status': 'FINISHED',
            'results': [],
          },
          {'type': 'TEMPLATE_RESPONSE', 'content': 'refused'},
        ],
      );

      final decoded = decodeHistoryZip(
        zipOf([
          ('manifest.json', manifestJson(3)),
          ('chat_sessions/session-1.json', sessionJson(
            currentMessageId: 2,
            messages: [user, reply],
          )),
          ('chat_session_index.json', indexJson(['session-1'])),
        ]),
        newId: () => 'id',
      );

      final blocks = (decoded.sessions.single.messages.last
              as AssistantMessage)
          .blocks;
      expect(blocks.whereType<ServerToolUseBlock>(), hasLength(1));
      expect(blocks.whereType<WebSearchToolResultBlock>(), hasLength(1));
      expect(blocks.whereType<ThinkingBlock>(), isEmpty);
      expect(
        blocks.whereType<TextBlock>().map((block) => block.text),
        ['refused'],
      );
    });

    test('rejects invalid JSON, unsafe attachment ids and missing metadata',
        () {
      expect(
        () => decodeHistoryZip(
          zipOfBytes([
            (
              'manifest.json',
              utf8.encode('{"export_format_version":3}'),
            ),
            ('chat_sessions/session-1.json', utf8.encode('{bad')),
          ]),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidJson),
      );

      final unsafeFile = messageJson(
        id: 1,
        fragments: [
          {
            'type': 'FILE',
            'files': [
              {
                'id': '../evil',
                'file_name': 'x.txt',
                'file_size': 1,
                'token_usage': null,
                'inserted_at': '2026-01-02T03:04:05.000Z',
                'export_path': null,
                'is_image': false,
                'width': null,
                'height': null,
              },
            ],
          },
          {'type': 'REQUEST', 'content': 'q'},
        ],
      );
      expect(
        () => decodeHistoryZip(
          validZip(messages: [unsafeFile], currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidFiles),
      );

      final missingUsage = messageJson(
        id: 1,
        fragments: [{'type': 'REQUEST', 'content': 'q'}],
      )..remove('accumulated_token_usage');
      expect(
        () => decodeHistoryZip(
          validZip(messages: [missingUsage], currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.incomplete),
      );
    });

    test('rejects oversized and encrypted entries before decoding them', () {
      expect(
        () => decodeHistoryZip(
          declaredZip(
            name: 'chat_sessions/session-1_files/img.png',
            uncompressedSize: 64 * 1024 * 1024 + 1,
          ),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.tooLarge),
      );
      expect(
        () => decodeHistoryZip(
          declaredZip(name: 'manifest.json', uncompressedSize: 10, flags: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.unrecognized),
      );
    });

    test('sniffs MIME types and tolerates a short RIFF header', () {
      final user = UserMessage(
        id: 'message-1',
        createdAt: at(5),
        text: 'Look',
        selectedChildId: 'message-2',
        attachments: const [
          Attachment(id: 'jpeg', name: 'a.jpg', size: 3, isImage: true),
          Attachment(id: 'short', name: 'b.webp', size: 4, isImage: true),
        ],
      );
      final reply = AssistantMessage(
        id: 'message-2',
        parentId: 'message-1',
        createdAt: at(6),
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: 'ok')],
      );
      final bytes = encodeHistoryZip(
        [
          SessionHistory(
            session: sessionWith(),
            messages: [user, reply],
          ),
        ],
        imageBytes: {
          'jpeg': Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
          'short': Uint8List.fromList(utf8.encode('RIFF')),
        },
        notice: (_) => null,
      );

      final decoded = decodeHistoryZip(bytes, newId: () => 'id');

      expect(decoded.images['jpeg']?.mimeType, 'image/jpeg');
      expect(decoded.images['short']?.mimeType, '');
    });

    test('rejects image paths outside the session directory', () {
      final user = messageJson(
        id: 1,
        fragments: [
          {
            'type': 'FILE',
            'files': [
              {
                'id': 'img-1',
                'file_name': 'photo.png',
                'file_size': 1,
                'token_usage': null,
                'inserted_at': '2026-01-02T03:04:05.000Z',
                'export_path': 'chat_sessions/other_files/img-1_photo.png',
                'is_image': true,
                'width': null,
                'height': null,
              },
            ],
          },
          {'type': 'REQUEST', 'content': 'a'},
        ],
      );

      expect(
        () => decodeHistoryZip(
          validZip(messages: [user], currentMessageId: 1),
          newId: () => 'id',
        ),
        throwsHistory(HistoryError.invalidFiles),
      );
    });
  });
}
