import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory support;
  late AppDatabase db;
  late ChatRepository repository;
  late AttachmentStore store;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('open_chat_attachments_');
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    store = AttachmentStore(supportDirectory: () async => support);
  });

  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

  Future<File> writeOriginal(String id) async {
    final directory = Directory(p.join(support.path, 'attachments'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, id));
    await file.writeAsString('content');
    return file;
  }

  test('cleanupOrphans deletes files without an attachment row', () async {
    final known = await writeOriginal('known');
    final orphan = await writeOriginal('orphan');
    final session = await repository.createSession();
    await repository.addUserMessage(
      sessionId: session.id,
      text: 'question',
      attachments: const [
        Attachment(
          id: 'known',
          name: 'known.png',
          size: 7,
          localPath: 'attachments/known',
        ),
      ],
    );

    await store.cleanupOrphans(repository);

    expect(known.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('deleteAttachments removes originals and ignores missing files', () async {
    final known = await writeOriginal('known');

    await store.deleteAttachments(const [
      Attachment(
        id: 'known',
        name: 'known.png',
        size: 7,
        localPath: 'attachments/known',
      ),
      Attachment(
        id: 'missing',
        name: 'missing.png',
        size: 7,
        localPath: 'attachments/missing',
      ),
      Attachment(id: 'no-path', name: 'none', size: 0),
    ]);

    expect(known.existsSync(), isFalse);
  });
}
