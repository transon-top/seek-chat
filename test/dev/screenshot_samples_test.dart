import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/dev/screenshot_samples.dart';
import 'package:seek_chat/shared/data/chat_repository.dart';
import 'package:seek_chat/shared/data/database.dart';
import 'package:seek_chat/shared/models/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('seeds the English demo sessions once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await seedScreenshotSamples(db, prefs);
    await seedScreenshotSamples(db, prefs);

    final repository = ChatRepository(db);
    final sessions = await repository.listSessions();
    expect(sessions, hasLength(7));
    expect(sessions.where((session) => session.pinned), hasLength(1));
    expect(sessions.first.title, 'Markdown, code & math');

    final search = sessions.firstWhere(
      (session) => session.title == 'Web search & citations',
    );
    final messages = await repository.loadMessages(search.id);
    final reply = messages.whereType<AssistantMessage>().single;
    expect(reply.blocks.whereType<ThinkingBlock>(), hasLength(1));
    expect(reply.blocks.whereType<ServerToolUseBlock>(), hasLength(1));
    expect(reply.blocks.whereType<WebSearchToolResultBlock>(), hasLength(1));
    final text = reply.blocks.whereType<TextBlock>().last;
    expect(text.citations, hasLength(2));

    for (final session in sessions) {
      expect(await repository.loadMessages(session.id), hasLength(2));
    }
  });
}
