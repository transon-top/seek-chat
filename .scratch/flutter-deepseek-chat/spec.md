# SeekChat v1 规格

状态：定稿（票 11，2026-11-19）。
行为契约：`https://github.com/deepseek-ai/chat-demo`（React 18 + rspack 纯静态应用）。
本文汇总各票结论并做完整性检查；规范性细节以各章节文档为准，本文给出决策、边界与验收映射。

| 章节 | 文档 |
| --- | --- |
| API 协议与流式客户端 | [`api.md`](api.md) |
| 数据模型 | [`data-model.md`](data-model.md) |
| 应用架构与依赖 | [`architecture.md`](architecture.md) |
| Markdown / 数学 / Mermaid | [`markdown.md`](markdown.md) |
| 界面规格 | [`ui.md`](ui.md) |
| 联网搜索与引用 | [`search.md`](search.md) |
| 图片与文档上传 | [`attachments.md`](attachments.md) |
| 内容安全与图片审核 | [`safety.md`](safety.md) |
| 语音输入与朗读 | [`speech.md`](speech.md) |
| 历史导入导出 | [`history.md`](history.md) |
| 中英双语与主题 | [`i18n-theme.md`](i18n-theme.md) |
| 用户元信息 | [`user-metadata.md`](user-metadata.md) |
| 术语 | 根目录 [`GLOSSARY.md`](../../GLOSSARY.md) |

## 1. 目标、非目标、平台与版本

### 1.1 目标

v1 交付 iOS + Android 的 DeepSeek 聊天应用，界面用 `shadcn_ui`，行为对齐 chat-demo。
验收功能共 10 项：

1. 联网搜索、深度思考搜索、阅读链接。
2. 上传图片与文档。
3. 模型内容安全，包括图片审核。
4. 会话标题、重命名与删除会话。
5. 编辑消息、重新生成、继续生成。
6. 朗读回答与语音输入。
7. 在设置中选择语言和所在地，作为用户元信息标记传给模型。
8. 导入与导出历史对话（导入覆盖已有对话）。
9. Markdown 渲染，包括 Mermaid 图表。
10. 中文与英文界面，浅色与深色主题。

隐含基础能力：流式回复、深度思考、多会话、API Key 设置、代码高亮、数学公式。

### 1.2 非目标

- 桌面 / Web 平台适配；应用商店签名与发布流程。
- 云同步、多账号、跨设备；服务端 API 代理（v1 直连，接受 BYOK 风险）。
- 草稿持久化、消息折叠、模型选择器。会话置顶与抽屉内搜索已由
  [`sidebar-search`](../sidebar-search/spec.md) 单独规格，不计入 v1 非目标。
- 点赞 / 点踩 / 分享面板；图片结果墙；应用内文档预览；拍照、粘贴、拖拽上传。
- 后台录音 / 后台朗读、锁屏控制、真实波形与频谱。
- 旧版归档迁移；导入归档内设置、Key 或草稿；自动备份、增量合并、按会话导入导出。
- ZIP64、加密、分卷与流式 ZIP。

### 1.3 平台与工具链

- iOS 15+（工程部署目标 15.0）与 Android；手机竖屏优先，横屏与平板单列适配。
- Flutter 3.50.0 stable、Dart 3.14.0、Xcode 26.3、Android compileSdk 37 / NDK 28.2（票 04）。
- 无深链与 Web URL；路由只用 `Navigator` 1.0。

### 1.4 版本与固定常量

| 项 | 值 |
| --- | --- |
| 应用版本 | `1.0.0+1`（`pubspec.yaml`） |
| 数据库 schema | `schemaVersion 1` |
| 历史归档格式 | `export_format_version 3` |
| 模型 | 固定 `deepseek-flash`；`deepseek-v4-pro` 仅保留类型扩展位 |
| API 源 | 默认 `https://api.deepseek.com`，`--dart-define=SEEK_CHAT_API_ORIGIN` 覆盖 |
| 主题种子 | `#4D6BFE` |
| 品牌显示名 | 占位 `Fleepseek`；`DeepSeek API Key` 保留原文 |

## 2. 架构、目录与依赖

### 2.1 分层

功能优先（feature-first）+ `shared/` 核心；依赖方向固定为
`main → app → features → shared`。`shared/` 不 import `features/`，功能之间不直接 import。
`shared/` 只收纳被两个以上功能复用的代码。详见 [`architecture.md`](architecture.md) §1。

```
lib/
  main.dart          # 启动、数据库、残留状态收尾、ProviderScope
  app/               # 应用壳、路由、主题、locale、Material 桥接
  features/
    chat/            # 聊天页、消息、输入区、语音、附件、回复视图
    sessions/        # 会话列表 / 抽屉
    settings/        # 系统设置
    search/          # 来源胶囊、抽屉、卡片、引用角标
    history/         # 导入导出
  shared/
    api/ data/ models/ prefs/ security/ speech/
    providers.dart error_text.dart logging.dart
  l10n/              # ARB 与生成的 AppLocalizations
```

### 2.2 状态、并发与生命周期

- `flutter_riverpod` 3.5，手写 Provider，不引入 `riverpod_generator`。
- 基础设施用同步 `Provider`；会话列表用 `StreamProvider` + `ChatRepository.watchSessions()`。
- 聊天控制器为 `NotifierProvider.autoDispose.family<ChatController, ChatState, String>`；
  流式中 `ref.keepAlive()`，离开页面不取消请求，`ref.onDispose` 兜底取消。
- 每会话同时最多一个生成中的回复；不同会话可并行。会话内闸门为
  `ChatController.busy` 与 `ActiveReply`，不设全局锁。
- App 进入 `paused` / `hidden` 时补写内存中的流式回复；启动时把残留
  `pending` / `streaming` 置为 `stopped`。v1 不申请 iOS 后台执行权限。
- 音频通道全局互斥：录音、转写、朗读同一时间只有一个（`speech.md` §4.3）。

### 2.3 启动顺序

1. `WidgetsFlutterBinding.ensureInitialized()`。
2. 打开 `seek_chat.sqlite`，执行 `PRAGMA foreign_keys = ON`。
3. `resetInterruptedReplies()`。
4. 附件孤儿清理；失败只记日志，不阻塞启动。
5. 同步读取 `SharedPreferences`（语言 / 主题首帧无闪烁）。
6. `runApp(ProviderScope(...))`。

启动失败（数据库打开 / 迁移、偏好读取）的界面尚未规格化，见 §12 与票 22。

### 2.4 依赖清单（锁定 2026-11-19）

版本以 `pubspec.lock` 为准；下表为直接依赖的锁定快照。

| 包 | 锁定版本 | 用途 |
| --- | --- | --- |
| `flutter` / `flutter_localizations` | SDK 3.50.0 | 运行时与本地化 |
| `material_ui` | 1.11.1 | Material 3 基础与 shadcn_ui 底座 |
| `flutter_riverpod` | 3.5.0 | 状态管理与依赖注入 |
| `shadcn_ui` | 0.60.0 | 目标组件库 |
| `shared_preferences` | 2.5.6 | 本机设置 |
| `intl` | 0.20.3 | gen_l10n 运行时 |
| `http` | 1.6.0 | 网络、SSE、`AbortableRequest` |
| `drift` | 2.35.4 | 数据库 |
| `sqlite3` | 3.9.1 | drift 原生实现 |
| `path_provider` | 2.1.6 | 应用目录 |
| `path` | 1.9.1 | 路径拼接 |
| `uuid` | 4.6.0 | 主键 |
| `flutter_secure_storage` | 11.2.0 | API Key |
| `gpt_markdown` | 1.4.1 | Markdown、数学、代码高亮 |
| `mermaid_flutter` / `mermaid_core` | 0.3.2 / 0.3.2 | Mermaid 绘制与解析 |
| `url_launcher` | 6.3.3 | 外部链接 |
| `file_picker` | 13.4.0 | 相册、文件选择、导入导出保存 |
| `archive` | 3.6.1 | 历史归档 ZIP |
| `record` | 7.2.0 | 语音输入录音 |
| `flutter_soloud` | 5.3.1 | 朗读 PCM 流式播放 |
| `permission_handler` | 13.0.2 | 麦克风权限 |
| `cupertino_icons` | 1.0.9 | 图标资源 |
| `drift_dev` / `build_runner` | 2.35.3 / 2.17.1（dev） | 代码生成 |
| `flutter_lints` | 6.0.0（dev） | 静态规则 |
| `val_latex_flutter` | 0.1.4（dev） | 数学渲染测试断言 |

`lucide_icons_flutter` 3.1.25 经 `shadcn_ui` 传递引入，不新增直接依赖。

### 2.5 代码生成与质量门槛

代码生成只有 drift 与 gen_l10n 两链，生成物入库；不设覆盖率百分比、不引入 golden，
新分支、循环、解析或安全逻辑必须带测试。命令、依赖策略与 CI 计划见
[`architecture.md`](architecture.md) §11。

## 3. API 协议、流式状态机与错误处理

### 3.1 端点与鉴权

| 用途 | 方法与路径 | 鉴权 |
| --- | --- | --- |
| Key 校验 / 模型列表 | `GET {origin}/models` | `Authorization: Bearer {key}` |
| 消息 | `POST {origin}/anthropic/v1/messages` | `x-api-key` |
| 上传附件 | `POST {origin}/anthropic/v1/files` | `x-api-key` + `anthropic-beta: files-api-2025-04-14` |
| ASR | `POST {origin}/v1/tools/asr` | `Authorization: Bearer` |
| TTS | `POST {origin}/v1/tools/tts` | `Authorization: Bearer` |

消息请求另带 `Content-Type: application/json`、`Accept: text/event-stream`。
含文件块或 Files API 调用时追加 beta 头。`GET /models` 只校验 Key，不解析模型列表。

### 3.2 请求体

```jsonc
{
  "model": "deepseek-flash",
  "system": "该助手为DeepSeek，由深度求索公司创造。",
  "messages": [ /* latest_reminder 与 user/assistant 消息 */ ],
  "thinking": { "type": "enabled | disabled" },
  "tools": [ { "type": "deepseek_read_url", "name": "deepseek_read_url" },
             { "type": "deepseek_web_search", "name": "deepseek_web_search" } ],
  "safety_check": { "level": "high" },
  "stream": true,
  "title": { "enabled": true }    // 仅未命名会话
}
```

- `thinking` 取本轮回复创建时的快照；`deepseek_web_search` 仅在 `search` 快照为 true 时追加。
- `safety_check` 恒为 high；`stream: true` 由传输层追加。
- `latest_reminder` 伪装成 `role: latest_reminder`，位于对应 user 消息之前；内容五项：
  日期、星期、所在地、平台（iOS / Android）、语言，逗号连接。快照在附件补齐后、
  请求发出前生成并写入该 assistant 行；续写沿用原快照。

### 3.3 上下文构造

- 只回传「提问 + 可用回答」成对轮次。可用回答：`done` / `stopped`、非拒答、
  无模板文本、拼接正文非空。
- 用户消息有文件时 `content` 为数组：先文件块后文本块；图片用 `image`，其余用 `document`。
  `serverId` 为空的附件不进入请求。
- 历史 assistant：思考块不回传；文本块去 `citations`；只回传 `kind == read_link` 的工具调用与
  成功结果（保留 `signature`，缺签名则调用与结果都丢弃）；模板文本排除。
- 续写：历史取到原提问之前，末尾追加原 assistant 的当前块作为前缀；
  `thinking == true` 时保留本轮非空白思考与签名；无可用前缀则省略末尾 assistant。

### 3.4 SSE 与合并

- 事件名与 JSON `type` 相同，以 `message_stop` 结束，不发送 `[DONE]`。
- 事件全集：`message_start`、`content_block_start`、`content_block_delta`、
  `content_block_stop`、`message_delta`、`message_stop`、`ping`、错误帧。
- 合并：建立「服务端 index → 本地块下标」映射；`text_delta` / `thinking_delta` /
  `signature_delta` / `citations_delta` 按映射追加；`input_json_delta` 不消费；
  未知 index 忽略；无法识别的块不占位；客户端 `tool_use` 块丢弃并把 `prefix` 置 false。
- 拒答（`stop_reason: refusal`）：丢弃已下发的思考与正文，只保留工具块；不能续写、
  不能朗读。
- 中断：流在 `message_stop` 前结束且已收到 `stop_reason` 视为正常完成，否则按
  `interrupted` 错误收尾。
- 解析器复刻 WHATWG：三种换行、跨分片缓冲、多行 data、BOM、容错 UTF-8、
  未以空行结尾的事件丢弃；不自动重连。

### 3.5 回复状态机

```text
[*] → pending: 创建回复
pending → streaming: 收到任意已识别事件
pending → error: 请求前失败（upload/network/http/protocol）
streaming → streaming: 合并增量
streaming → done: message_stop，或 EOF 且已收到 stop_reason
streaming → stopped: 用户停止
streaming → error: stream/network/protocol/interrupted
stopped → pending: 续写或重新生成
done → pending: 续写或重新生成
error → pending: retryUpload 或重新生成
done / stopped / error → [*]
```

### 3.6 错误分类

| kind | 触发 | 可重试 |
| --- | --- | --- |
| `http` | 非 2xx | 按条件：network / rateLimited / serverBusy 可重试 |
| `stream` | 流中错误帧 | 否 |
| `network` | 请求未到达服务端 | 是 |
| `interrupted` | 流提前结束且无结束原因 | 否 |
| `protocol` | 非 SSE、无响应体、无法归类的流异常 | 否 |
| `upload` | 发送前补传附件失败，请求未发出 | 按 `retryable` |

状态码归类：`401 unauthorized`、`402 insufficientBalance`、`413 tooLarge`、
`429 rateLimited`、`>=500 serverBusy`、其余 `other`。唯一按文案归类：
`400` 且含 `Content Exists Risk` → `contentRejected`。消息流不自动重试；
唯附件失效会透明重发（最多 2 次，退避 1 s / 2 s，已收到内容块则不重发）。
本地化文案唯一映射点为 `lib/shared/error_text.dart`；服务端原文只在 debug 显示。

### 3.7 停止、续写与重新生成

- 停止：完成 `abortTrigger`，保留已收块，状态置 `stopped`，未结束思考块以当前时间收尾。
- 续写资格：`prefix == true`；非 `refusal` / `tool_use`；无任何工具块；无模板文本；
  `stopped` 或 `done + max_tokens`；是可见路径最后一条 assistant。
- 续写：同一 assistant 行状态改回 `pending`，新块追加在末尾，`message_delta` 更新
  stop reason 与累计 usage。
- 重新生成：同一 user 下新增 assistant 版本，旧回答子树保留。
- 编辑提问：新增同父 user 版本并复制附件关联，再插入新 assistant；旧子树保留。

### 3.8 自动标题与 Key 校验

- 自动标题仅在请求开始时会话标题为空且本轮带 `title.enabled` 时采纳；
  同时满足 `stop_reason` 为 `end_turn` / `max_tokens`、标题非空、未被手动重命名、
  请求未取消、未在导入历史。只写入一次；无本地截断兜底，空标题显示「新对话」。
- Key 校验：`GET /models` 2xx 即通过；401 显示「API Key 无效」，网络失败显示网络错误。

## 4. 数据模型与迁移

### 4.1 表与存储

- 四张表：`sessions`、`messages`、`attachments`、`message_attachments`（DDL 见
  [`data-model.md`](data-model.md) §1）。
- `messages.blocks` 存 JSON 数组（思考、文本、`server_tool_use`、
  `web_search_tool_result`、`web_fetch_tool_result`）；`stop_details`、`usage`、`error` 同为 JSON。
- 主键文本 UUID v4；时间为 epoch 毫秒；数据库列 snake_case，Dart / JSON camelCase。
- 附件原件存 `<Application Support>/attachments/<attachment.id>`，数据库存相对路径；
  `serverId` 存在附件行上，按附件 id 在所有引用间共享。
- 草稿只在内存；不做草稿表。

### 4.2 分支模型

- `sessions.root_message_id` 指向当前选中分支第一条；空会话为 NULL。
- 每条消息有 `parent_id` 与 `selected_child_id`；可见路径从 root 沿 `selected_child_id` 走到底。
- 切换版本只改父节点的 `selected_child_id`；切到根版本兄弟时改 `root_message_id`。
- 重新生成 / 编辑在父节点非空时更新父节点指针，根版本更新 `root_message_id`；旧子树不动。
- 续写不新建消息，更新原 assistant 行并沿用快照。

### 4.3 落盘时机

| 时点 | 写入 |
| --- | --- |
| 创建回复 | 插入 `pending` assistant 行，`blocks='[]'`，会话时间前移 |
| 附件补齐、请求发出前 | 写入 `latest_reminder` |
| 流式期间 | 不写库，只在内存合并，UI 按帧刷新 |
| `done` / `stopped` / `error` | 写入 blocks、状态、stop reason/details、usage、error；思考块补 `endedAt` |
| 续写 | 更新同一行；沿用原快照；会话时间前移 |
| App 进入后台 | flush 当前内存回复一次 |
| 启动 | 残留 `pending` / `streaming` 置 `stopped` |
| 导入 / 导出前 | 残留状态按 `stopped` 处理 |

### 4.4 删除与迁移

- 删除会话：单事务删除会话、消息与关联，提交后删除不再被引用的本地原件；
  远端 Files API 文件不删除；启动时清理孤儿文件。
- 原件缺失（`local_path` NULL 或文件不存在）：只展示元数据，不进入请求，不提供补传。
- drift `schemaVersion = 1`；`MigrationStrategy` 用 `stepByStep`，禁止 destructive fallback；
  升级失败进入可重试错误态，不自动清库。
- 归档格式版本独立于数据库版本，当前为 3。

## 5. 渲染栈与流式管线

### 5.1 选型

| 能力 | 选型 | 锁定版本 |
| --- | --- | --- |
| Markdown 与流式渲染 | `gpt_markdown`（`incremental` 分段缓存） | 1.4.1 |
| 数学 | `val_latex_flutter`（包内置引擎），仅启用 `\(...\)` / `\[...\]` | 0.1.4 |
| Mermaid | `mermaid_flutter` + `mermaid_core`，固定高 320 | 0.3.2 |
| 代码高亮 | `gpt_markdown` 内置 `val_highlight` / `CodeField` | 传递依赖 |
| 链接 | `url_launcher`，仅 http(s)，无协议补 `https://` | 6.3.3 |

不使用 `flutter_markdown`、`flutter_math_fork`、WebView + mermaid.js。

### 5.2 流式管线

1. SSE delta 由 `ChatController` 合并到内存。
2. 每帧最多一次界面更新；流式时按「上一帧耗时 × 2」开启节流窗口，限制在
   50 ms–2 s；窗口内 token 合并。
3. `MarkdownView` 渲染：增量 AST 缓存、稳定 `ValueKey`、局部重绘；
   流结束、切换版本或非流式文本立即显示全文。
4. 数学公式随 token 重排，半截公式不抛异常；Mermaid 保留上次成功场景，
   从未成功则降级等宽源码。

### 5.3 降级

| 情况 | 行为 |
| --- | --- |
| 数学解析失败 / 半截公式 | 显示原文 |
| Mermaid 流式半截 / 解析失败 | 保留上次成功；从未成功显示源码 |
| 未知围栏语言 | 纯文本代码块 |
| 单个文本块 > 200000 字符 | 跳过 Markdown，按纯文本 |
| 非 http(s) 链接 | 不响应 |
| Markdown 图片 | 不加载，显示可点击地址 |

### 5.4 性能预算与验收样例

- 目标设备 iPhone 13 / Pixel 6：更新 50 ms–2 s 一次；单次 Markdown 重建 ≤ 16.7 ms；
  已定稿段不重解析；200 条消息滚动流畅。**尚未真机实测**，见 §12。
- 验收样例与测试见 [`markdown.md`](markdown.md) §9 与
  `test/features/chat/markdown_view_test.dart`。

## 6. UI 规格、路由、组件与主题

### 6.1 路由与呈现

主路由为聊天页；会话列表改为左侧抽屉；系统设置为底部 Sheet，占屏 92%，
顶部三段导航（通用设置 / 账号管理 / 数据管理）。完整清单见 [`ui.md`](ui.md) §1.2。

| 界面 | 入口 | 呈现 |
| --- | --- | --- |
| 聊天页 | 应用启动 | 根页面 |
| 会话抽屉 | 顶部菜单 / 右滑 | 左侧 Sheet |
| 系统设置 | 抽屉底部设置行 | 底部 Sheet，三段导航 |
| 数据管理 | 设置导航 | Sheet 内二级视图 |
| 来源抽屉 | 「N 个网页」胶囊 / 搜索行 / 查看全部 | 底部 Sheet，最高 85% |
| 附件来源 | 回形针 | 底部 Sheet |
| 语言 / 所在地 / 音色 | 设置行 | 底部 Sheet |
| Key / 重命名 / 删除 / 导入确认 / 进度 | 对应入口 | Dialog |
| 图片查看 | 消息图片 | 全屏路由 |

### 6.2 聊天页

- 顶部栏高 46：菜单、居中标题（15sp / w500，空标题「新对话」）、新建对话；
  分享不渲染。
- 消息区水平 16；助手正文通栏无气泡；用户消息右对齐浅灰气泡；消息间距 16；
  宽屏内容最大 760 居中。
- 输入区：圆角 28、1px 描边、无阴影；回形针、语音、发送 / 停止；
  深度思考与智能搜索为两个独立胶囊开关，激活为蓝色系。
- 空态：「今天有什么可以帮到你？」；加载：进度条 + 3 条骨架 +「正在加载会话…」；
  错误：错误提示 + 重试。
- 自动滚动：仅在用户位于底部附近时贴底。

### 6.3 会话抽屉与设置

- 抽屉宽 `min(320, 屏宽×0.82)`；顶部 `Fleepseek` 文字标；新建对话胶囊；
  分组「今天 / 昨天 / 7 天内 / 更早」；当前会话蓝色高亮；底部设置行。
- 设置：主题三卡片；语言与所在地同区；朗读音色 / 深度思考 / 智能搜索 / 固定模型；
  麦克风权限三态；账号管理含 Key 与清除；数据管理含导入、导出、删除全部对话。
  交互状态详见 [`ui.md`](ui.md) §5.9。

### 6.4 主题与组件

- `ShadApp` + `ShadThemeData`，由 `ColorScheme.fromSeed(#4D6BFE)` 映射
  `ShadColorScheme`；`materialThemeBuilder` 把同一 Material 主题传给渲染包。
- `ShadTextTheme` 显式覆盖全部 13 个样式，字体清空为系统字体。
- 图标只用 `lucide_icons_flutter`（经 `shadcn_ui` 重导出）。
- 固定 token：圆角 4–28（Sheet 24、输入区 28、胶囊 999）；间距 2–48；
  页面内边距聊天 16 / 设置 20；点击区 ≥ 44；动态字体支持 2.0。
- 动效 150–180 ms，Sheet / Dialog 220–250 ms；`disableAnimations` 时全部静态化。
- 主题、颜色、字号、Markdown 元素完整表见 [`ui.md`](ui.md) §3。

组件映射（完整表见 [`ui.md`](ui.md) §2）：应用壳 `ShadApp`；主 / 次 / 危险按钮
`ShadButton` + `.outline` + `.destructive`；图标按钮 `ShadIconButton.ghost`
（视觉 28–36，点击区 ≥ 44）；输入 `ShadInput`；开关 `ShadSwitch`；进度 `ShadProgress`；
错误块 `ShadAlert.destructive`；对话框 `ShadDialog`；底部弹层 `ShadSheet`；
菜单 `ShadPopover`；提示 `ShadTooltip` / `ShadToast`；分隔线 `ShadSeparator`。
自绘组件按 [`ui.md`](ui.md) §2.2 落在所属功能目录，跨功能复用才下沉 `shared/`。

### 6.5 实现状态

界面迁移第 1–2 步已完成（2026-11-19）：`ShadApp` + `ShadThemeData` 由同一 Material
种子派生，中文行高 1.6；聊天页为根路由，会话抽屉、会话分组与新建 / 重命名 / 删除
已迁入 `SessionDrawer`，首条消息发出时才创建会话。设置页、输入区与消息区仍为
临时 Material 控件，按 §11 第 3–7 步继续。功能行为已按本规格实现；迁移期间每步
保持 `flutter analyze` 与 `flutter test` 通过。

## 7. 设置、语言与所在地、安全

### 7.1 设置与持久化

| 键 | 取值 | 默认 | 说明 |
| --- | --- | --- | --- |
| `user.locale` | `system` / `zh` / `en` | `system` | 界面语言与元信息语言共用 |
| `user.location` | JSON `{region, province, city}` | 空 | 非法数据整条丢弃 |
| `ui.themeMode` | `system` / `light` / `dark` | `system` | 首帧同步读取 |
| `tts.voice` | `stella` / `tide` | `stella` | 开始朗读时读取一次 |
| `speech.micRequested` | bool | `false` | 区分未请求与已拒绝 |
| `chat.thinking` / `chat.search` | bool | `false` | 输入区开关默认值 |

API Key 只存 `flutter_secure_storage`，不写数据库、不进日志、不进导出包、不进备份。
iOS 使用 `first_unlock_this_device`；Android 用默认密码套件，v1 不启用生物识别。
Android `allowBackup="false"`。

### 7.2 语言与所在地

- 语言首次跟随系统：以 `zh` 开头为中文，其余英文；切换立即生效，只影响之后创建的请求；
  已生成回复保留各自快照。
- 所在地选择器跟随**系统语言**：中文系统用省 / 市两级，其他系统用国家 / 地区；
  「不指定」用于清除（城市级退回省一级）。
- 元信息内容模板固定五项：`日期,星期,所在地,平台,语言`；未设置所在地保留空字段与逗号。
- 不申请定位权限；语言与所在地只随消息请求发给用户配置的 API。

### 7.3 安全边界

- 所有消息请求恒 `safety_check: { level: 'high' }`，不提供开关，不做本地内容过滤。
- 移动端 BYOK 的 Key 可被逆向提取；v1 接受此风险，生产分发需服务端代理。
- 401 不清除 Key，只提示更新。
- 日志仅 debug、不记录 Key、请求头、完整请求体与附件内容。

## 8. 联网搜索、附件、内容安全、语音

### 8.1 联网搜索与阅读链接

- 两个独立开关「深度思考」「智能搜索」持久化，默认关闭；同时开启即深度思考搜索。
- 回复创建时快照 `thinking` / `search`；续写沿用快照。
- 视图由 `ReplyView` 纯函数从持久化块推导：时间线步骤、正文、来源与去重网页结果；
  不新增持久化状态。
- 工具状态 `wip / done / failed` 只由块推导；无单工具重试，失败随回复保留。
- 来源登记三类：搜索结果、`deep_search` 抓取结果、正文引用；按 URL 唯一编号；
  `read_link` 与打开的页面不登记。
- 正文 `[citation:N]` 渲染为灰色数字角标，点击外部打开；来源缺失移除 token。
- 「N 个网页」胶囊在流结束、非拒答且有结果时显示，点击打开全局来源抽屉；
  搜索行与「查看全部」打开同一抽屉。
- 文本拼接、聚合、标题文案、字段降级以 [`search.md`](search.md) §3–§7 为准。

### 8.2 附件

- `file_picker` 单一入口：相册（`FileType.image`，原图）或文件（`FileType.any`）；
  不需要相册 / 存储权限。
- 白名单按 chat-demo 复制（约 950 个扩展名，小写比较）；大小上限：`user_data` 32 MB，
  图片与版面解析 64 MB；单次草稿最多 50 个；任一不合法整批拒绝。
- 图片按扩展名判定并写 `is_image`。
- 选中即上传，并发 3；`purpose` 按类型取值；不调用删除文件接口。
- 发送时把原件复制到应用支持目录（先写文件再写数据库）；未发送草稿只在内存。
- 发送闸门：文本非空或附件非空，且所有附件 `done`。
- 发送前补传：本轮并行，失败则请求不发出（`upload` 错误）；历史逐张补传，失败静默跳过。
- `file_id` 失效时清空对应 `serverId`，重新上传并重发，最多 2 次。
- 失败文案与重试图标按 [`attachments.md`](attachments.md) §6。

### 8.3 内容安全与图片审核

| 场景 | 客户端处理 |
| --- | --- |
| 输入 400 `Content Exists Risk` | 归类 `contentRejected`，显示审核文案，不显示原文 |
| 输入图片被拦截 | `stop_reason: refusal` + `explanation` 非空 → 图片审核文案 |
| 输出被拦截 | 丢弃已下发正文与思考，显示通用拒答文案 |

- 展示优先级：模板文本（导入历史）> 图片审核文案 > 通用拒答文案。
- 拒答隐藏思考 / 工具时间线、正文、来源与胶囊；重新生成禁用；不能续写与朗读。
- 拒答文案用正文样式，不用错误色；错误行优先于拒答文案。
- 文案键：`replyRefused`、`replyImageBlocked`、`apiErrorContentRejected`。

### 8.4 语音输入与朗读

- 语音输入：一次性录音，`record` 7.2.0，16-bit PCM WAV / 16 kHz / 单声道；
  上限 120 秒（文件 ≤ 8 MiB）；`POST /v1/tools/asr`，multipart 字段 `file`；
  结果去空白后插入光标处、替换选区，不自动发送。
- 转写失败除权限 / 无设备 / 空结果 / 上限外全部折叠为「语音识别失败」；不自动重试。
  录音被来电 / 路由 / 后台 / 切页中断时提示「录音已中断」；转写取消无提示。
- 朗读：仅 assistant 操作条；`POST /v1/tools/tts`，`format: pcm`、
  `filter_markdown: true`、`voice_id` 取 `tts.voice`；`flutter_soloud` 播裸 PCM
  （s16le、24 kHz、单声道），首帧前缓冲 100 ms。
- 朗读状态 `idle / loading / playing`；同条再点停止；全局单通道；录音与朗读互斥。
- 仅前台：进入非 `resumed` 取消录音并停止朗读；不添加后台音频模式。
- 麦克风权限三态由 `permission_handler` + `speech.micRequested` 区分；
  已拒绝提供「打开系统设置」。
- 语音与音频不落库、不进归档、不做 TTS 缓存；文案与错误映射见 [`speech.md`](speech.md) §6、§8。

## 9. 历史导入与导出

- 格式：chat-demo `export_format_version = 3`；文件名 `deepseek_data-YYYY-MM-DD.zip`；
  `archive` 读写，导出 STORE，导入接受 STORE / DEFLATE；单卷 ZIP32。
- 结构：`manifest.json` → 每会话 JSON → `chat_session_index.json` → 会话图片原件；
  不写 `user.json`（导入允许并跳过）。
- 范围：完整消息树与当前分支；图片原件只导出有本地文件的；文档等只导出元数据；
  不导出 Key、设置、草稿、`serverId`、模型名、签名、工具调用 ID、用量与 `citations`。
- 状态映射：导出时 `refusal → CONTENT_FILTER`、`max_tokens / stopped → INCOMPLETE`、
  `done → FINISHED`、`error → FAILED`、`pending/streaming → WIP`；导入后
  `CONTENT_FILTER → done + refusal`、`FINISHED → done`、`INCOMPLETE → stopped`、
  `FAILED → error`、`WIP → stopped`；所有导入 assistant `prefix = false`。
- 导入校验错误码：`unrecognized`、`newerVersion`、`invalidVersion`、`invalidJson`、
  `incomplete`、`invalidBranches`、`invalidFiles`、`tooLarge`；失败不改现有数据与生成状态。
- 覆盖导入状态机：`idle → confirm → validate → stop → writeFiles → replace → done`；
  单事务替换四表；保留设置、Key 与草稿任务；不自动备份；旧原件在提交后删除。
- 导出状态机：`snapshot → read → encode → save → done`；不修改数据库。
- 上限：ZIP 256 MiB、单 JSON 32 MiB、单图片 64 MiB、解压总量 512 MiB；
  整包驻留内存（`shortcut: 命中上限后再改为流式 ZIP`）。
- 界面：设置「数据管理」两行 + 删除全部对话；不可关闭进度；失败行内红字。
- 细节见 [`history.md`](history.md)。

## 10. v1 验收对照表

状态含义：**已实现** = 行为与自动化测试齐备；**已实现（临时 UI）** = 功能行为已实现，
最终界面待 §11 的 shadcn 迁移后复验。

| # | 验收功能 | 规格锚点 | 自动化测试 | 手动验收 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 1 | 联网搜索、深度思考搜索、阅读链接 | §3、§8.1 | `reply_view_test.dart`、`app_test.dart`（搜索摘要 / 停止 / 空结果 / 深度搜索）、`request_test.dart` | [`ui.md`](ui.md) §10.2 #4–5 | 已实现（临时 UI） |
| 2 | 上传图片与文档 | §8.2 | `attachment_rules_test.dart`、`attachments_view_test.dart`、`upload_tasks_test.dart`、`upload_client_test.dart`、`upload_errors_test.dart` | [`ui.md`](ui.md) §10.2 #3；§5.7；真机选择器 | 已实现（临时 UI） |
| 3 | 内容安全与图片审核 | §3.4、§8.3 | `reply_accumulator_test.dart`、`reply_view_test.dart`、`app_test.dart`（拒答 / 图片 / 400）、`error_text_test.dart` | [`ui.md`](ui.md) §10.2 #5 | 已实现（临时 UI） |
| 4 | 会话标题、重命名、删除 | §3.8、§4.2、§6.3 | `chat_repository_test.dart`、`chat_controller_test.dart`（自动标题） | [`ui.md`](ui.md) §10.2 #1–2；§5.10 | 已实现（临时 UI；重命名 / 删除无 widget 测试） |
| 5 | 编辑消息、重新生成、继续生成 | §3.7、§4.2 | `chat_controller_test.dart`、`app_test.dart`（分支重开 / 切换 / 编辑 / 生成中禁用） | [`ui.md`](ui.md) §5.5、§10.2 #6 | 已实现（临时 UI） |
| 6 | 朗读回答与语音输入 | §8.4 | `speech_controller_test.dart`、`speech_api_test.dart`、`speech_widgets_test.dart`、`speech_store_test.dart`、`speech_error_text_test.dart` | [`speech.md`](speech.md) §11.2 1–10；真机 | 已实现；真机项待验 |
| 7 | 语言与所在地元信息 | §7.2、§3.2 | `latest_reminder_test.dart`、`location_test.dart`、`user_metadata_store_test.dart`、`settings_page_test.dart` | [`ui.md`](ui.md) §10.2 #7；[`i18n-theme.md`](i18n-theme.md) §6 | 已实现（临时 UI） |
| 8 | 历史导入与导出 | §9 | `history_zip_test.dart`、`history_service_test.dart`、`history_section_test.dart`、`chat_repository_test.dart` | [`ui.md`](ui.md) §10.2 #9；[`history.md`](history.md) §8；真机文件面板 | 已实现（临时 UI） |
| 9 | Markdown 与 Mermaid | §5 | `markdown_view_test.dart`、`reply_view_test.dart` | [`ui.md`](ui.md) §10.2 #4；[`markdown.md`](markdown.md) §8 | 已实现 |
| 10 | 中英双语与浅深主题 | §6、§7.1、§7.2 | `app_test.dart`（中英 × 浅深）、`theme_test.dart`、`settings_page_test.dart` | [`i18n-theme.md`](i18n-theme.md) §6 四组合 | 已实现（临时 UI） |

跨项验收：

1. `flutter analyze` 与 `flutter test` 全绿；提交前执行。
2. 中 / 英 × 浅 / 深四组合逐页检查，无硬编码中文、无主题闪烁。
3. 真机检查：系统权限（麦克风）、文件选择 / 保存面板、TTS 首帧播放、
   录音后立即朗读、来电 / 后台中断、动态字体 2.0、减少动画。
4. 性能门槛：流式渲染 50 ms–2 s、单帧 ≤ 16.7 ms、200 条消息流畅（待实测）。

### 10.1 子版本验收门槛

子版本范围、演示脚本、公共门槛与回滚点见 [`roadmap.md`](roadmap.md) §2、§5；
本表只锁验收归属。

| 子版本 | 范围 | 验收锚点 | 通过条件 |
| --- | --- | --- | --- |
| S0 | 主题与聊天壳（已完成） | `ui.md` §9 第 1–2 步 | 抽屉分组、新建 / 重命名 / 删除、当前会话高亮可演示 |
| S1 | 输入区迁移 | 本文 §6.2、§8.2、§8.4；`ui.md` §5.2 | 蓝色开关、附件、语音、发送 / 停止、无 Key 态全过 |
| S2 | 消息区迁移 | 本文 §5、§6.2、§8.1、§8.3；`ui.md` §5.4–§5.6、§8 | 时间线、来源胶囊 / 抽屉 / 角标、分支与操作条、拒答全过 |
| S3 | 设置迁移 | 本文 §6.3、§7、§9；`ui.md` §5.9 | 三段导航、主题 / 语言 / 所在地 / 音色、Key、数据管理全过 |
| S4 | 启动失败界面（票 22） | 本文 §2.3；`architecture.md` §2；`data-model.md` §8 | 票 22 四项决策落文档；各失败路径按决策实现并有注入测试；不自动清库 |
| S5 | 无障碍、响应式与文案 | `ui.md` §6、§7、§10.1 | 语义、动态字体 2.0、320 宽、横屏 / 平板、减少动画、ARB 收口；重命名 / 删除 widget 测试补齐 |
| S6 | 真机验收、性能与 v1 候选 | 本文 §5.4、§10 全表 | 十项 + 跨项验收全绿；性能数字回填；CI 绿；无 P0 |

## 11. 实施顺序建议与风险

### 11.1 剩余实施顺序

功能行为已实现、测试覆盖；剩余工作集中在 [`ui.md`](ui.md) §9 的界面迁移，
按屏幕逐步进行，每步保持分析与测试通过：

1. ~~`lib/app/theme.dart`：`buildShadTheme` / `buildShadTextTheme`；`app.dart` 换 `ShadApp`
   与 Material 桥接。~~（已完成）
2. ~~聊天壳：`ChatHeader`、`SessionDrawer`、根路由切换，移除列表首页。~~（已完成）
3. 输入区：`Composer`、蓝色开关、附件条、语音按钮、发送 / 停止。
4. 消息区：用户 / 助手消息、思考与工具行、分支、操作条、来源胶囊与抽屉、角标。
5. 设置：三段导航 Sheet、主题卡片、语言 / 所在地 / 音色 Sheet、Key Dialog、数据管理二级视图。
6. 无障碍与响应式收口：语义、动态字体 2.0、320 宽、横屏、平板、减少动画。
7. 文案：新增 ARB 键、同步中英、`flutter gen-l10n`。

子版本切分、演示脚本与回滚点见 [`roadmap.md`](roadmap.md)（票 19）；
剩余工作按 S1–S6 推进，S4 可插入 S1–S3 之间。

### 11.2 风险

| 风险 | 影响 | 处置 |
| --- | --- | --- |
| 移动端 BYOK Key 可被逆向提取 | 高 | v1 接受；生产分发改服务端代理（不在本版） |
| `mermaid_flutter` / `mermaid_core` 0.3.x API 变化 | 中 | 锁定版本；升级必须重跑渲染验收样例 |
| `val_latex_flutter` 0.1.x、单一厂商、字体约 2.1 MB | 中 | 锁定版本；解析失败显示原文 |
| 流式渲染性能未真机实测 | 中 | 按 §5.4 目标在 iPhone 13 / Pixel 6 基准后回填 |
| TTS PCM 字节序官方未写明 | 中 | 上线前用已知 PCM spike 验证 `s16le`；不符则播放层交换 |
| `record` 与 `flutter_soloud` 音频会话切换 | 中 | 真机验证；冲突时等待释放，再失败降级 `just_audio`（失去首帧流式） |
| Android 音频中断上报不完整 | 中 | 以后台生命周期兜底；真机验收覆盖 |
| 归档整包驻留内存（256 MiB 上限） | 中 | 上限保护；命中后改流式 ZIP |
| 服务端 API 行为 / 限额变化 | 中 | 错误分类与文案隔离；发布前用真实 Key 回归 |
| 无 CI | 低 | 发布前加 GitHub Actions 执行四条命令 |
| 占位品牌 `Fleepseek` | 低 | 正式名称由发布票决定，不影响布局 |
| 站点图标远程加载的隐私与失败率 | 低 | v1 接受；仅加载服务端下发的 http(s) 图标，失败静默 |

## 12. 未决项

1. **启动失败的应用级界面**：数据库打开 / 迁移失败、偏好读取失败的界面与重试动作未规格化
   （`architecture.md` §2 的交接目标不存在）。已开票
   [`22-startup-failure.md`](issues/22-startup-failure.md)，列为 S4，不阻塞 S1–S3。
2. **真机性能基准**：§5.4 目标值待 iPhone 13 / Pixel 6 实测回填（S6）。
3. **语音真机验证**：TTS 字节序、录音后立即朗读、Android 中断兜底（`speech.md` §12，S6）。
4. **正式品牌名**：`Fleepseek` 为占位，S6 前定稿。

本次汇总未发现其他契约缺口；其余章节的所有决策均已由已关闭票锁定。
