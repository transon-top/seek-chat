import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/dev/markdown_samples.dart';
import 'package:seek_chat/dev/mock_seed.dart';
import 'package:seek_chat/shared/data/chat_repository.dart';
import 'package:seek_chat/features/sessions/session_drawer.dart';
import 'package:seek_chat/shared/data/database.dart';
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

  test('seeds 50 history sessions across every group once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await seedHistorySamples(db, prefs);
    await seedHistorySamples(db, prefs);

    final repository = ChatRepository(db);
    final sessions = await repository.listSessions();
    expect(sessions, hasLength(historySampleCount));
    expect(
      sessions.every((s) => s.title.startsWith(historySampleTitlePrefix)),
      isTrue,
    );

    final groups = {
      for (final (group, items) in groupSessions(sessions, DateTime.now()))
        group: items.length,
    };
    expect(groups, {
      SessionGroup.today: 10,
      SessionGroup.yesterday: 10,
      SessionGroup.last7Days: 15,
      SessionGroup.earlier: 15,
    });

    for (final session in sessions) {
      expect(await repository.loadMessages(session.id), hasLength(2));
    }
  });
}
