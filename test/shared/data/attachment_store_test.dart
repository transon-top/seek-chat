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

  test('save copies the original under attachments/<id>', () async {
    final source = File(p.join(support.path, 'picked.pdf'))
      ..writeAsBytesSync([1, 2, 3]);

    final relative = await store.save('att-1', source.path);

    expect(relative, 'attachments/att-1');
    final saved = File(p.join(support.path, relative));
    expect(saved.readAsBytesSync(), [1, 2, 3]);
    expect(await store.absolutePath(relative), saved.path);
  });

  test('saveBytes writes an archive image and readBytes reads it back', () async {
    final relative = await store.saveBytes('imported', [1, 2, 3, 4]);

    expect(relative, 'attachments/imported');
    expect(
      File(p.join(support.path, relative)).readAsBytesSync(),
      [1, 2, 3, 4],
    );
    expect(await store.readBytes(relative), [1, 2, 3, 4]);
    expect(await store.readBytes('attachments/missing'), isNull);
    expect(await store.readBytes(null), isNull);
  });

  test('absolutePath returns null for missing originals', () async {
    expect(await store.absolutePath(null), isNull);
    expect(await store.absolutePath(''), isNull);
    expect(await store.absolutePath('attachments/missing'), isNull);
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
