import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/types.dart';
import 'chat_repository.dart';

/// ZH
/// 附件原件的文件层：删除与启动孤儿清理（`data-model.md` §5）。
///
/// 原件按附件 id 存放在 `<应用支持目录>/attachments/<id>`，数据库只存相对
/// 路径。写入顺序是先写文件再写库，因此数据库失败会留下孤儿文件。
///
/// EN
/// File layer for attachment originals: deletion and startup orphan cleanup (`data-model.md` §5).
///
/// Originals live at `<app support dir>/attachments/<id>` keyed by attachment id. The
/// database stores relative paths only. Files go first, so a DB failure leaves an orphan.
class AttachmentStore {
  AttachmentStore({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  static const String directoryName = 'attachments';

  /// ZH
  /// 把选择器给出的原件复制到 `attachments/<id>`，返回数据库要存的相对路径。
  /// 发送时调用：先写文件，再提交数据库行（`data-model.md` §5）。
  ///
  /// EN
  /// Copy the picker's original to `attachments/<id>` and return its database-relative path.
  /// Called on send: write the file first, then commit the database row (`data-model.md` §5).
  Future<String> save(String attachmentId, String sourcePath) async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, attachmentId));
    await File(sourcePath).copy(target.path);
    return '$directoryName/$attachmentId';
  }

  /// ZH
  /// 写入归档导入的图片原件，返回数据库要存的相对路径（`history.md` §5）。
  ///
  /// EN
  /// Write an archive-imported image original; return its database-relative path (`history.md` §5).
  Future<String> saveBytes(String attachmentId, List<int> bytes) async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, attachmentId));
    await target.writeAsBytes(bytes, flush: true);
    return '$directoryName/$attachmentId';
  }

  /// ZH
  /// 读取原件；缺失时返回 null。
  ///
  /// EN
  /// Read the original bytes; return null when missing.
  Future<Uint8List?> readBytes(String? relativePath) async {
    final path = await absolutePath(relativePath);
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// ZH
  /// 相对路径对应的绝对路径；原件不存在时返回 null。
  ///
  /// EN
  /// Absolute path for a relative path; return null when the original does not exist.
  Future<String?> absolutePath(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final root = await _supportDirectory();
    final file = File(p.join(root.path, relativePath));
    return await file.exists() ? file.path : null;
  }

  /// ZH
  /// 删除已从数据库移除的附件原件；文件缺失时忽略。
  ///
  /// EN
  /// Delete originals for attachments removed from the database; ignore missing files.
  Future<void> deleteAttachments(Iterable<Attachment> attachments) async {
    final root = await _supportDirectory();
    for (final attachment in attachments) {
      final relative = attachment.localPath;
      if (relative == null || relative.isEmpty) continue;
      await _delete(File(p.join(root.path, relative)));
    }
  }

  /// ZH
  /// 删除附件目录中没有数据库记录的文件；失败不阻塞启动。
  ///
  /// EN
  /// Delete attachment-directory files with no database record; failures do not block startup.
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
      // ZH
      // 文件已缺失或不可删除时保持数据现状，下次启动再试。
      //
      // EN
      // If the file is missing or undeletable, keep data as-is and retry on next startup.
    }
  }
}
