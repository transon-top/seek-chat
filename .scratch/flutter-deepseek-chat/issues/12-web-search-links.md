# 联网搜索、深度思考搜索、阅读链接与引用角标

Type: grilling
Status: open
Blocked by: 05

## Question

对齐 chat-demo 的联网能力：

1. 工具声明：`deepseek_web_search`、`deepseek_read_url` 的启用条件；搜索、深度思考搜索的开关与输入区呈现。
2. 流事件：`server_tool_use`（search / open_page / find_in_page / read_link）、`web_search_tool_result`、`web_fetch_tool_result` 的累积与展示；`kind` 区分 search / deep_search / read_link / image_search / deep_image_search。
3. 引用角标：`[citation:N]` 解析、`TextCitation` 挂载、来源列表 / 抽屉、点击行为；找不到来源时的降级。
4. 历史回传：只回传 read_link 调用与结果；成功时保留 signature；搜索结果不回传。
5. 失败态：`web_search_tool_result_error`、`web_fetch_tool_result_error` 的文案与重试。
6. UI：搜索中的进度提示、来源卡片、站点图标 / 标题缺失的降级。
7. 与 Markdown 渲染的衔接：引用角标作为自定义 inline 节点；与渲染方案锁定票对齐。

产出：`search.md` 章节 + 事件状态机 + 来源卡片字段表。
