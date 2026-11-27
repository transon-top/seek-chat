import 'package:shared_preferences/shared_preferences.dart';

import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/models/types.dart';

/// ZH
/// README 截图用的英文样本：`--dart-define=SEEK_CHAT_SCREENSHOT_SEED=true`
/// 时替代中文 debug 样本写入，覆盖抽屉时间分组、置顶、搜索时间线、引用角标与
/// Markdown 渲染。只在 debug 构建生效。
///
/// EN
/// English samples for README screenshots: with
/// `--dart-define=SEEK_CHAT_SCREENSHOT_SEED=true` they replace the Chinese debug
/// samples, covering drawer time groups, pinning, the search timeline, citations and
/// Markdown rendering. Debug builds only.
const int _sampleVersion = 1;
const String _hashKey = 'dev.screenshotSampleHash';

const List<String> _sampleTitles = [
  'Markdown, code & math',
  'Web search & citations',
  'Voice input & read-aloud',
  'Attachments & drafts',
  'Release checklist',
  'SQLite indexing tips',
  'DeepSeek API quickstart',
];

Future<void> seedScreenshotSamples(
  AppDatabase database,
  SharedPreferences prefs,
) async {
  if (prefs.getInt(_hashKey) == _sampleVersion) return;

  final now = DateTime.now();
  var cursor = now;
  final repository = ChatRepository(
    database,
    clock: () => cursor.millisecondsSinceEpoch,
  );

  for (final session in await repository.listSessions()) {
    if (_sampleTitles.contains(session.title)) {
      await repository.deleteSession(session.id);
    }
  }

  Future<String> startSession(String title, DateTime time) async {
    cursor = time;
    final session = await repository.createSession();
    await repository.renameSession(session.id, title);
    return session.id;
  }

  // Older sessions first so the Markdown sample stays newest and opens on cold start.
  final quickstartId = await startSession(
    'DeepSeek API quickstart',
    now.subtract(const Duration(days: 2)),
  );
  await _exchange(
    repository,
    quickstartId,
    prompt: 'How do I send my first message to DeepSeek?',
    blocks: const [
      TextBlock(
        text:
            'Send a `POST` request to the Messages endpoint with your API key:\n\n'
            '```bash\n'
            'curl https://api.deepseek.com/anthropic/v1/messages \\\n'
            '  -H "x-api-key: \$DEEPSEEK_API_KEY" \\\n'
            '  -H "content-type: application/json" \\\n'
            '  -d \'{"model":"deepseek-flash","stream":true,"messages":[]}\'\n'
            '```\n\n'
            'Set `stream: true` to receive Server-Sent Events. SeekChat stores the '
            'key in secure storage and never logs it.',
      ),
    ],
  );
  await repository.setSessionsPinned([quickstartId], true);

  final sqliteId = await startSession(
    'SQLite indexing tips',
    now.subtract(const Duration(days: 20)),
  );
  await _exchange(
    repository,
    sqliteId,
    prompt: 'Which columns should I index in SQLite?',
    blocks: const [
      TextBlock(
        text:
            'Index the columns you filter and sort on most often:\n\n'
            '1. High-selectivity columns in `WHERE` clauses.\n'
            '2. Columns used by `ORDER BY` to avoid a temp sort.\n'
            '3. Composite indexes respect the leftmost-prefix rule.\n\n'
            'Indexes slow down writes, so check `EXPLAIN QUERY PLAN` before adding one.',
      ),
    ],
  );

  final releaseId = await startSession(
    'Release checklist',
    now.subtract(const Duration(days: 6)),
  );
  await _exchange(
    repository,
    releaseId,
    prompt: 'Draft a release checklist for a mobile app.',
    blocks: const [
      TextBlock(
        text:
            '- [x] Bump version name and build number\n'
            '- [x] Turn off debug logging and mock data\n'
            '- [ ] Verify dark mode on a physical device\n'
            '- [ ] Review permission copy and privacy policy\n'
            '- [ ] Upload symbols and confirm crash reporting',
      ),
    ],
  );

  final attachmentsId = await startSession(
    'Attachments & drafts',
    now.subtract(const Duration(days: 3)),
  );
  await _exchange(
    repository,
    attachmentsId,
    prompt: 'Can I attach a PDF and a photo to the same prompt?',
    blocks: const [
      TextBlock(
        text:
            'Yes. Use the **+** button in the composer to pick photos or files — '
            'images, PDF, Word and PowerPoint are accepted. Each attachment shows its '
            'upload progress above the input, and drafts keep attachments until you send.',
      ),
    ],
  );

  final voiceId = await startSession(
    'Voice input & read-aloud',
    now.subtract(const Duration(days: 1)),
  );
  await _exchange(
    repository,
    voiceId,
    prompt: 'How does voice input work?',
    blocks: const [
      TextBlock(
        text:
            'Hold the microphone button to record, then release to transcribe. '
            'The transcript lands in the composer for review before sending.\n\n'
            'Tap the speaker icon on any reply to read it aloud; pick the voice under '
            'Settings → Voice.',
      ),
    ],
  );

  final searchId = await startSession(
    'Web search & citations',
    now.subtract(const Duration(hours: 1)),
  );
  await _exchange(
    repository,
    searchId,
    prompt: 'What changed in the latest Flutter stable release?',
    thinking: true,
    search: true,
    blocks: const [
      ThinkingBlock(
        thinking:
            'The question is about the latest stable release. I should search first, '
            'then summarize the changes with sources for each claim.',
      ),
      ServerToolUseBlock(
        id: 'toolu_search_1',
        name: 'deepseek_web_search',
        input: SearchInput(queries: ['Flutter latest stable release notes']),
        kind: ServerToolKind.search,
      ),
      WebSearchToolResultBlock(
        toolUseId: 'toolu_search_1',
        kind: ServerToolKind.search,
        content: [
          WebSearchResult(
            title: 'Flutter release notes',
            url: 'https://docs.flutter.dev/release/release-notes',
            snippet:
                'Release notes for the current stable channel, including framework and engine changes.',
            encryptedContent: '',
            siteName: 'docs.flutter.dev',
            pageAge: '2 days ago',
          ),
          WebSearchResult(
            title: 'Flutter on GitHub',
            url: 'https://github.com/flutter/flutter/releases',
            snippet:
                'Signed release builds, changelogs and hotfix announcements for every channel.',
            encryptedContent: '',
            siteName: 'github.com',
            pageAge: '2 days ago',
          ),
        ],
      ),
      TextBlock(
        text:
            'The latest stable release focuses on rendering performance and developer '
            'tooling. Frame scheduling is smoother on high-refresh displays, and the '
            'inspector now reports rebuild counts per widget.',
        citations: [
          TextCitation(
            url: 'https://docs.flutter.dev/release/release-notes',
            title: 'Flutter release notes',
            citedText: 'Rendering performance and developer tooling improvements.',
            encryptedIndex: '1',
          ),
          TextCitation(
            url: 'https://github.com/flutter/flutter/releases',
            title: 'Flutter on GitHub',
            citedText: 'Signed release builds and hotfix announcements.',
            encryptedIndex: '2',
          ),
        ],
      ),
    ],
  );

  final markdownId = await startSession(
    'Markdown, code & math',
    now.subtract(const Duration(minutes: 10)),
  );
  await _exchange(
    repository,
    markdownId,
    prompt: 'Show me how replies are rendered.',
    blocks: const [
      TextBlock(
        text:
            'Replies render **Markdown**, syntax-highlighted code, tables and math.\n\n'
            '| Element | Rendered |\n'
            '| --- | --- |\n'
            '| Headings | Yes |\n'
            '| Tables | Yes |\n'
            '| Math | Yes |\n\n'
            '```dart\n'
            'Future<void> main() async {\n'
            '  final client = DeepSeekApiClient();\n'
            '  await for (final event in client.sendMessage(prompt)) {\n'
            '    print(event);\n'
            '  }\n'
            '}\n'
            '```\n\n'
            r'Inline math stays tidy: \(E = mc^2\). Long replies stream in without '
            'dropping frames, and every code block has a copy button.',
      ),
    ],
  );

  await prefs.setInt(_hashKey, _sampleVersion);
}

Future<void> _exchange(
  ChatRepository repository,
  String sessionId, {
  required String prompt,
  required List<ReplyBlock> blocks,
  bool thinking = false,
  bool search = false,
}) async {
  final user = await repository.addUserMessage(
    sessionId: sessionId,
    text: prompt,
  );
  final reply = await repository.createReply(
    sessionId: sessionId,
    userMessageId: user.id,
    model: ChatModel.deepseekFlash,
    thinking: thinking,
    search: search,
  );
  await repository.updateReply(
    messageId: reply.id,
    status: ReplyStatus.done,
    blocks: blocks,
  );
}
