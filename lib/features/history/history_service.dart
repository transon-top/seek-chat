import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../shared/data/attachment_store.dart';
import '../../shared/data/chat_repository.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import 'history_zip.dart';

/// ZH
/// 历史导入导出服务：文件选择由界面负责，这里只处理数据与事务。
///
/// EN
/// History import/export service: the UI picks files; this handles data and transactions only.
final historyServiceProvider = Provider<HistoryService>(
  (ref) => HistoryService(
    ref.watch(chatRepositoryProvider),
    ref.watch(attachmentStoreProvider),
  ),
);

final class HistoryService {
  HistoryService(
    this._repository,
    this._attachments, {
    String Function()? newId,
    DateTime Function()? now,
  })  : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final ChatRepository _repository;
  final AttachmentStore _attachments;
  final String Function() _newId;
  final DateTime Function() _now;

  /// ZH
  /// 读取全部会话并生成 ZIP。导出使用开始时的列表快照；会话在读取中消失
  /// 时整次失败（`history.md` §6）。
  ///
  /// EN
  /// Read all sessions and build a ZIP. Export uses the list snapshot from the start;
  /// a session disappearing during the read fails the whole export (`history.md` §6).
  Future<({String fileName, Uint8List bytes})> exportArchive({
    required String? Function(AssistantMessage reply) notice,
  }) async {
    final summaries = await _repository.listSessions(includeEmpty: true);
    final history = <SessionHistory>[];
    final imageBytes = <String, Uint8List>{};

    for (final summary in summaries) {
      final session = await _repository.getSession(summary.id);
      if (session == null) {
        throw StateError('history session disappeared: ${summary.id}');
      }
      final messages = await _repository.loadMessagesForDisplay(summary.id);
      for (final message in messages.whereType<UserMessage>()) {
        for (final attachment in message.attachments) {
          if (!attachment.isImage ||
              attachment.localPath == null ||
              imageBytes.containsKey(attachment.id)) {
            continue;
          }
          final bytes = await _attachments.readBytes(attachment.localPath);
          if (bytes == null) continue;
          if (bytes.length > historyImageEntryLimitBytes) {
            historyFail(HistoryError.tooLarge);
          }
          imageBytes[attachment.id] = bytes;
        }
      }
      history.add(SessionHistory(
        session: Session(
          id: session.id,
          title: summary.title,
          createdAt: session.createdAt,
          updatedAt: session.updatedAt,
          rootMessageId: session.rootMessageId,
          pinned: session.pinned,
        ),
        messages: messages,
      ));
    }

    final bytes = encodeHistoryZip(
      history,
      imageBytes: imageBytes,
      notice: notice,
    );
    return (fileName: _fileName(_now()), bytes: bytes);
  }

  /// ZH
  /// 覆盖导入。解码与校验全部通过后才停止生成并写文件；数据库替换在单事务
  /// 中完成（`history.md` §5）。返回导入的会话数。
  ///
  /// EN
  /// Destructive import. Stop generation and write files only after decode and validation pass;
  /// the database swaps in a single transaction (`history.md` §5). Returns the session count.
  Future<int> importArchive(
    Uint8List bytes, {
    required void Function() stopGeneration,
  }) async {
    final decoded = decodeHistoryZip(bytes, newId: _newId);
    stopGeneration();

    // ZH
    // 附件改用新的本地 id：旧原件不会被覆盖，归档 id 也不能决定写入路径。
    //
    // EN
    // Attachments get new local ids: no old original is overwritten, archive ids never pick paths.
    final attachmentIds = <String, String>{};
    for (final tree in decoded.sessions) {
      for (final message in tree.messages.whereType<UserMessage>()) {
        for (final attachment in message.attachments) {
          attachmentIds.putIfAbsent(attachment.id, _newId);
        }
      }
    }

    final paths = <String, String>{};
    for (final entry in decoded.images.entries) {
      final localId = attachmentIds[entry.key];
      if (localId == null) continue;
      paths[localId] = await _attachments.saveBytes(
        localId,
        entry.value.bytes,
      );
    }

    final history = [
      for (final tree in decoded.sessions)
        SessionHistory(
          session: tree.session,
          messages: _rewriteAttachments(tree.messages, attachmentIds, paths),
        ),
    ];
    final keptPaths = {
      for (final tree in history)
        for (final message in tree.messages.whereType<UserMessage>())
          for (final attachment in message.attachments)
            if (attachment.localPath != null) attachment.localPath!,
    };
    final removed = await _repository.replaceAllHistory(history);
    await _attachments.deleteAttachments([
      for (final attachment in removed)
        if (attachment.localPath == null ||
            !keptPaths.contains(attachment.localPath))
          attachment,
    ]);
    return history.length;
  }

  /// ZH
  /// 删除全部会话与附件；返回删除的会话数。
  ///
  /// EN
  /// Delete all sessions and attachments; returns the number of deleted sessions.
  Future<int> deleteAll({required void Function() stopGeneration}) async {
    stopGeneration();
    final count =
        (await _repository.listSessions(includeEmpty: true)).length;
    final removed = await _repository.deleteAllHistory();
    await _attachments.deleteAttachments(removed);
    return count;
  }

  List<Message> _rewriteAttachments(
    List<Message> messages,
    Map<String, String> ids,
    Map<String, String> paths,
  ) =>
      [
        for (final message in messages)
          if (message is UserMessage)
            message.withAttachments([
              for (final attachment in message.attachments)
                Attachment(
                  id: ids[attachment.id] ?? attachment.id,
                  name: attachment.name,
                  size: attachment.size,
                  isImage: attachment.isImage,
                  mimeType: attachment.mimeType,
                  localPath: paths[ids[attachment.id]],
                ),
            ])
          else
            message,
      ];

  String _fileName(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'deepseek_data-${date.year}-${two(date.month)}-${two(date.day)}.zip';
  }
}
