# 术语表（GLOSSARY）

本仓库只有一个上下文：Flutter DeepSeek Chat 移动端。术语在规格、票与代码中含义一致。

## Session（会话）

一次对话的容器，拥有标题、创建/更新时间与当前选中分支的根消息。会话列表只读取元数据；打开会话才加载消息。空标题显示「新对话 / New chat」，自动标题只在标题为空时写入一次。

## Message（消息）

会话树中的一个节点，分为 user 与 assistant 两种角色。消息通过 `parentId` 挂在父节点下，通过 `selectedChildId` 指向当前选中的下一条消息。重新生成与编辑提问都会产生同一父节点下的新版本，旧版本及子树保留。

## Branch（分支）

从会话根消息沿 `selectedChildId` 走到无后继的一条路径。显示与请求上下文共用这条路径。切换版本只修改父节点的 `selectedChildId`；每个节点保留自己的选择，切回时下游路径恢复。根版本可以有多个 `parentId = NULL` 的消息，由 `sessions.rootMessageId` 选中。

## Reply（回复）

assistant 消息的运行时概念，带状态机：`pending → streaming → done | stopped | error`。续写把状态改回 `pending` 并追加块，不新建消息。状态只在创建、请求发出前、结束/停止/出错时落盘；流式期间只在内存中合并。

## ReplyBlock（回复块）

assistant 回复中的一个有序内容单元，存在 `messages.blocks` JSON 列中。类型包括思考块、文本块、`server_tool_use`、`web_search_tool_result`、`web_fetch_tool_result`。按协议字段原样保存；续写产生的块追加在末尾。

## Thinking（思考块）

回复块的一种，保存思考正文、`signature`、起止时间（epoch 毫秒）或导入数据的耗时秒数。历史轮次的思考不回传；仅续写前缀保留本轮思考与签名。

## Citation（引用）

文本块内的 `citations` 条目，结构为 `web_search_result_location`：`url`、`title`、`cited_text`、`encrypted_index`。同一文本块内的引用按 URL 去重由展示层处理；历史请求不回传引用。

## Attachment（附件）

用户消息引用的文件。本地原件按附件 id 共享存放于应用支持目录；元数据与 Files API `serverId` 存 `attachments` 表，消息与附件的引用关系存 `message_attachments` 表。`serverId` 按附件 id 在所有引用间共享，缺失时发送前补传；原件缺失的附件只展示、不进入请求。删除会话只回收不再被引用的本地原件，不删除远端文件。

## Latest Reminder（元信息快照）

每条 assistant 回复保存的本轮请求系统信息快照：日期、星期、所在地、平台、语言。请求中以 `latest_reminder` 角色插在对应 user 消息之前；续写沿用原快照。

## Template Text（模板文本）

服务端下发的提示性文本块，`isTemplate = true`。只用于展示，不作为正常回答进入上下文，含模板块的轮次不能续写。

## Visible Path（可见路径）

从 `sessions.rootMessageId` 沿每行 `selectedChildId` 走出的消息序列。界面展示与请求上下文的唯一来源。

## Reply Status（回复状态）

`pending`（已创建、请求未发出或未收到事件）、`streaming`（接收中）、`done`（正常结束）、`stopped`（用户停止、页面关闭、启动兜底）、`error`（请求或流出错）。启动时残留的 `pending`/`streaming` 统一按 `stopped` 收尾。
