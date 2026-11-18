# API 协议与流式客户端契约

Type: grilling
Status: open

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
