# 内容安全与图片审核

票 14 的决策。行为契约以 `https://github.com/deepseek-ai/chat-demo` 为准，服务端行为以
[模型内容安全（DeepSeek API Docs）](https://api-docs.deepseek.com/zh-cn/guides/safety/) 为准。
术语见根目录 `GLOSSARY.md`，请求体见 [`api.md`](api.md) §2，附件见 [`attachments.md`](attachments.md)。

## 1. `safety_check` 启用范围

- 所有消息请求恒携带 `safety_check: { level: 'high' }`：新建回复、重新生成、续写、
  自动标题同属一个请求，全部覆盖（`api.md` §2，`request.dart`）。
- 不提供开关，不随联网搜索、深度思考或图片附件变化；`low` / 不传均为默认检查，
  v1 不使用。
- Files API 上传本身不触发审核；审核发生在「消息请求」时，检查用户消息（文本、
  文档、图片）与模型输出。
- 请求是否被审核不由客户端预判，也不做本地内容过滤。

## 2. 服务端返回与客户端处理

| 场景 | 服务端返回 | 客户端处理 |
| --- | --- | --- |
| 输入（文本/文档）未通过审核 | `400 Content Exists Risk`，或响应以拒答结束 | 400 按 `contentRejected` 归类；拒答按 §3 |
| 输入图片未通过审核 | `200` 流式，`stop_reason: refusal`，`stop_details.explanation` 指出被拦截图片（如 `messages.1.content.0`） | 丢弃正文与思考，显示图片审核文案（§3） |
| 输出未通过审核 | 输出结束后连接保持打开，最终 `stop_reason: refusal`，`stop_details.explanation` 为 null | 丢弃已下发的正文与思考（协议要求），显示通用拒答文案 |
| 限流 / 请求格式错误 | `429` / 其他 `400` | 仍按 `api.md` §5 归类，不与审核混淆 |

- 拒答可能发生在流末尾：实现已收到并显示正文时也必须丢弃（`ReplyAccumulator.settle`）。
- `stop_details.category` 恒为 null；`explanation` 仅在图片被拦截时非空。原始
  explanation 是内部路径文案，不直接展示。
- 拒答前的输出 token 照常计费，`usage.outputTokens` 已包含安全审核产生的 token；
  v1 无 usage 界面，不做额外处理。
- 拒答回复：思考与正文不落库（收尾时丢弃），工具块保留；不进入上下文，不能续写或
  朗读，不能重新生成（chat-demo 一致）。

## 3. 拒答展示与后续操作

| 来源 | 判定 | 正文区域 | 操作 |
| --- | --- | --- | --- |
| 正常结束 | `stopReason != refusal` | 正常正文 | 重新生成、续写按既有规则 |
| 输出拒答 | `refusal` 且无模板文本、`explanation` 为空 | 通用拒答文案，正文样式（非红色错误） | 无续写；重新生成禁用 |
| 图片拒答 | `refusal` 且 `explanation` 非空 | 图片审核文案 | 同上；用户移除图片后重新发送 |
| 文本输入审核拒绝 | HTTP 400 `Content Exists Risk` | 红色错误行「生成失败：内容未通过安全审核，请修改后重试」 | 可重新生成（发的是同一请求，需先改问题） |
| 其他请求错误 | 429 / 402 / 413 / 5xx / network 等 | 既有错误文案 | 既有可重试判定（`api.md` §5） |

- 展示优先级：模板文本（`isTemplate`，导入历史）> 图片审核文案（`explanation`
  非空）> 通用拒答文案。模板文本按正文 Markdown 展示；模板与 `explanation`
  去首尾空白后判空。
- 拒答与回复级错误同时存在时（流在拒答后断开等极少数情况），错误行优先，不重复
  显示拒答文案。
- 拒答时隐藏思考/工具时间线、正文、来源胶囊与「N 个网页」；重新生成按钮置灰。
- 拒答文案用正文样式，不用错误色：这是模型答复，不是请求失败。
- `stop_details` 已随回复持久化；v1 只消费 `explanation` 是否为空，不解析其路径，
  也不在界面上指出具体哪一张图片。

## 4. 文案

| 键 | 中文 | 英文 |
| --- | --- | --- |
| `replyRefused` | 你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。 | Sorry, that's beyond my current scope. Let's talk about something else. |
| `replyImageBlocked` | 图片未通过内容安全审核，请移除后重试。 | The image was blocked by content safety review. Remove it and try again. |
| `apiErrorContentRejected` | 内容未通过安全审核，请修改后重试 | The content did not pass safety review. Edit it and try again. |

- 文案与 chat-demo 的 `replyRefused` 对齐；另外两条是本端补充。
- 服务端原文不直接展示；仅 debug 构建的 `other` 条件沿用既有原文附加规则。
- 设置页不加独立隐私说明：审核由用户配置的 DeepSeek API 在同一请求内完成，
  没有新增数据接收方；设置页视觉与文案由票 20 / 18 收口。

## 5. 错误码区分

| 条件 | 状态码 / 字段 | 文案键 | 可重试 |
| --- | --- | --- | --- |
| 内容审核拒绝（输入） | 400，错误文案含 `Content Exists Risk` | `apiErrorContentRejected` | 否 |
| 限流 | 429 | `apiErrorRateLimited` | 是 |
| 其他请求错误 | 其他 400 / 402 / 413 / 5xx | 既有条件文案 | 按 `api.md` §5 |
| 模型拒答 | 200 + `stop_reason: refusal` | `replyRefused` / `replyImageBlocked` | 不按错误处理 |

- 内容审核拒绝只认服务端文案 `Content Exists Risk`（大小写不敏感）；其余 400 保持
  原归类，避免把附件失效、参数错误误判为审核。

## 6. 测试样例

| 样例 | 断言 | 层级 |
| --- | --- | --- |
| 正常回复 | 正文、时间线与来源正常展示；`safety_check` 恒在请求体 | 既有 app / client 测试 |
| 输出拒答 | 已下发的正文/思考被丢弃；显示通用拒答文案；时间线、来源与「N 个网页」隐藏；重新生成禁用 | app 测试 |
| 图片拒答 | `stop_details.explanation` 非空时显示图片审核文案，不显示原始路径 | app 测试 |
| 模板文本拒答 | 存在 `isTemplate` 文本时优先展示模板文本 | 视图纯函数测试（导入未实现，暂无端到端） |
| 文本审核 400 | 归为 `contentRejected`，显示审核文案，不显示服务端原文 | app 测试 + 文案映射测试 |
| 429 / 网络失败 | 仍走既有限流/网络文案与可重试性 | 文案映射 / 控制器测试 |
