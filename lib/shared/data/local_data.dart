import 'dart:io';

import 'package:path/path.dart' as p;

import 'attachment_store.dart';
import 'database.dart';

/// ZH
/// 启动失败恢复入口：关闭数据库连接，删除主库及 `-journal` / `-wal` / `-shm`、
/// 旧库及同套附属文件、附件目录。
///
/// 只删除会话与附件数据；`SharedPreferences` 中的设置与安全存储中的 API Key
/// 不在本函数的接触范围内，因此自然保留。操作不承诺原子性：中途失败后再次
/// 调用会继续完成剩余删除。
///
/// EN
/// Startup recovery entry: close the database connection, then delete the main database
/// and its `-journal` / `-wal` / `-shm` files, the legacy database with the same sidecars,
/// and the attachments directory.
///
/// Only chats and attachments are removed; settings in `SharedPreferences` and the API key
/// in secure storage are outside this function's reach and are kept. The operation is not
/// atomic: a failed attempt leaves the remainder for the next call.
Future<void> clearChatsAndAttachments({
  required AppDatabase? database,
  required Future<Directory> Function() supportDirectory,
}) async {
  await database?.close();
  final root = await supportDirectory();
  for (final name in const [databaseFileName, legacyDatabaseFileName]) {
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      final file = File(p.join(root.path, '$name$suffix'));
      if (await file.exists()) await file.delete();
    }
  }
  final attachments = Directory(
    p.join(root.path, AttachmentStore.directoryName),
  );
  if (await attachments.exists()) await attachments.delete(recursive: true);
}
