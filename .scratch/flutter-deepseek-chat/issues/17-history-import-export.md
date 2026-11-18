# 历史对话导入与导出（ZIP，覆盖导入）

Type: grilling
Status: resolved
Blocked by: 06

## Question

1. 对齐 chat-demo 归档格式：`src/services/chat/history/README.md`、`format.ts`、`paths.ts`。
2. 内容范围：会话、消息、分支、思考块、附件；API Key / 设置 / 草稿排除；图片原件的包含规则。
3. ZIP 读写：Dart `archive` 包 vs 其他；大文件流式处理与内存上限。
4. 文件选择与分享：file_picker、share_plus；iOS / Android 文档提供器。
5. 导入校验：版本、schema、损坏包的错误；覆盖前确认与自动备份。
6. 覆盖语义：清空现有会话与附件，保留设置与 Key；回滚路径。
7. 进度与取消；失败后的数据一致性。

产出：`history.md` 章节 + 归档格式表 + 导入状态机。

## Answer

结论写入 [`history.md`](../history.md)，实现在 `lib/features/history/`。要点：

1. **格式**：完全对齐 chat-demo `export_format_version = 3`：manifest → 会话 JSON → 索引 → 图片；导出用 STORE，单卷 ZIP32。
2. **内容**：全部会话与完整分支树、思考耗时、模板、搜索/阅读链接签名、图片原件；不含 API Key、设置、草稿、`serverId`；模型、思考签名、结构化错误、用量等归档无法表达的字段按 chat-demo 规则丢失。
3. **ZIP**：`archive` 3.6.1，整包内存读写；导入 256 MiB、单 JSON 32 MiB、单图片 64 MiB、解压总量 512 MiB 上限，超限提示文件过大。
4. **文件选择**：只用 `file_picker`（`pickFiles` / `saveFile`），不引入 `share_plus`。
5. **校验**：版本、ZIP 结构、CRC、JSON、索引对应、消息树与图片路径全部校验；失败不改数据、不停止生成。错误码映射到中英文案。
6. **覆盖**：确认后先停止全部生成，再按新附件 id 写图片、单事务替换四张表；附件 id 全部重新生成，旧原件不会被覆盖；保留设置与 Key；不自动备份旧历史，提交前旧数据始终保留。
7. **一致性与进度**：不可取消的阻塞进度框；事务保证失败不改库，遗留图片文件由启动孤儿清理回收；v1 不提供中途取消。
