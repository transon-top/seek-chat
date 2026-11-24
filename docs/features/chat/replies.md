# 聊天与回复

状态：已实现 · 最后核对：2026-11-23
适用：SeekChat `0.5.0+1` · 数据库 `schemaVersion 2`

## 1. 范围与入口

一个 Session 内的对话闭环：发送、流式接收、停止、重新生成、编辑提问、
续写、分支切换、自动标题，以及长会话的初始窗口与跟随底部。

入口：

- 聊天页底部输入卡：发送 / 停止（见 [输入区与附件](../input/composer-attachments.md)）。
- 助手回复操作条：复制、朗读、重新生成、继续生成。
- 用户消息下方：编辑、版本切换器。
- 顶部栏：新建对话；打开会话抽屉。
- 首次发送消息时才创建 Session；空会话不落库。

## 2. 行为与状态

### 2.1 发送与新回复

- 发送条件：文本 `trim()` 非空，或草稿附件非空；所有草稿附件上传完成；
  语音状态为 `idle`；当前会话不在生成中。
- 发送时按当前开关快照本轮的 `thinking`（深度思考）与 `search`（智能搜索）；
  此后的开关变化不影响已创建的回复。
- 创建 assistant 行，状态 `pending`，块列表为空；会话 `updated_at` 前移。
- 请求发出前补齐本轮附件并生成 `latest_reminder` 快照。
- 收到任意已识别的流事件后进入 `streaming`；正常结束 `done`，用户停止
  `stopped`，请求或流出错 `error`。
- 流式期间只在内存合并增量，界面按帧刷新；不逐 token 写库。

### 2.2 停止

- 用户在输入区点停止：中止请求，保留已收内容，状态置 `stopped`；
  未结束的思考块按当前时间收尾。
- 停止不弹额外提示行；已收正文保留。
- 页面关闭、会话切换或 App 被杀不会留下永远悬空的「生成中」状态；
  启动时统一收尾，见 §2.7。

### 2.3 重新生成

- 入口：助手回复操作条。生成中与拒答时不可用。
- 在同一 user 消息下新增 assistant 版本，并选中新版本；旧回答及其子树保留。
- 新版本重新生成本轮 `latest_reminder` 快照。

### 2.4 编辑提问

- 入口：用户消息下方「编辑」；当前会话无生成中回复时可用。
- 点击后把原文与附件填回输入区；提交时以原消息的父节点为父，新建同父
  user 版本并复制附件关联，再插入新的 assistant 回复；旧子树保留。
- 编辑根提问时更新 `sessions.root_message_id`；编辑非根提问时更新父节点的
  `selected_child_id`。

### 2.5 续写

续写不新建消息，而是把原 assistant 行改为 `pending`，在末尾追加新块。
必须同时满足：

- `prefix` 为真（不是客户端工具调用回复）；
- 不是拒答，`stop_reason` 不是 `tool_use`；
- 不含任何工具块与模板文本；
- 状态为 `stopped`，或 `done` 且 `stop_reason` 为 `max_tokens`；
- 是当前可见路径的最后一条 assistant。

续写沿用原回复的 `model`、`thinking`、`search` 与 `latest_reminder` 快照，
并把会话 `updated_at` 前移。

### 2.6 分支与版本切换

- 消息通过 `parent_id` 挂在父节点下，通过 `selected_child_id` 指向当前选中的
  下一条；可见路径从 `sessions.root_message_id` 沿 `selected_child_id` 走到叶子。
- 有兄弟版本时显示版本切换器，格式「当前 / 总数」；生成中禁用。
- 切换只改父节点的 `selected_child_id`；切换根版本时改
  `sessions.root_message_id`。每个节点保留自己的选择，切回时下游路径恢复。
- 切换后保持滚动位置，不播放整页转场；切换会停止正在进行的朗读。

### 2.7 自动标题与启动兜底

- 自动标题只在以下条件全部满足时采纳：请求开始时会话标题为空、
  本轮带 `title.enabled`；请求未被取消；`stop_reason` 为 `end_turn` 或
  `max_tokens`；服务端返回的标题非空。
- 只写入一次；手动重命名、重新生成、续写都不覆盖已有标题。
- 空标题在界面显示「新对话」。
- 启动时把残留的 `pending` / `streaming` 回复统一置为 `stopped`。
- App 进入后台时，对正在流式的会话补写一次内存中的回复；补写失败不阻塞。

### 2.8 长会话：初始窗口

- 打开历史会话时只渲染可见路径末尾最近 50 条消息。
- 向上滚动到距已渲染范围起点 200 像素以内时，每次补 40 条更早消息。
- 补历史时做两段滚动偏移修正，视口不跳动。
- 初始窗口只影响渲染范围，不改变可见路径与请求上下文；不是数据分页。

### 2.9 跟随底部

- 内容不足一屏时，当前提问从视口顶部开始，回复向下增长。
- 超过一屏后跟随最新内容；距底部 40 像素以内视为「在底部」。
- 用户主动上滑离开底部后暂停跟随；重新贴近底部时恢复。
- 离开底部时显示「回到底部」浮动按钮；发送、编辑、重新生成、续写会
  重新开启跟随。

## 3. 边界与错误

- 请求错误按类型归为 `http`、`stream`、`network`、`interrupted`、`protocol`
  与 `upload`；可重试性按条件判定（详见 [内容安全与拒答](safety.md) §3 与
  错误映射约定）。
- 消息流不自动重试；唯一透明重发是附件 `file_id` 失效（最多 2 次，
  退避 1 秒、2 秒，已收到内容块则不重发）。
- `upload` 错误在回复下方显示原因与「重试」；其他错误通过「重新生成」重发。
- 401 不清除 Key，只提示更新；402、413、429、5xx 与网络错误使用各自文案。
- 已收正文在错误后保留；错误行优先于拒答文案。
- 编辑提交、重新生成、续写都会停止正在进行的朗读。
- 生成中不能再次发送、编辑、重新生成或切换版本；输入框与开关仍可编辑，
  停止入口只在输入区。

## 4. 持久化与兼容性

drift 四表：`sessions`、`messages`、`attachments`、`message_attachments`。

关键字段：

| 位置 | 字段 | 说明 |
| --- | --- | --- |
| `sessions` | `root_message_id` | 当前选中分支第一条；空会话为 `NULL` |
| `sessions` | `pinned` | 置顶，schema 2 新增；见 [会话抽屉](../sessions/session-drawer.md) |
| `messages` | `parent_id` / `selected_child_id` | 分支树与当前选择 |
| `messages` | `thinking` / `search` | 回复创建时的开关快照 |
| `messages` | `latest_reminder` | 本轮系统信息快照 |
| `messages` | `status` | `pending` / `streaming` / `done` / `stopped` / `error` |
| `messages` | `blocks` | 回复块 JSON 数组 |
| `messages` | `stop_reason` / `stop_details` / `usage` / `error` | 收尾与错误信息 |

- 主键为 UUID v4；时间为 epoch 毫秒；数据库列 snake_case，JSON 字段 camelCase。
- 落盘时机：创建回复、请求发出前、终态（`done` / `stopped` / `error`）、
  续写、进入后台、启动兜底；流式期间不写库。
- `updated_at` 在发送、重新生成、编辑、续写时前移；重命名、自动标题、置顶
  不改变活动时间。
- 删除会话在单事务内删除会话、消息与附件关联；提交后回收不再被引用的本地
  原件；远端 Files API 文件不删除。
- 数据库 `schemaVersion 2`；迁移使用显式 `from → to`，禁止破坏性回退。
- 草稿只在内存，不落库、不进归档。

## 5. 已知限制

- 不支持删除单条消息；只能删除整个会话。
- 草稿不跨页面或进程持久化；离开聊天页即丢弃。
- 不支持后台音频或后台任务调度；进入后台时只补写内存中的回复，
  进程仍可能被系统终止，启动时残留状态按 `stopped` 收尾。
- 每会话单流，跨会话可并行；切换会话不会停止原会话的生成，
  流式期间控制器保持存活，回到原会话可看到结果。
- 搜索命中不定位到具体消息；从搜索结果打开会话停在最新消息。
- 没有消息分页加载；初始窗口只减少渲染量，打开会话仍读取全部消息。
- 无服务端代理；Key 直连带来的逆向风险由产品接受。

## 6. 验证

- `test/features/chat/chat_controller_test.dart`：发送、停止、重新生成、编辑、
  续写、自动标题、快照与错误。
- `test/features/chat/messages_view_test.dart`：初始窗口、补历史、跟随底部、
  回到底部、版本切换。
- `test/shared/data/chat_repository_test.dart`：分支、可见路径、落盘时机、
  删除与附件回收。
- `test/app/app_test.dart`：端到端聊天流程与关键状态。
- `test/features/chat/reply_view_test.dart`：回复视图推导与操作可用性。

## 相关文档

- [消息渲染](rendering.md)
- [联网搜索与深度思考](web-search.md)
- [内容安全与拒答](safety.md)
- [输入区与附件](../input/composer-attachments.md)
- [按住说话与朗读](../input/speech.md)
- [会话抽屉](../sessions/session-drawer.md)
- [历史导入导出](../settings/history-archive.md)
- [`GLOSSARY.md`](../../../GLOSSARY.md)：Session、Message、Branch、Reply、Visible Path、
  Sticky Bottom、Initial Window、Reply Status
