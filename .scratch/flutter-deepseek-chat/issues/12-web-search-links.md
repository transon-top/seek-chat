# 联网搜索、深度思考搜索、阅读链接与引用角标

Type: grilling
Status: resolved
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

## Answer

结论写入 [`search.md`](../search.md)。要点：

1. **开关**：深度思考与智能搜索是两个独立开关，持久化到 `shared_preferences`，默认关闭；同时开启即深度思考搜索，无第三个开关；回复创建时快照，进行中的回复不受后续切换影响。
2. **视图**：搜索步骤不落库，由块纯函数推导 `ReplyView`；普通搜索按 `kind` 全局合并，深度搜索只合并相邻同类；`read_link` 仅 `wip` 时显示；事件状态机见 `search.md` §3.2。
3. **角标**：灰色数字小标签，用 `gpt_markdown` 的 `inlinePatterns` 渲染；点击外部打开 URL；编号越界的 token 移除；移动端无悬停预览。
4. **来源列表**：按用户截图改为「N 个网页」胶囊（叠加最多 4 个站点图标），点击由下向上弹出抽屉展示全部去重网页；票 09 的正文下横向来源卡由本方案取代。搜索行与「查看全部」打开同一抽屉。
5. **失败与重试**：中文文案逐条对齐 chat-demo；工具失败无单独重试，只能重新生成。
6. **图片搜索**：只影响文案，`image_url` 保存但不渲染。
7. **来源登记**：同一 URL 只编号一次，后到元数据只补空不覆盖；字段表与降级规则见 `search.md` §6.1。
8. **历史回传**：沿用 `api.md`，只回传成功的 `read_link` 与签名，搜索结果不回传。
9. **文案归属**：中文为基线，英文与 key 组织交票 18。

事实核查：`gpt_markdown` 1.4.1 支持 `inlinePatterns`（`lib/inline_pattern.dart`）；现有 `lib/features/chat/markdown_view.dart` 尚未使用该参数。
