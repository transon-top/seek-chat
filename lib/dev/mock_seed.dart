import 'package:shared_preferences/shared_preferences.dart';

import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/models/types.dart';
import 'markdown_samples.dart';

/// ZH
/// 样本会话标题；改名会让旧会话留在列表里，直到下次哈希变化被清理。
///
/// EN
/// Sample session titles; renaming leaves old sessions until the next hash change cleans them.
const String markdownSampleSessionTitle = 'Markdown 渲染测试';
const String longTextSampleSessionTitle = 'Markdown 超长文本降级';

/// ZH
/// 历史会话样本标题前缀：扩建或改内容时按前缀整体重建。
///
/// EN
/// History sample title prefix: rebuild the whole set by prefix when content changes.
const String historySampleTitlePrefix = '历史样本';

/// ZH
/// 历史会话样本条数：覆盖抽屉列表滚动、分组与渐隐的长时间场景。
///
/// EN
/// History sample count: covers long-list scrolling, grouping and edge fading in the drawer.
const int historySampleCount = 50;

/// ZH
/// 压测样本前缀：一个长会话加大量会话，供列表性能基线测量使用。
///
/// EN
/// Stress sample prefix: one long session plus many sessions for list performance baselines.
const String stressSampleTitlePrefix = '压测样本';
const String longSessionSampleTitle = '压测样本 · 长会话 1000 条';
const String stressSessionTitlePrefix = '$stressSampleTitlePrefix · 会话';

/// ZH
/// 长会话的总消息条数（提问与回复各一半）。
///
/// EN
/// Total messages in the long session (half prompts, half replies).
const int longSessionSampleMessages = 1000;

/// ZH
/// 压测会话条数，与现有 50 条历史样本叠加。
///
/// EN
/// Stress session count, added on top of the existing 50 history samples.
const int stressSessionSampleCount = 1000;

const String _sampleHashKey = 'dev.markdownSampleHash';
const String _historyHashKey = 'dev.historySampleHash';
const String _stressHashKey = 'dev.stressSampleHash';

/// ZH
/// debug 构建启动时写入 Markdown 样本会话。
///
/// 样本内容哈希与上次一致时跳过；变化时删除两个样本会话后重建，
/// 改样本只需热重启，不必手动删除会话。
///
/// EN
/// Debug builds seed the Markdown sample sessions at startup.
///
/// Skip when the sample hash matches; otherwise delete both sample sessions and rebuild,
/// so editing samples needs only a hot restart, not manual deletion.
Future<void> seedMarkdownSamples(
  ChatRepository repository,
  SharedPreferences prefs,
) async {
  final hash = _samplesHash();
  if (prefs.getInt(_sampleHashKey) == hash) return;

  for (final session in await repository.listSessions()) {
    if (session.title == markdownSampleSessionTitle ||
        session.title == longTextSampleSessionTitle) {
      await repository.deleteSession(session.id);
    }
  }
  // ZH
  // 先写超长文本会话，让主样本会话更新、冷启动自动打开。
  //
  // EN
  // Seed the long-text session first so the main sample stays newest for cold start.
  await _seedSession(repository, longTextSampleSessionTitle, [longTextSample]);
  await _seedSession(repository, markdownSampleSessionTitle, markdownSamples);
  await prefs.setInt(_sampleHashKey, hash);
}

Future<void> _seedSession(
  ChatRepository repository,
  String title,
  List<MarkdownSample> samples,
) async {
  final session = await repository.createSession();
  await repository.renameSession(session.id, title);
  for (final sample in samples) {
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: sample.prompt,
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: sample.thinking,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: sample.blocks,
    );
  }
}

/// ZH
/// 写入 50 条历史会话样本，覆盖抽屉的四个时间分组。
///
/// 时间戳需要落在不同日期，所以用可注入时钟的仓库生成；样本内容哈希不变
/// 时跳过，变化时按标题前缀整体重建。
///
/// EN
/// Seed 50 history sessions covering the drawer's four time groups.
///
/// Timestamps must fall on different days, so use a repository with an injectable clock;
/// skip when the hash is unchanged, otherwise rebuild the whole set by title prefix.
Future<void> seedHistorySamples(
  AppDatabase database,
  SharedPreferences prefs,
) async {
  final samples = _historySamples();
  final hash = _fnv1a([
    for (final sample in samples)
      '${sample.title}\u0000${sample.prompt}\u0000${sample.reply}',
  ]);
  if (prefs.getInt(_historyHashKey) == hash) return;

  final now = DateTime.now();
  var cursor = now;
  final repository = ChatRepository(
    database,
    clock: () => cursor.millisecondsSinceEpoch,
  );

  for (final session in await repository.listSessions()) {
    if (session.title.startsWith(historySampleTitlePrefix)) {
      await repository.deleteSession(session.id);
    }
  }
  for (final (index, sample) in samples.indexed) {
    cursor = _historySessionTime(now, index);
    final session = await repository.createSession();
    await repository.renameSession(session.id, sample.title);
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: sample.prompt,
    );
    final thinking = index % 5 == 0;
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: thinking,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: [
        if (thinking) const ThinkingBlock(thinking: '先按问题范围拆成几点，再逐条给出答案。'),
        TextBlock(text: sample.reply),
      ],
    );
  }
  await prefs.setInt(_historyHashKey, hash);
}

/// ZH
/// 写入压测样本：一个 1000 条消息的长会话与 1000 条会话。
///
/// 供列表性能基线测量使用；由 `SEEK_CHAT_STRESS_SEED` 或集成测试显式调用，
/// 默认启动不写，避免污染日常开发数据。样本内容哈希不变时跳过，变化时按
/// 前缀整体重建。
///
/// EN
/// Seed stress samples: one 1000-message long session and 1000 sessions.
///
/// For list performance baselines; called explicitly by `SEEK_CHAT_STRESS_SEED` or
/// integration tests, never at default startup, to keep daily dev data clean. Skip when
/// the sample hash is unchanged; otherwise rebuild the whole set by prefix.
Future<void> seedStressSamples(
  AppDatabase database,
  SharedPreferences prefs,
) async {
  final hash = _fnv1a([
    'stress-v1',
    '$longSessionSampleMessages',
    '$stressSessionSampleCount',
  ]);
  if (prefs.getInt(_stressHashKey) == hash) return;

  final now = DateTime.now();
  var cursor = now;
  final repository = ChatRepository(
    database,
    clock: () => cursor.millisecondsSinceEpoch,
  );

  for (final session in await repository.listSessions()) {
    if (session.title.startsWith(stressSampleTitlePrefix)) {
      await repository.deleteSession(session.id);
    }
  }

  // ZH
  // 会话样本：每条一个问答，时间从最近往前每 30 分钟一条铺开约 21 天。
  //
  // EN
  // Session samples: one Q&A each, spaced 30 minutes back from now over about 21 days.
  for (var index = 0; index < stressSessionSampleCount; index++) {
    cursor = now.subtract(Duration(minutes: 30 * (index + 1)));
    final session = await repository.createSession();
    await repository.renameSession(
      session.id,
      '$stressSessionTitlePrefix ${(index + 1).toString().padLeft(4, '0')}',
    );
    final exchange = _stressExchanges[index % _stressExchanges.length];
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: exchange.prompt,
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: [TextBlock(text: exchange.reply)],
    );
  }

  // ZH
  // 长会话放最后写入，成为最近会话，便于测量从抽屉首屏打开。
  //
  // EN
  // Seed the long session last so it is the latest, for measuring opening from the drawer.
  cursor = now;
  final session = await repository.createSession();
  await repository.renameSession(session.id, longSessionSampleTitle);
  for (var index = 0; index < longSessionSampleMessages ~/ 2; index++) {
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: '压测提问 ${index + 1}：请按第 ${index % 5 + 1} 种格式回答。',
    );
    final thinking = index % 5 == 0;
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: thinking,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: [
        if (thinking) const ThinkingBlock(thinking: '先确认格式要求，再组织一段可测量的正文。'),
        TextBlock(text: _stressReply(index)),
      ],
    );
  }
  await prefs.setInt(_stressHashKey, hash);
}

typedef _HistorySample = ({String title, String prompt, String reply});

const List<String> _historyTopics = [
  'Flutter 列表卡顿排查',
  'Drift 响应式查询',
  'SSE 断线重连',
  '发布前检查清单',
  'SQLite 索引怎么建',
];

/// ZH
/// 50 条样本循环使用 5 组问答，标题带序号以便区分。
///
/// EN
/// 50 samples cycle through five Q&A pairs; titles carry an index for distinction.
List<_HistorySample> _historySamples() {
  const exchanges = [
    (
      prompt: '帮我排查一下 Flutter 列表滚动卡顿的常见原因。',
      reply:
          '常见原因集中在三处：\n\n'
          '1. **重建范围过大**：状态变化时整页重建，缩小到列表项级别。\n'
          '2. **列表未懒加载**：`ListView` 用 `builder`，不要用 `children`。\n'
          '3. **图片解码开销**：给 `Image` 加 `cacheWidth`，并用 `RepaintBoundary` 隔离。',
    ),
    (
      prompt: '解释一下 Drift 的响应式查询是怎么工作的。',
      reply:
          'Drift 会为查询涉及的每张表建立依赖关系。\n\n'
          '表数据变化时，drift 通知所有引用该表的查询重新执行，'
          '再通过 `Stream` 推送新结果。\n\n'
          '```dart\n'
          'Stream<List<Todo>> watchTodos() =>\n'
          "    (select(todos)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();\n"
          '```',
    ),
    (
      prompt: 'SSE 连接断开后应该怎么重连？',
      reply:
          '分三步处理：\n\n'
          '| 情况 | 处理 |\n'
          '| --- | --- |\n'
          '| 网络中断 | 指数退避重试，上限 30 秒 |\n'
          '| 服务端 5xx | 提示稍后重试，不自动重放 |\n'
          '| 客户端主动停止 | 不重连 |\n\n'
          '重连后从最后一次事件 id 续传，避免重复内容。',
    ),
    (
      prompt: '列一份移动端 App 发布前的检查清单。',
      reply:
          '- [x] 版本号与构建号递增\n'
          '- [x] 关闭调试日志与 mock 数据\n'
          '- [ ] 真机验证深色模式\n'
          '- [ ] 检查权限文案与隐私声明\n'
          '- [ ] 上传符号表，确认崩溃回收可用',
    ),
    (
      prompt: 'SQLite 应该给哪些列建索引？',
      reply:
          '优先给查询里高频出现的过滤和排序列建索引：\n\n'
          '1. `WHERE` 条件列，选择度越高越好。\n'
          '2. `ORDER BY` 列，避免额外排序。\n'
          '3. 组合索引注意最左前缀。\n\n'
          '索引会增加写入成本，先用 `EXPLAIN QUERY PLAN` 确认扫描行数再决定。',
    ),
  ];

  return [
    for (var index = 0; index < historySampleCount; index++)
      (
        title:
            '$historySampleTitlePrefix ${(index + 1).toString().padLeft(2, '0')}'
            ' · ${_historyTopics[index % _historyTopics.length]}',
        prompt: exchanges[index % exchanges.length].prompt,
        reply: exchanges[index % exchanges.length].reply,
      ),
  ];
}

/// ZH
/// 压测会话的问答池：五种格式各一条，循环使用。
///
/// EN
/// Q&A pool for stress sessions: one per format, five total, cycled.
const List<({String prompt, String reply})> _stressExchanges = [
  (
    prompt: '压测：给一段带列表与图片的 Markdown。',
    reply:
        '## 列表与图片\n\n'
        '**粗体**与*斜体*混排，用于测量段落排版。\n\n'
        '- 第一项\n'
        '- 第二项\n'
        '  - 嵌套项\n\n'
        '![示例图片](https://example.com/session.png)',
  ),
  (
    prompt: '压测：给一个代码块。',
    reply:
        '### 代码块\n\n'
        '```dart\n'
        'int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);\n'
        '```',
  ),
  (
    prompt: '压测：给一个表格。',
    reply:
        '### 表格\n\n'
        '| 指标 | 目标 |\n'
        '| --- | --- |\n'
        '| 帧耗时 | ≤16.7ms |\n'
        '| 首屏 | <300ms |',
  ),
  (
    prompt: '压测：给一个 mermaid 图。',
    reply:
        '### mermaid\n\n'
        '```mermaid\n'
        'flowchart LR\n'
        '  A[消息] --> B[解析]\n'
        '  B --> C[渲染]\n'
        '```',
  ),
  (
    prompt: '压测：给一个公式。',
    reply:
        '### 公式\n\n'
        r'\['
        '\n'
        r'\int_0^1 x^2 dx = \frac{1}{3}'
        '\n'
        r'\]',
  ),
];

/// ZH
/// 长会话的回复池：五种格式循环，覆盖列表里最重的渲染路径。
///
/// EN
/// Reply pool for the long session: five formats cycling through the heaviest render paths.
String _stressReply(int index) {
  final label = '压测回复 ${index + 1}';
  switch (index % 5) {
    case 0:
      return '## $label\n\n'
          '这段正文用于测量长列表里 Markdown 段落、粗体与列表的渲染成本。'
          '**重点**：每帧只应重建可见项。\n\n'
          '- 第一项\n'
          '- 第二项\n'
          '  - 嵌套项\n\n'
          '![示例图片](https://example.com/stress-$index.png)';
    case 1:
      return '### $label\n\n'
          '```dart\n'
          'int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);\n'
          '```';
    case 2:
      return '### $label\n\n'
          '| 指标 | 目标 |\n'
          '| --- | --- |\n'
          '| 帧耗时 | ≤16.7ms |\n'
          '| 首屏 | <300ms |';
    case 3:
      return '### $label\n\n'
          '```mermaid\n'
          'flowchart LR\n'
          '  A[消息] --> B[解析]\n'
          '  B --> C[渲染]\n'
          '```';
    default:
      return '### $label\n\n'
          r'\['
          '\n'
          r'\int_0^1 x^2 dx = \frac{1}{3}'
          '\n'
          r'\]';
  }
}

/// ZH
/// 前 10 条在最近两小时内，接着 10 条在昨天，15 条在最近七天，其余更早。
///
/// EN
/// First 10 within two hours, next 10 yesterday, 15 in the last seven days, the rest older.
DateTime _historySessionTime(DateTime now, int index) {
  final today = DateTime(now.year, now.month, now.day);
  if (index < 10) {
    final early = now.subtract(Duration(minutes: 7 * (index + 1)));
    return early.isBefore(today) ? today.add(Duration(minutes: index)) : early;
  }
  if (index < 20) {
    return today
        .subtract(const Duration(days: 1))
        .add(Duration(hours: 21 - (index - 10)));
  }
  if (index < 35) {
    final offset = index - 20;
    return today
        .subtract(Duration(days: 2 + offset % 5))
        .add(Duration(hours: 9 + offset % 10));
  }
  final offset = index - 35;
  return today
      .subtract(Duration(days: 8 + offset * 4))
      .add(const Duration(hours: 15));
}

/// ZH
/// FNV-1a 32 位：跨进程稳定，用于判断样本是否被编辑过。
///
/// EN
/// 32-bit FNV-1a: stable across processes, used to detect edited samples.
int _fnv1a(Iterable<String> values) {
  var hash = 0x811c9dc5;
  for (final value in values) {
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }
  return hash;
}

int _samplesHash() {
  final values = <String>[];
  void add(String value) => values.add(value);

  for (final sample in [...markdownSamples, longTextSample]) {
    add(sample.label);
    add(sample.prompt);
    add('${sample.thinking}');
    for (final block in sample.blocks) {
      switch (block) {
        case TextBlock():
          add(block.text);
          for (final citation in block.citations) {
            add(citation.url);
            add(citation.title ?? '');
            add(citation.citedText);
          }
        case ThinkingBlock():
          add(block.thinking);
        default:
          break;
      }
    }
  }
  return _fnv1a(values);
}
