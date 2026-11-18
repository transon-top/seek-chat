import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/types.dart';
import 'chat_repository.dart';

/// 附件原件的文件层：删除与启动孤儿清理（`data-model.md` §5）。
///
/// 原件按附件 id 存放在 `<应用支持目录>/attachments/<id>`，数据库只存相对
/// 路径。写入顺序是先写文件再写库，因此数据库失败会留下孤儿文件。
class AttachmentStore {
  AttachmentStore({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  static const String directoryName = 'attachments';

  /// 删除已从数据库移除的附件原件；文件缺失时忽略。
  Future<void> deleteAttachments(Iterable<Attachment> attachments) async {
    final root = await _supportDirectory();
    for (final attachment in attachments) {
      final relative = attachment.localPath;
      if (relative == null || relative.isEmpty) continue;
      await _delete(File(p.join(root.path, relative)));
    }
  }

  /// 删除附件目录中没有数据库记录的文件；失败不阻塞启动。
  Future<void> cleanupOrphans(ChatRepository repository) async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    if (!await directory.exists()) return;

    final known = await repository.attachmentLocalPaths();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final relative = '$directoryName/${p.basename(entity.path)}';
      if (known.contains(relative)) continue;
      await _delete(entity);
    }
  }

  Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // 文件已缺失或不可删除时保持数据现状，下次启动再试。
    }
  }
}
