import 'package:shared_preferences/shared_preferences.dart';

import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/models/types.dart';
import 'markdown_samples.dart';

/// 样本会话标题；改名会让旧会话留在列表里，直到下次哈希变化被清理。
const String markdownSampleSessionTitle = 'Markdown 渲染测试';
const String longTextSampleSessionTitle = 'Markdown 超长文本降级';

/// 历史会话样本标题前缀：扩建或改内容时按前缀整体重建。
const String historySampleTitlePrefix = '历史样本';

/// 历史会话样本条数：覆盖抽屉列表滚动、分组与渐隐的长时间场景。
const int historySampleCount = 50;

const String _sampleHashKey = 'dev.markdownSampleHash';
const String _historyHashKey = 'dev.historySampleHash';

/// debug 构建启动时写入 Markdown 样本会话。
///
/// 样本内容哈希与上次一致时跳过；变化时删除两个样本会话后重建，
/// 改样本只需热重启，不必手动删除会话。
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
  // 先写超长文本会话，让主样本会话更新、冷启动自动打开。
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

/// 写入 50 条历史会话样本，覆盖抽屉的四个时间分组。
///
/// 时间戳需要落在不同日期，所以用可注入时钟的仓库生成；样本内容哈希不变
/// 时跳过，变化时按标题前缀整体重建。
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

typedef _HistorySample = ({String title, String prompt, String reply});

const List<String> _historyTopics = [
  'Flutter 列表卡顿排查',
  'Drift 响应式查询',
  'SSE 断线重连',
  '发布前检查清单',
  'SQLite 索引怎么建',
];

/// 50 条样本循环使用 5 组问答，标题带序号以便区分。
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

/// 前 10 条在最近两小时内，接着 10 条在昨天，15 条在最近七天，其余更早。
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

/// FNV-1a 32 位：跨进程稳定，用于判断样本是否被编辑过。
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
