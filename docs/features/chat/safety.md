# 内容安全与拒答

状态：已实现 · 最后核对：2026-11-23
适用：SeekChat `0.5.0+1`

## 1. 范围与入口

服务端内容安全审核与客户端拒答展示：所有者是消息请求、附件图片与模型输出。
不包含本地内容过滤、独立隐私开关或账号级安全设置。

入口与触发：

- 所有消息请求（新回复、重新生成、续写、自动标题）恒携带
  `safety_check: { level: "high" }`。
- 输入文本 / 文档审核拒绝通过 HTTP 400 返回。
- 输入图片或模型输出审核拒绝通过流结束原因 `refusal` 返回。
- Files API 上传本身不触发审核；审核发生在消息请求时。

## 2. 行为与状态

### 2.1 请求侧

- `safety_check` 不提供开关，不随联网搜索、深度思考或附件变化。
- 客户端不预判请求是否会被审核，也不做本地内容过滤。
- 审核范围由服务端覆盖用户消息（文本、文档、图片）与模型输出。

### 2.2 响应处理

| 场景 | 服务端返回 | 客户端处理 |
| --- | --- | --- |
| 输入文本 / 文档未通过 | `400 Content Exists Risk` | 归类为 `contentRejected`，显示审核文案；不显示服务端原文 |
| 输入图片未通过 | `200` 流，`stop_reason: refusal`，`stop_details.explanation` 非空 | 丢弃思考与正文，显示图片审核文案 |
| 输出未通过 | 输出结束后 `stop_reason: refusal`，`explanation` 为空 | 丢弃已下发的思考与正文，显示通用拒答文案 |
| 限流 / 格式错误 | `429` / 其他 `400` | 按普通错误归类，不与审核混淆 |

- 拒答可能发生在流末尾：即使正文已经显示，最终收到 `refusal` 时仍必须丢弃。
- 拒答后保留工具块，但思考与正文不落库、不进入上下文。
- 原始 `explanation` 是内部路径文案，不直接展示；客户端只判断是否为空。

### 2.3 拒答展示

- 拒答文案使用正文样式，不使用红色错误色：这是模型答复，不是请求失败。
- 拒答时隐藏思考 / 工具时间线、正文、来源胶囊与「N 个网页」。
- 操作条只保留复制与版本切换；朗读、继续生成、重新生成禁用。
- 展示优先级：模板文本（导入历史）> 图片审核文案 > 通用拒答文案。
- 拒答与回复级错误同时存在时，错误行优先，不重复显示拒答文案。

文案：

| 场景 | 中文 | 英文 |
| --- | --- | --- |
| 输出拒答 | 你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。 | Sorry, that's beyond my current scope. Let's talk about something else. |
| 图片审核 | 图片未通过内容安全审核，请移除后重试。 | The image was blocked by content safety review. Remove it and try again. |
| 输入审核 400 | 内容未通过安全审核，请修改后重试 | The content did not pass safety review. Edit it and try again. |

## 3. 边界与错误

- 只把错误文案含 `Content Exists Risk`（大小写不敏感）的 400 归为审核拒绝；
  其余 400 保持原归类，避免把附件失效或参数错误误判为审核。
- 输入审核拒绝可重新生成，但发的是同一请求，用户需先修改内容。
- 图片拒答时用户需移除图片后重新发送；界面不指出具体是哪一张图片。
- 拒答回复不能续写、不能朗读、不能重新生成。
- 拒答前的输出 token 照常计费，`usage.outputTokens` 包含审核产生的 token；
  v1 没有用量界面。
- 429、402、413、5xx 与网络错误沿用普通错误文案与可重试性。

## 4. 持久化与兼容性

- 回复行保存 `stop_reason = refusal` 与 `stop_details`（含 `explanation`）；
  v1 只消费 `explanation` 是否为空。
- 拒答的思考与正文不写入 `blocks`；工具块保留。
- 导入历史时归档状态 `CONTENT_FILTER` 还原为 `done + refusal`，
  并丢弃思考与普通正文、保留工具块。
- 不新增表、列或归档字段。

## 5. 已知限制

- 不做本地内容预检；所有判断依赖服务端。
- 不展示服务端原始说明，也不指出被拦截的具体附件位置。
- 拒答与普通错误同时出现时只显示错误；用户可能不知道同时发生过拒答。
- 审核在用户配置的 DeepSeek API 侧完成，应用内没有独立隐私说明页。
- 图片审核只覆盖消息请求中的图片，不覆盖上传阶段。

## 6. 验证

- `test/shared/api/reply_accumulator_test.dart`：`refusal` 收尾与正文 / 思考丢弃。
- `test/features/chat/reply_view_test.dart`：拒答文案优先级、来源与时间线隐藏。
- `test/features/chat/chat_controller_test.dart`：拒答不可续写、不可重新生成。
- `test/shared/error_text_test.dart`：`contentRejected` 映射。
- `test/app/app_test.dart`：输出拒答、图片拒答与 400 审核的界面行为。

## 相关文档

- [聊天与回复](replies.md)
- [联网搜索与深度思考](web-search.md)
- [输入区与附件](../input/composer-attachments.md)
- [`GLOSSARY.md`](../../../GLOSSARY.md)：Reply、ReplyBlock、Template Text
