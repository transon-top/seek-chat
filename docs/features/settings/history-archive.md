# 历史导入导出

状态：已实现 · 最后核对：2026-11-23
适用：SeekChat `0.5.0+1` · 数据库 `schemaVersion 2` · 归档格式 `3`

## 1. 范围与入口

会话历史的 ZIP 归档导入与导出，以及「删除所有对话」。
归档格式与 chat-demo 的 `export_format_version = 3` 对齐。

入口：设置路由 →「数据管理」子页：

- 导入历史对话；
- 导出所有历史对话；
- 删除所有对话。

## 2. 行为与状态

### 2.1 归档产物

- 文件名：`deepseek_data-YYYY-MM-DD.zip`，使用本地日期。
- 格式：单卷 ZIP32；导出全部使用 STORE（不压缩），导入接受 STORE / DEFLATE。
- 不支持 ZIP64、加密、分卷与流式 ZIP；读写整包驻留内存。
- 条目顺序：

| 顺序 | 条目 | 说明 |
| --- | --- | --- |
| 1 | `manifest.json` | `{"export_format_version":3}`，必须是首个条目 |
| 2 | `chat_sessions/{session_id}.json` | 每个会话一份，含完整消息树 |
| 3 | `chat_session_index.json` | 会话索引，与会话文件一一对应 |
| 4 | `chat_sessions/{session_id}_files/{file_id}_{file_name}` | 图片原件 |

- 不写 `user.json`；导入允许它出现在 manifest 与第一个会话之间并跳过。
- 图片条目名对 id 与文件名做安全化：路径分隔符替换，空值、`.`、`..` 替换为
  `unnamed`。
- 未引用的图片条目跳过；被引用但缺失的图片只保留附件元数据。
- 会话 id 不能含路径分隔符；消息 id 是会话内自增整数，父消息 id 必须小于子消息 id。

### 2.2 导出范围

| 内容 | 导出行为 |
| --- | --- |
| 会话标题、插入与更新时间 | 是；空标题写 `null` |
| 完整消息树（全部分支） | 是 |
| 当前分支 | `current_message_id` 指向可见路径末尾；空会话写 `0` |
| 思考块 | 正文 + 耗时秒数 |
| 模板文本 | 导出为模板响应 |
| 搜索 / 打开网页 / 页内查找 / 阅读链接 | 对应片段；阅读链接带签名、URL、标题 |
| 图片原件 | 只导出有本地原件的图片 |
| 文档等非图片附件 | 只导出元数据，`export_path` 为 `null` |
| 附件引用关系 | 是 |
| API Key、设置、草稿、`serverId` | 否 |

导出时丢弃归档无法表达的字段：模型名、思考签名、工具调用 ID、结构化错误、
用量明细、正文引用角标、非图片附件原件、`latest_reminder` 快照、
非当前分支的节点选择。本地数据模型保留这些字段，只是不写入 ZIP。

### 2.3 状态映射

| 本地状态 | 归档状态 | 导入后的本地状态 |
| --- | --- | --- |
| `done` + `refusal` | `CONTENT_FILTER` | `done` + `refusal`，丢弃思考与普通正文，保留工具块 |
| `done` + `max_tokens` | `INCOMPLETE` | `stopped` |
| `done` 其他 | `FINISHED` | `done` |
| `stopped` | `INCOMPLETE` | `stopped` |
| `error` | `FAILED` | `error`，正文来自导出时的模板文案 |
| `pending` / `streaming` | `WIP` | `stopped` |

- 导出与导入前，残留的 `pending` / `streaming` 按 `stopped` 处理。
- 所有导入的 assistant 回复 `prefix = false`，不能续写。
- 错误与拒绝提示：导出时若回复没有模板文本，按导出时的界面语言写入提示；
  正常空回复与 `max_tokens` 不补造提示，重复导出不会重复追加。

### 2.4 导入校验

按顺序校验，失败即终止：

1. 文件不是 ZIP、首个条目不是 `manifest.json`、条目名不安全或重复 →
   `unrecognized`；
2. `export_format_version > 3` → `newerVersion`；不等于 3 → `invalidVersion`；
3. ZIP 结构损坏、CRC 不符或 JSON 解析失败 → `unrecognized` / `invalidJson`；
4. 容器与元数据字段不合法、索引与会话文件不一一对应 → `incomplete`；
5. 消息树损坏（重复 id、父节点缺失或更大、角色不交替、根不是提问、
   `current_message_id` 不存在）→ `invalidBranches`；
6. 图片路径落在会话目录外、同一条目对应不同附件 → `invalidFiles`；
7. 超过大小上限 → `tooLarge`。

- 单个内容片段不合法时只丢弃该片段；容器、元数据和消息树仍严格校验。
- 附件 id 含路径分隔符、`.`、`..` 或盘符时整包失败（`invalidFiles`）。
- 未知片段类型直接丢弃，不显示占位。
- 校验失败不停止正在生成的回复，也不改动现有数据。

### 2.5 覆盖导入流程

```text
idle
  → confirm（确认覆盖）
  → validate（解码 + 全部校验，内存中完成）
  → stop（停止全部活动会话的生成）
  → writeFiles（图片按新附件 id 写入本地）
  → replace（单事务清空并写入四表）
  → done
```

- 覆盖范围：`sessions`、`messages`、`attachments`、`message_attachments`
  全部替换。
- 保留范围：全部 `shared_preferences` 设置、安全存储中的 API Key、
  正在上传的草稿任务。
- 不自动备份旧历史；确认框明确提示会覆盖，并建议先导出。
- 校验失败或写文件失败：数据库未改，现有数据保留。
- 替换失败：事务回滚，旧数据保留；新写入的图片成为孤儿，由启动清理回收。
- 成功后删除旧附件原件；删除失败不回滚数据库，启动孤儿清理会再试。
- 导入期间显示不可关闭的进度框，阻止再次导入 / 导出；聊天页仍可浏览，
  但生成已停止。
- 导入不提供中途取消。

### 2.6 导出流程

```text
idle → snapshot（记录会话列表） → read（读数据库与图片原件）
     → encode（内存生成 ZIP） → save（系统保存面板） → done
```

- 导出期间使用开始时的会话快照；会话在读取中消失则整次失败。
- 没有图片原件的图片只导出元数据；文档附件从不写原件。
- 导出不修改数据库；用户取消保存则结束，不提示错误。

### 2.7 删除所有对话

- 先停止全部生成，再在单事务内清空会话、消息与附件关联。
- 提交后回收本地原件；远端 Files API 文件不删除。
- 成功提示「已删除全部对话」；设置与 API Key 保留。

## 3. 边界与错误

| 错误码 | 含义 |
| --- | --- |
| `unrecognized` | 不是可识别的 ZIP / 归档结构 |
| `newerVersion` | 归档版本高于当前支持版本 |
| `invalidVersion` | 归档版本不是 3 |
| `invalidJson` | 会话 JSON 解析失败 |
| `incomplete` | 索引、会话文件或元数据不完整 |
| `invalidBranches` | 消息树或当前分支不合法 |
| `invalidFiles` | 图片路径或附件映射不合法 |
| `tooLarge` | 超过大小上限 |

- 未归类异常显示通用导入失败文案。
- 导入失败不改动现有数据与生成状态。
- 用户取消文件选择或保存面板不提示错误。
- 导入成功后提示导入的会话数；导出成功后提示文件已保存。

## 4. 持久化与兼容性

| 项 | 上限 |
| --- | --- |
| 导入 ZIP 文件 | 256 MiB |
| 单个 JSON 条目 | 32 MiB |
| 单个图片条目 | 64 MiB |
| 全部条目解压后总量 | 512 MiB |

- 超限直接失败并提示「文件过大」，不进入覆盖流程。
- 导出在编码完成后按 ZIP 字节数检查 256 MiB 上限。
- 归档格式版本独立于数据库版本，当前为 3。
- 导入的附件 id 全部重新生成，避免覆盖旧原件。
- 数据库 `schemaVersion 2`；归档的 `pinned` 随会话文件往返，缺失按 `false`。
- 旧版应用导入新归档时忽略 `pinned`，会话回时间分组。
- 不支持旧版归档迁移（只支持格式 3）。

## 5. 已知限制

- 只支持格式版本 3；不迁移旧版归档。
- 不导入归档内的设置、API Key 或草稿。
- 不提供自动备份、增量合并、按会话导入导出或分享面板。
- 不支持 ZIP64、加密、分卷与流式解压；整包驻留内存。
- 导入不可中途取消；上限保证操作时间可控。
- 导出不包含文档原件，只含元数据。
- 远端 Files API 文件不随删除或覆盖导入删除。
- 导入后所有 assistant 回复不能续写。

## 6. 验证

- `test/features/history/history_zip_test.dart`：格式、字段映射、状态映射、
  校验错误码、`pinned` 与图片安全化。
- `test/features/history/history_service_test.dart`：导出后再导入、图片原件、
  覆盖导入、失败不改数据与大小上限。
- `test/features/history/history_section_test.dart`：确认框、进度、成功与错误提示、
  删除全部。
- `test/shared/data/chat_repository_test.dart`：单事务替换、旧附件返回与空历史。
- 真实系统文件选择器与保存面板需手动验证。

## 相关文档

- [会话抽屉](../sessions/session-drawer.md)
- [设置与用户元信息](settings-metadata.md)
- [聊天与回复](../chat/replies.md)
- [`GLOSSARY.md`](../../../GLOSSARY.md)：History Archive、Session、Attachment
