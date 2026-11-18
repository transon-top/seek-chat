# API 协议与流式客户端契约

Type: grilling
Status: resolved

## Question

把 chat-demo 的行为契约固化为 Dart 侧规格：

1. 请求体：`model`、`system`、`messages`、`thinking`、`tools`（MVP 是否只声明 `deepseek_read_url`、是否需要 `safety_check`）、`title` 扩展。
2. SSE：事件类型全集与 `applyEvent` 的合并语义（text / thinking / server_tool_use / web_search_tool_result / web_fetch_tool_result、block index 映射、signature_delta）。
3. 错误分类：http / stream / network / interrupted / protocol / upload，及可重试性。
4. 停止与续写：AbortController 等价物、`prefix` 语义、末尾 assistant 触发续写。
5. 分支请求构造：历史只回传哪些块（read_link 调用与结果、签名保留）。
6. 自动标题：服务端 `title: { enabled: true }` vs 本地截断。
7. API Key 校验（`GET /models`）与模型列表。
8. 流式客户端：Dart 侧用 `http` + 手写 SSE 解析还是现成包；取消、超时、背压、连接关闭判定。

产出：写入规格的 `api.md` 章节或独立文档，含类型定义草案与状态机图。

## Answer

规格写入 [`../api.md`](../api.md)，含 Dart 类型草案、状态机与测试清单。结论：

1. **请求体**：`model`、固定 `system`、`messages`、`thinking`、`tools`、`safety_check: high`、可选 `title`。`deepseek_read_url` 恒声明，`deepseek_web_search` 由本轮 `search` 快照决定；v1 固定 `deepseek-flash`，不做模型选择器。
2. **SSE**：事件全集与 `applyEvent` 合并语义已逐条锁定；服务端 index 映射到本地块下标，跳过块不占位；`tool_use` 使回复不可续写；`signature_delta` 拼接；无 `[DONE]`，`message_stop` 结束。
3. **错误**：`http / stream / network / interrupted / protocol / upload` 六类；可重试仅 `network`、`rateLimited`、`serverBusy`；消息流不自动重试，只有附件失效在未收到内容前最多重传重发 2 次（退避 1s、2s）。
4. **停止与续写**：Dart 用 `AbortableRequest` 的 `abortTrigger` 取消；`prefix` 只是本地回复状态，请求中没有该字段，末尾 assistant 触发续写；续写资格与请求构造规则见 `api.md` §6。
5. **分支上下文**：只回传「可用提问 + 可用回答」成对轮次；历史思考不回传，文本去引用并合并，工具只留 `read_link` 调用与结果且签名缺失时两者都丢弃。
6. **自动标题**：服务端 `title: { enabled: true }`；仅在标题为空、`end_turn/max_tokens`、去空白非空、未取消、未导入时采纳；手动重命名取消本轮写入；无本地截断兜底。
7. **Key 校验**：`GET /models` + `Authorization: Bearer`，只判 2xx，不解析模型列表。
8. **Dart 客户端**：`package:http` 1.5+ 的 `AbortableRequest` + 自写 WHATWG SSE 解析器（跨分片 CRLF、多行 data、注释、BOM、容错 UTF-8）；**不设客户端超时**，只由用户停止或服务端错误结束；应用级共享一个 `http.Client`。备选 `flutter_client_sse`、`dio`、`package:sse` 均否决，理由见 `api.md` §10。

交接：`latest_reminder` 的平台标记与语言取值 → 票 16；附件细节 → 票 13；引用展示 → 票 12；请求快照持久化 → 票 06；客户端生命周期与分层 → 票 07。
