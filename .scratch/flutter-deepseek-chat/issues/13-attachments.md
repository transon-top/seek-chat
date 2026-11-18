# 图片与文档上传

Type: grilling
Status: resolved
Blocked by: 05

## Question

对齐 chat-demo 的附件能力：

1. Files API：`POST /anthropic/v1/files` 的 `purpose`、`anthropic-beta: files-api-2025-04-14`、`file_id` 复用与删除。
2. 请求块：图片 `image`、文档 `document`；扩展模式（搜索）下 document 返回 400 的限制。
3. 选择与预览：file_picker / image_picker 选型；移动端是否支持粘贴与拖拽。
4. 本地存储：原件保存位置、与会话 / 消息的关联、删除策略、导出时的包含规则。
5. 校验：大小、格式、数量上限、上传失败重试与可重试性。
6. UI：附件条、上传进度、失败态、图片缩略图与查看器。
7. 权限：相册 / 文件访问权限的申请与拒绝处理。

产出：`attachments.md` 章节 + 上传状态机 + 限制表。

## Answer

结论写入 [`attachments.md`](../attachments.md)。要点：

1. **选型**：`file_picker` 13.4.0 单一依赖；相册用 `FileType.image`，文件用 `FileType.any` 后按白名单校验；不引入 `image_picker`，不做拍照/粘贴/拖拽。
2. **入口**：输入栏一个回形针按钮 → 底部面板「从相册选择 / 选择文件」；两种系统选择器都不需要权限声明。
3. **上传**：选中即上传，并发 3；`purpose` 图片不传、pdf/doc/docx/ppt/pptx 用 `rich_layout_recognition`、其余 `user_data`；首字段 `purpose` 后跟 `file`；v1 不删除远端文件。
4. **限制**：扩展名白名单逐项复制 `uploadExts.ts`；`user_data` 32 MB，其余 64 MB；单草稿最多 50 个；整批校验，任一失败整批不加入。
5. **存储**：发送时复制原件到 `<应用支持目录>/attachments/<id>`，先文件后数据库；删除会话后按引用清理文件；原件缺失只展示，不进入请求。
6. **发送**：全部附件上传成功才可发送；发送前补齐本轮与历史上下文的 `serverId`；`file_id` 失效自动清空并退避重传 2 次。
7. **失败**：上传失败区分服务器繁忙 / 解析失败 / 配额上限 / 其他；可重试项显示刷新图标，配额用 SnackBar 提示并链接删除文件文档；回复级 `upload` 错误可重试。
8. **UI**：输入区附件条（图片缩略图 / 文档卡片，上传中与失败态）、消息附件展示与全屏图片查看；发送按钮按「有文字或附件且全部上传完成」启用。
