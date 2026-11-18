# 历史对话导入与导出（ZIP，覆盖导入）

Type: grilling
Status: open
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
