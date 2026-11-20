import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/dev/markdown_samples.dart';
import 'package:open_chat/dev/mock_seed.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('seeds both sample sessions once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var tick = 0;
    final repository = ChatRepository(db, clock: () => tick++);

    await seedMarkdownSamples(repository, prefs);
    await seedMarkdownSamples(repository, prefs);

    final sessions = await repository.listSessions();
    expect(sessions, hasLength(2));
    expect(sessions.map((session) => session.title).toSet(), {
      markdownSampleSessionTitle,
      longTextSampleSessionTitle,
    });

    for (final session in sessions) {
      final sampleCount = session.title == markdownSampleSessionTitle
          ? markdownSamples.length
          : 1;
      final messages = await repository.loadMessages(session.id);
      expect(messages, hasLength(sampleCount * 2));
    }
  });
}
