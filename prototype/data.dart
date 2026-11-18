/// 票 09 原型用的假数据。故意与真实数据层无关，方便快速改文案与状态。
library;

/// 原型顶部的场景切换器。每个场景回答一类「长什么样」的问题。
enum PrototypeScenario {
  demo('完整'),
  streaming('流式'),
  empty('空会话'),
  loading('加载中'),
  error('错误'),
  stopped('已停止'),
  dropped('断流'),
  refusal('内容拒答'),
  long('超长消息');

  const PrototypeScenario(this.label);

  final String label;
}

class FakeSession {
  const FakeSession(this.id, this.title, this.time);

  final int id;
  final String title;
  final String time;
}

const fakeSessions = <FakeSession>[
  FakeSession(1, '对比三款降噪耳机', '10:24'),
  FakeSession(2, '把周报改得更简洁', '昨天'),
  FakeSession(3, 'Flutter 流式渲染方案', '昨天'),
  FakeSession(4, '上海三日游行程', '周一'),
  FakeSession(5, '解释这段 Rust 代码', '上周'),
];

class FakeSource {
  const FakeSource(this.index, this.site, this.title, this.url);

  final int index;
  final String site;
  final String title;
  final String url;
}

const demoSources = <FakeSource>[
  FakeSource(
    1,
    'theverge.com',
    '2026 旗舰降噪耳机横评：谁的地铁表现最好',
    'https://www.theverge.com/2026/earbuds-roundup',
  ),
  FakeSource(
    2,
    'rtings.com',
    '通话降噪实测：风噪与嘈杂街道场景数据',
    'https://www.rtings.com/headphones/tests/microphone',
  ),
];

class FakeAttachment {
  const FakeAttachment({
    required this.name,
    required this.isImage,
    this.uploadProgress,
    this.failed = false,
  });

  final String name;
  final bool isImage;

  /// 0..1 表示上传中，null 表示已完成。
  final double? uploadProgress;
  final bool failed;

  FakeAttachment copyWith({double? uploadProgress, bool? failed}) {
    return FakeAttachment(
      name: name,
      isImage: isImage,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      failed: failed ?? this.failed,
    );
  }
}

const demoDraftAttachments = <FakeAttachment>[
  FakeAttachment(name: 'desk-setup.jpg', isImage: true, uploadProgress: 0.62),
  FakeAttachment(name: '对比清单.pdf', isImage: false, failed: true),
];

const demoUserAttachments = <FakeAttachment>[
  FakeAttachment(name: 'desk-setup.jpg', isImage: true),
  FakeAttachment(name: '对比清单.pdf', isImage: false),
];

const demoUserQuestion =
    '帮我对比一下 AirPods Pro 3、Sony WF-1000XM6 和 Bose QC Ultra，重点看降噪和通话。';

const demoThinking =
    '用户要三款降噪耳机的对比，重点放在降噪与通话。先查最新评测，再按降噪、通话、佩戴三个维度整理。'
    '通话部分需要区分安静室内与街道风噪两种场景。';

const demoAnswer =
    '先给结论：通勤降噪优先 Sony WF-1000XM6，通话与生态优先 AirPods Pro 3，佩戴舒适优先 Bose QC Ultra。\n\n'
    'Sony 的低频降噪仍然最强，但麦克风在风噪下的语音清晰度一般；AirPods Pro 3 的通话算法与 iPhone 集成最好；'
    'Bose 的耳塞最轻，长时间佩戴压力最小。';

const demoFollowUp = '具体说说 Sony 的通话为什么一般？';

const demoStreamingThinking = '需要解释麦克风结构与风噪算法的差异，并引用实测数据。';

const demoStreamingPartial =
    'Sony 的通话短板主要来自两点：一是麦克风阵列在风噪环境下容易收进气流声，二是它的语音分离算法更保守，';

const demoBranchTwo =
    '换个角度看：如果主要在地铁和飞机上用，Sony 的降噪收益远大于通话短板；但如果你每天要在路上接工作电话，'
    'AirPods Pro 3 更稳。Bose 则适合对耳压敏感的人。';

/// 续写与发送后的假流式片段。
const streamChunks = <String>[
  '会尽量保留人声，',
  '代价是嘈杂环境下的音量偏小。',
  '实测在 60 km/h 风噪下，',
  'Sony 的语音清晰度比 AirPods 低约 12%。',
  '如果你经常在户外通话，',
  '建议优先考虑 AirPods 或 Bose。',
];

const longAnswer = '''
这是一段用于观察超长消息排版与折叠行为的假回答。真实回答可能包含多个段落、列表与代码块，原型只需要确认折叠阈值、展开入口与滚动性能的观感。

第一段：先说明结论。超长消息默认折叠到约 8 行，底部用渐隐遮罩提示还有内容；点击「展开全文」后完整显示，按钮变成「收起」。

第二段：补充依据。这里重复一些不重要的句子，用来把内容撑到足够长。降噪深度、通话清晰度、佩戴压力、延迟、续航与生态协同是六个常见维度。每个维度都可以单独展开，但原型不需要真的做六张表。

第三段：边界情况。消息里可能有链接、引用角标、行内代码 `selectedChildId`、公式与 Mermaid 图。真实渲染由 gpt_markdown 负责，原型只验证折叠容器不会裁掉这些块。

第四段：交互。长消息展开后，底部操作条仍然可见；复制、重新生成与朗读按钮不随折叠状态变化。滚动时输入区保持固定，消息列表自己滚动。

第五段：再次重复，确保文本足够长。降噪深度、通话清晰度、佩戴压力、延迟、续航与生态协同。降噪深度、通话清晰度、佩戴压力、延迟、续航与生态协同。降噪深度、通话清晰度、佩戴压力、延迟、续航与生态协同。

第六段：结尾。若这段文字在你的屏幕上仍然很短，请把窗口调窄或调大系统字号，原型会按实际文本高度判断是否显示折叠入口。
''';

const errorDescription = '网络请求超时。检查网络后重试，或稍后再发送。';

const droppedDescription = '连接中断，已生成的内容已保留。可以重试或继续生成。';

const refusalDescription = '该请求可能涉及不适合展示的内容，模型已停止回答。你可以修改提问后重试。';
