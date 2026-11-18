# 图片与文档上传

票 13 的决策。行为契约以 `~/ZoneCode/chat-demo` 为准；本文只记录与移动端相关的取舍。
术语见根目录 `GLOSSARY.md`，数据表见 [`data-model.md`](data-model.md)，接口前缀见 [`api.md`](api.md)。

## 1. 选型与入口

- 选择器：`file_picker` 13.4.0，单一依赖覆盖相册与文件。
  - iOS 15+（工程部署目标 15.0）：相册走 `PHPickerViewController`，文件走 `UIDocumentPickerViewController`。
  - Android：相册走系统图片选择器，文件走 Storage Access Framework。
  - 不引入 `image_picker`；不实现拍照、粘贴与拖拽（移动端契约未覆盖，v1 不做）。
- 入口：输入栏一个回形针按钮，点击弹出底部面板两项：
  - 「从相册选择」：`FileType.image`，多选，原图不压缩（`compressionQuality: 0`）。
  - 「选择文件」：`FileType.any`，多选；选中后按扩展名白名单校验。
- 权限：两种系统选择器都不需要存储或相册权限；不新增 `Info.plist` 与 `AndroidManifest.xml` 条目。
  不申请相机权限。

## 2. Files API 与请求块

- 上传：`POST {origin}/anthropic/v1/files`，`multipart/form-data`。
  - 头：`x-api-key`、`anthropic-beta: files-api-2025-04-14`。
  - 字段顺序：`purpose`（可为空则不传）在前，`file` 在后。
  - `purpose` 取值：图片不传；`pdf`、`doc`、`docx`、`ppt`、`pptx` 传 `rich_layout_recognition`；其余传 `user_data`。
  - 响应 `{ "id": ... }` 即 `serverId`。不设过期；v1 不调用 `DELETE /files/{id}`（`chat-demo` 也不调用）。
- 请求块：`serverId` 非空的附件按顺序放在文本块之前；图片用
  `{type: image, source: {type: file, file_id}}`，其余用 `document`。
  `serverId` 为空的附件不进入请求。含文件块的请求追加 beta 头（已由传输层按 `hasFileBlocks` 实现）。
- 搜索扩展下 `document` 会被服务端以 400 拒绝：不在客户端预先拦截，按普通 HTTP 错误展示，与 `chat-demo` 一致。

## 3. 校验与限制

| 项 | 规则 |
| --- | --- |
| 扩展名 | 白名单逐项复制 `chat-demo/src/services/uploadExts.ts`（约 950 个，小写比较；无扩展名不支持）。`heic`/`heif` 不在白名单 |
| 大小 | `user_data` 32 MB；图片与版面解析（pdf/doc/docx/ppt/pptx）64 MB |
| 数量 | 单次草稿最多 50 个 |
| 批次 | 任一文件不合法则整批不加入；错误文案见 §6 |
| 图片判定 | 按扩展名：png/jpg/jpeg/gif/webp/svg/svgz/bmp/ico/tif/tiff/avif/apng/jfif/xbm/dib/pjp/pjpeg |

`chat-demo` 用浏览器 MIME 判定图片；移动端拿不到可靠 MIME，按扩展名判定，并写入 `attachments.is_image`。

## 4. 本地存储

- 选中文件后原件来自系统选择器的临时路径；**发送时**复制到
  `<应用支持目录>/attachments/<attachment.id>`，数据库存相对路径
  `attachments/<id>`。先写文件再写数据库行，文件写失败则整次发送失败。
- 未发送的草稿只在聊天页内存中；离开页面即丢弃（草稿不在 v1 范围，见地图 Out of scope）。
- 删除会话：删除消息与附件行，事务提交后删除不再被任何附件行引用的文件；远端 Files API 文件不删除。
- 原件缺失（`local_path` 为 NULL 或文件不存在）：只展示元数据，不进入请求，不提供补传入口。
- 附件 id 为 UUID v4；一个原件可被多条消息引用（编辑与重新生成沿用）。

## 5. 上传状态机

```text
选中 ──→ uploading ──→ done(serverId)
              │
              └──→ error(retryable) ──重试──→ uploading
              │
              └──→ error(not retryable)（过大、格式、解析失败；只能移除）
移除 → 丢弃任务结果（迟到的成功只更新任务表，不再展示）
```

- 选中即上传；单附件同一时刻只允许一个任务在跑。
- 并发上限 3，其余排队；排队中被移除的任务不发出请求。
- 发送闸门：文本 trim 非空或附件非空，且所有附件 `done`；否则发送按钮禁用。
- 发送前补传：本轮提问与进入上下文的历史轮次中 `serverId` 为空的附件。
  - 本轮：并行补传，任一失败则请求不发出，回复记 `upload` 错误并保留可重试标记。
  - 历史：从最新往前逐张补传，失败静默跳过（本次请求不带该附件）。
  - 补传成功把 `serverId` 写回所有引用同一附件的消息。
- `serverId` 被服务端判定失效（400 文案含 `file_ids do not exist`、
  `file data not found`、`invalid file_id`）：清空对应附件的 `serverId`，重新上传后重发；
  退避 1 s、2 s，最多重试 2 次，已收到内容块则不重发。

## 6. 失败文案与重试

| 情况 | 附件上显示 | 可重试 |
| --- | --- | --- |
| 上传中 | 上传中... | — |
| 服务端繁忙（5xx） | 服务器繁忙 | 是 |
| 网络、429 | 上传失败 | 是 |
| 解析失败（图片损坏/过大、加密、无法识别） | 解析失败 | 否 |
| 文件数 / 存储配额上限 | 上传失败 + 底部提示（含上限数值与「删除文件」链接） | 否 |
| 其他 400 | 上传失败 | 否 |

- 可重试的失败在卡片或缩略图上显示刷新图标；不可重试的失败显示红色描边与原因。
- 配额提示用 SnackBar，动作「删除文件」外部打开
  `https://api-docs.deepseek.com/api/delete-file`。
- 回复级 `upload` 错误在回复下方展示原因与「重试」入口；重试重新补传并请求。

## 7. UI

- 输入区附件条在文本框上方：
  - 图片 64×64 缩略图，上传中蒙层转圈，失败红描边 + 中心刷新图标。
  - 文档卡片：文件图标、文件名、`扩展名 + 大小`；上传中/失败时第二行换成状态文案。
  - 每个附件右上角移除按钮。
- 消息里的附件：图片缩略图（纯图片 120×120，与文档混排 64×64），点击全屏查看；
  文档卡片只展示文件名、扩展名与大小，不做应用内预览（外部打开需平台共享配置，v1 不做）。
  原件缺失的图片显示占位图标，文档卡片显示「原件已丢失」。
- 发送按钮：有内容且附件全部 `done` 时可用；无文字、仅有附件也可以发送。
- 界面文案新增中英文 ARB 条目；服务端原文不直接展示。

## 8. 与其它票的边界

- 导出导入（票 17）：只导出有原件的图片，文档只导出元数据（`data-model.md` §6）。
- 内容安全与图片审核（票 14）：在服务端错误与拒答层面处理，不在本票范围。
- 全量双语与主题（票 18）：本票只新增附件相关文案，其余界面文案仍由票 18 收口。
- 界面规格（票 10）：本票按现有临时 UI 追加控件，视觉细节待票 10 固化。
