# 图片与文档上传

Type: grilling
Status: open
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
