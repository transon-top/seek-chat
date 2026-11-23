import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// ZH
/// `data-model.md` 的四张表；回复块存在 `messages.blocks` JSON 列中，
/// 不单独建表。
///
/// EN
/// The four tables from `data-model.md`; reply blocks live in the `messages.blocks` JSON
/// column and do not get a separate table.
@DataClassName('SessionRow')
@TableIndex.sql('CREATE INDEX sessions_updated_at ON sessions (updated_at DESC)')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get rootMessageId => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MessageRow')
@TableIndex(name: 'messages_session', columns: {#sessionId, #createdAt})
@TableIndex(name: 'messages_parent', columns: {#sessionId, #parentId, #createdAt})
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable()();
  TextColumn get selectedChildId => text().nullable()();
  TextColumn get role => text()
      .check(const CustomExpression<bool>("role IN ('user', 'assistant')"))();
  IntColumn get createdAt => integer()();
  TextColumn get textContent => text().named('text').nullable()();
  TextColumn get model => text().nullable()();
  BoolColumn get thinking => boolean().nullable()();
  BoolColumn get search => boolean().nullable()();
  TextColumn get latestReminder => text().nullable()();
  BoolColumn get prefix => boolean().nullable()();
  TextColumn get status => text()
      .check(const CustomExpression<bool>(
          "status IN ('pending', 'streaming', 'done', 'stopped', 'error')"))
      .nullable()();
  TextColumn get stopReason => text().nullable()();
  TextColumn get blocks => text().nullable()();
  TextColumn get stopDetails => text().nullable()();
  TextColumn get usage => text().nullable()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK ((role = \'user\' AND text IS NOT NULL) OR '
            '(role = \'assistant\' AND status IS NOT NULL))',
      ];
}

@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get size => integer()();
  BoolColumn get isImage => boolean().withDefault(const Constant(false))();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  TextColumn get localPath => text().nullable()();
  TextColumn get serverId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MessageAttachmentRow')
@TableIndex(
  name: 'message_attachments_attachment',
  columns: {#attachmentId},
)
class MessageAttachments extends Table {
  TextColumn get messageId =>
      text().references(Messages, #id, onDelete: KeyAction.cascade)();
  TextColumn get attachmentId => text().references(Attachments, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {messageId, attachmentId};
}

@DriftDatabase(
  tables: [Sessions, Messages, Attachments, MessageAttachments],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// ZH
  /// 打开应用支持目录下的本机数据库。其他地方只存相对路径：iOS 容器路径
  /// 在每次安装后会变化。
  ///
  /// EN
  /// Open the local database in the app support directory. Other places store relative
  /// paths only, because iOS container paths change on every install.
  static AppDatabase open() => AppDatabase(
        LazyDatabase(() async {
          final directory = await getApplicationSupportDirectory();
          final file = File(p.join(directory.path, 'seek_chat.sqlite'));
          // ZH
          // 兼容改名前创建的数据库：新文件不存在时把旧文件改名，保留本机会话。
          //
          // EN
          // Migrate databases created before the rename: rename the legacy file when the
          // new one is absent, preserving local sessions.
          // shortcut: one-time legacy DB rename, remove after v1 ships.
          final legacy = File(p.join(directory.path, 'open_chat.sqlite'));
          if (!await file.exists() && await legacy.exists()) {
            await legacy.rename(file.path);
          }
          return NativeDatabase(file);
        }),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // ZH
        // 每个版本都必须提供显式 from → to 的迁移，不启用破坏性回退，
        // 也不调用 deleteEverything。
        //
        // EN
        // Every version must supply an explicit from → to migration; destructive fallback
        // is not enabled, and deleteEverything is never called.
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(sessions, sessions.pinned);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
