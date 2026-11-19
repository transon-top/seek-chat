import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../models/json.dart';
import '../models/types.dart';
import 'database.dart';

/// 会话、消息、分支与附件的持久化（`data-model.md`）。
///
/// 流式回复只在内存中合并，仅在状态迁移时落盘；本类在流式期间不写库。
class ChatRepository {
  ChatRepository(this._db, {String Function()? newId, int Function()? clock})
      : _newId = newId ?? (() => const Uuid().v4()),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final String Function() _newId;
  final int Function() _clock;

  // ---------------------------------------------------------------- 会话

  Future<List<SessionSummary>> listSessions() async =>
      _toSummaries(await _sessionsQuery().get());

  /// 会话列表的响应式来源；drift 在会话增删改后推送新列表。
  Stream<List<SessionSummary>> watchSessions() =>
      _sessionsQuery().watch().map(_toSummaries);

  /// 历史列表只含已有消息的会话；新建的草稿会话（尚未发出消息）不展示
  /// （chat-demo 同款）。消息写入后 drift 会重新推送同一查询。
  Selectable<SessionRow> _sessionsQuery() => _db.select(_db.sessions)
    ..where(
      (t) => existsQuery(
        _db.selectOnly(_db.messages)
          ..addColumns([_db.messages.id])
          ..where(_db.messages.sessionId.equalsExp(t.id)),
      ),
    )
    ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);

  Future<Session?> getSession(String id) async {
    final row = await (_db.select(_db.sessions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toSession(row);
  }

  Future<Session> createSession() async {
    final now = _clock();
    final id = _newId();
    await _db.into(_db.sessions).insert(SessionsCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
        ));
    return Session(id: id, title: '', createdAt: _date(now), updatedAt: _date(now));
  }

  /// 重命名不算活动：会话在列表中的位置不变。
  Future<void> renameSession(String sessionId, String title) async {
    await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
        .write(SessionsCompanion(title: Value(title)));
  }

  /// 删除会话及其全部消息，再清理本会话引用过、且不再被引用的附件行。
  /// 返回被移除的附件，供调用方在事务提交后删除本地文件。
  Future<List<Attachment>> deleteSession(String sessionId) async {
    var orphans = const <Attachment>[];
    await _db.transaction(() async {
      // Q7：先取出本会话引用过的附件，删除范围不波及其他会话的孤儿行。
      final candidateIds = await _attachmentIdsForSession(sessionId);
      await (_db.delete(_db.sessions)..where((t) => t.id.equals(sessionId)))
          .go();
      if (candidateIds.isEmpty) return;

      final rows = await (_db.select(_db.attachments)
            ..where((t) => t.id.isIn(candidateIds)))
          .get();
      final remainingLinks = await (_db.select(_db.messageAttachments)
            ..where((t) => t.attachmentId.isIn(candidateIds)))
          .get();
      final referenced = {
        for (final link in remainingLinks) link.attachmentId,
      };
      final orphanRows = [
        for (final row in rows)
          if (!referenced.contains(row.id)) row,
      ];
      if (orphanRows.isNotEmpty) {
        await (_db.delete(_db.attachments)
              ..where((t) => t.id.isIn(orphanRows.map((row) => row.id).toList())))
            .go();
      }
      orphans = [for (final row in orphanRows) _toAttachment(row)];
    });
    return orphans;
  }

  // ---------------------------------------------------------------- 消息

  /// 会话的全部消息，含所有分支，按模型规定的顺序排列。
  Future<List<Message>> loadMessages(String sessionId) async {
    final rows = await (_db.select(_db.messages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    return _enrich(rows);
  }

  /// 打开会话时的读取：残留的 `pending`/`streaming` 回复在返回结果中按
  /// `stopped` 处理并收尾思考块，不写库。
  Future<List<Message>> loadMessagesForDisplay(String sessionId) async {
    final session = await getSession(sessionId);
    final messages = await loadMessages(sessionId);
    if (session == null) return messages;
    return [
      for (final message in messages)
        _settleInterrupted(message, session.updatedAt),
    ];
  }

  /// 选中分支：从 `rootMessageId` 沿每行 `selected_child_id` 走出的路径。
  Future<List<Message>> visiblePath(String sessionId) async =>
      (await loadConversation(sessionId)).messages;

  /// 选中分支与每条消息的兄弟版本；聊天页一次读取即可渲染路径和切换器。
  ///
  /// [settleInterrupted] 为真时，残留的 `pending`/`streaming` 回复在返回结果
  /// 中按 `stopped` 显示（不写库），供打开会话时使用。
  Future<({List<Message> messages, Map<String, MessageVersions> versions})>
  loadConversation(
    String sessionId, {
    bool settleInterrupted = false,
  }) async {
    final ids = await _visibleIds(sessionId);
    final messages = settleInterrupted
        ? await loadMessagesForDisplay(sessionId)
        : await loadMessages(sessionId);
    final byId = {for (final message in messages) message.id: message};
    final groups = <String?, List<String>>{};
    for (final message in messages) {
      (groups[message.parentId] ??= []).add(message.id);
    }
    return (
      messages: [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ],
      versions: {
        for (final group in groups.values)
          for (var index = 0; index < group.length; index++)
            group[index]: MessageVersions(
              ids: List<String>.unmodifiable(group),
              index: index,
            ),
      },
    );
  }

  /// [parentId] 下的兄弟版本；parentId 为 null 时返回根版本。
  Future<List<Message>> siblings(String sessionId, String? parentId) async {
    final rows = await (_db.select(_db.messages)
          ..where((t) =>
              t.sessionId.equals(sessionId) &
              t.parentId.equalsNullable(parentId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    return _enrich(rows);
  }

  /// 把提问追加到选中分支末尾并选中它。
  Future<UserMessage> addUserMessage({
    required String sessionId,
    required String text,
    List<Attachment> attachments = const [],
  }) async {
    final id = _newId();
    String? parentId;
    late UserMessage message;

    await _db.transaction(() async {
      parentId = await _visibleLeafId(sessionId);
      final createdAt = await _nextTimestamp(
        sessionId,
        parentId,
        parentCreatedAt: parentId == null ? null : await _createdAt(parentId!),
      );

      await _db.into(_db.messages).insert(MessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            parentId: Value(parentId),
            role: 'user',
            createdAt: createdAt,
            textContent: Value(text),
          ));
      await _writeAttachments(id, attachments);

      if (parentId == null) {
        await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
            .write(SessionsCompanion(rootMessageId: Value(id)));
      } else {
        await _selectChild(parentId!, id);
      }
      await _touchSession(sessionId, createdAt);

      message = UserMessage(
        id: id,
        parentId: parentId,
        createdAt: _date(createdAt),
        text: text,
        attachments: attachments,
      );
    });

    return message;
  }

  /// 在 [userMessageId] 下创建 `pending` 回复并选中。
  ///
  /// 重新生成是同一操作：旧回复及其子树保持不变。
  Future<AssistantMessage> createReply({
    required String sessionId,
    required String userMessageId,
    required ChatModel model,
    required bool thinking,
    required bool search,
    String? latestReminder,
    bool prefix = true,
  }) async {
    final id = _newId();
    late AssistantMessage message;

    await _db.transaction(() async {
      final createdAt = await _nextTimestamp(
        sessionId,
        userMessageId,
        parentCreatedAt: await _createdAt(userMessageId),
      );

      await _db.into(_db.messages).insert(MessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            parentId: Value(userMessageId),
            role: 'assistant',
            createdAt: createdAt,
            model: Value(model.wire),
            thinking: Value(thinking),
            search: Value(search),
            latestReminder: Value(latestReminder),
            prefix: Value(prefix),
            status: const Value('pending'),
            blocks: const Value('[]'),
          ));
      await _selectChild(userMessageId, id);
      await _touchSession(sessionId, createdAt);

      message = AssistantMessage(
        id: id,
        parentId: userMessageId,
        createdAt: _date(createdAt),
        status: ReplyStatus.pending,
        blocks: const [],
        model: model,
        thinking: thinking,
        search: search,
        latestReminder: latestReminder,
        prefix: prefix,
      );
    });

    return message;
  }

  /// 在终态迁移（`done`、`stopped`、`error`）写入回复状态。可空列直接替换，
  /// 不与旧值合并。
  Future<void> updateReply({
    required String messageId,
    required ReplyStatus status,
    required List<ReplyBlock> blocks,
    StopReason? stopReason,
    StopDetails? stopDetails,
    Usage? usage,
    ReplyError? error,
    bool? prefix,
  }) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(
      blocks: Value(encodeReplyBlocks(blocks)),
      status: Value(status.name),
      stopReason: Value(stopReason?.wire),
      stopDetails: Value(
        stopDetails == null ? null : jsonEncode(encodeStopDetails(stopDetails)),
      ),
      usage: Value(usage == null ? null : jsonEncode(encodeUsage(usage))),
      error: Value(error == null ? null : encodeReplyError(error)),
      prefix: prefix == null ? const Value.absent() : Value(prefix),
    ));
  }

  /// 请求发出前写入本轮系统信息快照，时机为附件补齐之后。
  Future<void> setLatestReminder(String messageId, String latestReminder) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(latestReminder: Value(latestReminder)));
  }

  /// 续写复用同一条 assistant 行及其请求快照。
  Future<void> beginContinuation(String messageId) async {
    await _db.transaction(() async {
      final row = await _messageRow(messageId);
      if (row == null) return;
      await (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
          .write(const MessagesCompanion(
        status: Value('pending'),
        stopReason: Value<String?>(null),
        stopDetails: Value<String?>(null),
        error: Value<String?>(null),
      ));
      await _touchSession(row.sessionId, _clock());
    });
  }

  /// 在原提问的父节点下新建 user 版本，复制其附件引用，并插入新的
  /// pending 回复。
  Future<(UserMessage, AssistantMessage)> editUserMessage({
    required String sessionId,
    required String originalMessageId,
    required String text,
    required ChatModel model,
    required bool thinking,
    required bool search,
    String? latestReminder,
  }) async {
    late UserMessage user;
    late AssistantMessage reply;

    await _db.transaction(() async {
      final original = await _messageRow(originalMessageId);
      if (original == null) {
        throw StateError('message $originalMessageId not found');
      }
      final parentId = original.parentId;
      final createdAt = await _nextTimestamp(
        sessionId,
        parentId,
        parentCreatedAt: parentId == null ? null : await _createdAt(parentId),
      );

      final links = await (_db.select(_db.messageAttachments)
            ..where((t) => t.messageId.equals(originalMessageId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();
      final attachments = await _attachmentsByIds(
        links.map((link) => link.attachmentId).toList(),
      );

      final userId = _newId();
      await _db.into(_db.messages).insert(MessagesCompanion.insert(
            id: userId,
            sessionId: sessionId,
            parentId: Value(parentId),
            role: 'user',
            createdAt: createdAt,
            textContent: Value(text),
          ));
      for (final link in links) {
        await _db.into(_db.messageAttachments).insert(
              MessageAttachmentsCompanion.insert(
                messageId: userId,
                attachmentId: link.attachmentId,
                position: link.position,
              ),
            );
      }
      if (parentId == null) {
        await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
            .write(SessionsCompanion(rootMessageId: Value(userId)));
      } else {
        await _selectChild(parentId, userId);
      }

      final replyId = _newId();
      final replyCreatedAt = createdAt + 1;
      await _db.into(_db.messages).insert(MessagesCompanion.insert(
            id: replyId,
            sessionId: sessionId,
            parentId: Value(userId),
            role: 'assistant',
            createdAt: replyCreatedAt,
            model: Value(model.wire),
            thinking: Value(thinking),
            search: Value(search),
            latestReminder: Value(latestReminder),
            prefix: const Value(true),
            status: const Value('pending'),
            blocks: const Value('[]'),
          ));
      await _selectChild(userId, replyId);
      await _touchSession(sessionId, replyCreatedAt);

      user = UserMessage(
        id: userId,
        parentId: parentId,
        createdAt: _date(createdAt),
        text: text,
        attachments: attachments,
      );
      reply = AssistantMessage(
        id: replyId,
        parentId: userId,
        createdAt: _date(replyCreatedAt),
        status: ReplyStatus.pending,
        blocks: const [],
        model: model,
        thinking: thinking,
        search: search,
        latestReminder: latestReminder,
      );
    });

    return (user, reply);
  }

  /// 在兄弟版本中选中 [messageId]，不写 `updated_at`。
  Future<void> selectVersion({
    required String sessionId,
    required String messageId,
  }) async {
    final row = await _messageRow(messageId);
    if (row == null) return;
    await _db.transaction(() async {
      final parentId = row.parentId;
      if (parentId == null) {
        await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
            .write(SessionsCompanion(rootMessageId: Value(messageId)));
      } else {
        await _selectChild(parentId, messageId);
      }
    });
  }

  /// 启动兜底：残留的 `pending`/`streaming` 回复置为 `stopped`。返回受影响
  /// 的行数。
  Future<int> resetInterruptedReplies() {
    return (_db.update(_db.messages)
          ..where((t) => t.status.isIn(['pending', 'streaming'])))
        .write(const MessagesCompanion(status: Value('stopped')));
  }

  // ------------------------------------------------------------- 导入导出

  /// 删除全部会话、消息与附件；返回被移除的附件供调用方清理本地原件。
  Future<List<Attachment>> deleteAllHistory() async {
    var previous = const <Attachment>[];
    await _db.transaction(() async {
      final oldRows = await _db.select(_db.attachments).get();
      previous = [for (final row in oldRows) _toAttachment(row)];
      await _db.delete(_db.messageAttachments).go();
      await _db.delete(_db.messages).go();
      await _db.delete(_db.sessions).go();
      await _db.delete(_db.attachments).go();
    });
    return previous;
  }

  /// 用归档内容整体替换全部会话、消息与附件（`history.md` §5）。
  ///
  /// 单事务完成：失败时旧数据保留。返回被移除的附件，供调用方在事务提交后
  /// 删除本地原件。
  Future<List<Attachment>> replaceAllHistory(
    List<SessionHistory> history,
  ) async {
    var previous = const <Attachment>[];
    await _db.transaction(() async {
      final oldRows = await _db.select(_db.attachments).get();
      previous = [for (final row in oldRows) _toAttachment(row)];

      await _db.delete(_db.messageAttachments).go();
      await _db.delete(_db.messages).go();
      await _db.delete(_db.sessions).go();
      await _db.delete(_db.attachments).go();

      final seen = <String>{};
      for (final tree in history) {
        final session = tree.session;
        await _db.into(_db.sessions).insert(SessionsCompanion.insert(
              id: session.id,
              title: Value(session.title),
              createdAt: session.createdAt.millisecondsSinceEpoch,
              updatedAt: session.updatedAt.millisecondsSinceEpoch,
              rootMessageId: Value(session.rootMessageId),
            ));

        for (final message in tree.messages) {
          switch (message) {
            case UserMessage():
              await _db.into(_db.messages).insert(MessagesCompanion.insert(
                    id: message.id,
                    sessionId: session.id,
                    parentId: Value(message.parentId),
                    selectedChildId: Value(message.selectedChildId),
                    role: 'user',
                    createdAt: message.createdAt.millisecondsSinceEpoch,
                    textContent: Value(message.text),
                  ));
            case AssistantMessage():
              await _db.into(_db.messages).insert(MessagesCompanion.insert(
                    id: message.id,
                    sessionId: session.id,
                    parentId: Value(message.parentId),
                    selectedChildId: Value(message.selectedChildId),
                    role: 'assistant',
                    createdAt: message.createdAt.millisecondsSinceEpoch,
                    model: Value(message.model?.wire),
                    thinking: Value(message.thinking),
                    search: Value(message.search),
                    latestReminder: Value(message.latestReminder),
                    prefix: Value(message.prefix),
                    status: Value(message.status.name),
                    stopReason: Value(message.stopReason?.wire),
                    blocks: Value(encodeReplyBlocks(message.blocks)),
                    stopDetails: Value(
                      message.stopDetails == null
                          ? null
                          : jsonEncode(encodeStopDetails(message.stopDetails!)),
                    ),
                    usage: Value(
                      message.usage == null
                          ? null
                          : jsonEncode(encodeUsage(message.usage!)),
                    ),
                    error: Value(
                      message.error == null
                          ? null
                          : encodeReplyError(message.error!),
                    ),
                  ));
          }
        }
      }

      for (final tree in history) {
        for (final message in tree.messages.whereType<UserMessage>()) {
          for (var position = 0;
              position < message.attachments.length;
              position++) {
            final attachment = message.attachments[position];
            if (seen.add(attachment.id)) {
              await _db.into(_db.attachments).insert(
                    AttachmentsCompanion.insert(
                      id: attachment.id,
                      name: attachment.name,
                      size: attachment.size,
                      isImage: Value(attachment.isImage),
                      mimeType: Value(attachment.mimeType),
                      localPath: Value(attachment.localPath),
                      serverId: Value(attachment.serverId),
                    ),
                  );
            }
            await _db.into(_db.messageAttachments).insert(
                  MessageAttachmentsCompanion.insert(
                    messageId: message.id,
                    attachmentId: attachment.id,
                    position: position,
                  ),
                );
          }
        }
      }
    });
    return previous;
  }

  // ------------------------------------------------------------- 附件

  /// `server_id` 由引用同一附件的所有消息共享。
  Future<void> setAttachmentServerId(String attachmentId, String? serverId) async {
    await (_db.update(_db.attachments)
          ..where((t) => t.id.equals(attachmentId)))
        .write(AttachmentsCompanion(serverId: Value(serverId)));
  }

  /// 数据库登记的全部原件相对路径，供启动时清理没有数据库记录的文件。
  Future<Set<String>> attachmentLocalPaths() async {
    final rows = await _db.select(_db.attachments).get();
    return {
      for (final row in rows)
        if (row.localPath != null && row.localPath!.isNotEmpty) row.localPath!,
    };
  }

  // ------------------------------------------------------------------ 私有

  Future<void> _writeAttachments(
    String messageId,
    List<Attachment> attachments,
  ) async {
    for (var position = 0; position < attachments.length; position++) {
      final attachment = attachments[position];
      await _db.into(_db.attachments).insert(
            AttachmentsCompanion.insert(
              id: attachment.id,
              name: attachment.name,
              size: attachment.size,
              isImage: Value(attachment.isImage),
              mimeType: Value(attachment.mimeType),
              localPath: Value(attachment.localPath),
              serverId: Value(attachment.serverId),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await _db.into(_db.messageAttachments).insert(
            MessageAttachmentsCompanion.insert(
              messageId: messageId,
              attachmentId: attachment.id,
              position: position,
            ),
          );
    }
  }

  Future<List<Attachment>> _attachmentsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(_db.attachments)
          ..where((t) => t.id.isIn(ids)))
        .get();
    return [for (final row in rows) _toAttachment(row)];
  }

  Future<List<Message>> _enrich(List<MessageRow> rows) async {
    if (rows.isEmpty) return const [];
    final links = await (_db.select(_db.messageAttachments)
          ..where((t) => t.messageId.isIn(rows.map((row) => row.id).toList()))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final attachments = await _attachmentsByIds(
      links.map((link) => link.attachmentId).toSet().toList(),
    );
    final byId = {for (final attachment in attachments) attachment.id: attachment};
    final byMessage = <String, List<Attachment>>{};
    for (final link in links) {
      final attachment = byId[link.attachmentId];
      if (attachment == null) continue;
      (byMessage[link.messageId] ??= []).add(attachment);
    }
    return [
      for (final row in rows) _toMessage(row, byMessage[row.id] ?? const []),
    ];
  }

  Message _toMessage(MessageRow row, List<Attachment> attachments) {
    if (row.role == 'user') {
      return UserMessage(
        id: row.id,
        parentId: row.parentId,
        selectedChildId: row.selectedChildId,
        createdAt: _date(row.createdAt),
        text: row.textContent ?? '',
        attachments: attachments,
      );
    }
    return AssistantMessage(
      id: row.id,
      parentId: row.parentId,
      selectedChildId: row.selectedChildId,
      createdAt: _date(row.createdAt),
      model: ChatModel.fromWire(row.model),
      thinking: row.thinking,
      search: row.search,
      latestReminder: row.latestReminder,
      prefix: row.prefix ?? true,
      status: _replyStatus(row.status),
      blocks: decodeReplyBlocks(row.blocks),
      stopReason: StopReason.fromWire(row.stopReason),
      stopDetails: parseStopDetails(decodeJsonSource(row.stopDetails)),
      usage: parseUsage(decodeJsonSource(row.usage)),
      error: parseReplyError(row.error),
    );
  }

  List<SessionSummary> _toSummaries(List<SessionRow> rows) => [
        for (final row in rows)
          SessionSummary(
            id: row.id,
            title: row.title,
            createdAt: _date(row.createdAt),
            updatedAt: _date(row.updatedAt),
          ),
      ];

  Session _toSession(SessionRow row) => Session(
        id: row.id,
        title: row.title,
        createdAt: _date(row.createdAt),
        updatedAt: _date(row.updatedAt),
        rootMessageId: row.rootMessageId,
      );

  Attachment _toAttachment(AttachmentRow row) => Attachment(
        id: row.id,
        name: row.name,
        size: row.size,
        isImage: row.isImage,
        mimeType: row.mimeType,
        localPath: row.localPath,
        serverId: row.serverId,
      );

  Future<MessageRow?> _messageRow(String id) async =>
      (_db.select(_db.messages)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> _createdAt(String messageId) async {
    final row = await _messageRow(messageId);
    if (row == null) {
      throw StateError('message $messageId not found');
    }
    return row.createdAt;
  }

  /// 保证 `ORDER BY created_at` 与父子顺序、版本顺序一致。
  Future<int> _nextTimestamp(
    String sessionId,
    String? parentId, {
    int? parentCreatedAt,
  }) async {
    var next = _clock();
    if (parentCreatedAt != null && next <= parentCreatedAt) {
      next = parentCreatedAt + 1;
    }
    final lastSibling = await (_db.select(_db.messages)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.parentId.equalsNullable(parentId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (lastSibling != null && next <= lastSibling.createdAt) {
      next = lastSibling.createdAt + 1;
    }
    return next;
  }

  Future<void> _selectChild(String parentId, String childId) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(parentId)))
        .write(MessagesCompanion(selectedChildId: Value(childId)));
  }

  Future<void> _touchSession(String sessionId, int updatedAt) async {
    await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
        .write(SessionsCompanion(updatedAt: Value(updatedAt)));
  }

  Future<String?> _visibleLeafId(String sessionId) async {
    final ids = await _visibleIds(sessionId);
    return ids.isEmpty ? null : ids.last;
  }

  Future<List<String>> _visibleIds(String sessionId) async {
    final rows = await _db.customSelect(
      '''
      WITH RECURSIVE path(id, depth) AS (
        SELECT root_message_id, 0 FROM sessions
         WHERE id = ? AND root_message_id IS NOT NULL
        UNION ALL
        SELECT m.selected_child_id, p.depth + 1
          FROM messages m JOIN path p ON m.id = p.id
         WHERE m.selected_child_id IS NOT NULL
      )
      SELECT m.id AS id FROM path p JOIN messages m ON m.id = p.id
       ORDER BY p.depth
      ''',
      variables: [Variable.withString(sessionId)],
      readsFrom: {_db.sessions, _db.messages},
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  Future<List<String>> _attachmentIdsForSession(String sessionId) async {
    final rows = await _db.customSelect(
      '''
      SELECT DISTINCT ma.attachment_id AS id
        FROM message_attachments ma
        JOIN messages m ON m.id = ma.message_id
       WHERE m.session_id = ?
      ''',
      variables: [Variable.withString(sessionId)],
      readsFrom: {_db.messageAttachments, _db.messages},
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// 打开会话时把残留的生成状态视为已停止，并给未结束的思考块补结束时间。
  Message _settleInterrupted(Message message, DateTime at) {
    if (message is! AssistantMessage || !message.isInFlight) {
      return message;
    }
    final endedAt = at.millisecondsSinceEpoch;
    return AssistantMessage(
      id: message.id,
      parentId: message.parentId,
      selectedChildId: message.selectedChildId,
      createdAt: message.createdAt,
      status: ReplyStatus.stopped,
      blocks: [
        for (final block in message.blocks)
          block is ThinkingBlock &&
                  block.startedAt != null &&
                  block.endedAt == null
              ? block.copyWith(endedAt: endedAt)
              : block,
      ],
      model: message.model,
      thinking: message.thinking,
      search: message.search,
      latestReminder: message.latestReminder,
      prefix: message.prefix,
      stopReason: message.stopReason,
      stopDetails: message.stopDetails,
      usage: message.usage,
      error: message.error,
    );
  }

  DateTime _date(int epochMillis) =>
      DateTime.fromMillisecondsSinceEpoch(epochMillis);

  ReplyStatus _replyStatus(String? wire) {
    for (final status in ReplyStatus.values) {
      if (status.name == wire) return status;
    }
    return ReplyStatus.error;
  }
}
