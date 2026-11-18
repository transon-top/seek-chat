# 历史对话导入与导出

票 17 的决策。行为契约以 `https://github.com/deepseek-ai/chat-demo/tree/main/src/services/chat/history/` 为准；
本文记录移动端的格式对齐、覆盖导入、失败一致性与内存取舍。
术语见根目录 [`GLOSSARY.md`](../../GLOSSARY.md)，数据表见 [`data-model.md`](data-model.md)。

## 1. 选型与产物

- 格式：沿用 chat-demo 的 `export_format_version = 3`，条目名、字段名与校验规则一致。
- 文件名：`deepseek_data-YYYY-MM-DD.zip`（本地日期）。
- ZIP：Dart 包 `archive` 3.6.1，导出全部使用 STORE（不压缩），读取接受 STORE / DEFLATE。
  单卷 ZIP32；不支持 ZIP64、加密、分卷。
- 读写都在内存中完成；v1 不实现流式 ZIP（见 §7 上限）。
- 文件选择与保存：只用 `file_picker`。
  - 导入：`pickFiles(type: custom, allowedExtensions: ['zip'])`。
  - 导出：`saveFile(fileName, bytes, mimeType: 'application/zip')`，交给系统文档提供器。
  - 不引入 `share_plus`；v1 没有分享面板。

## 2. 归档结构

导出按以下顺序写入；导入也接受「会话 JSON 与图片交错、索引在末尾」的顺序。

| 顺序 | 条目 | 说明 |
| --- | --- | --- |
| 1 | `manifest.json` | `{"export_format_version":3}`，必须是首个条目 |
| 2 | `chat_sessions/{session_id}.json` | 每个会话一份，含完整消息树 |
| 3 | `chat_session_index.json` | 会话索引，与会话文件一一对应 |
| 4 | `chat_sessions/{session_id}_files/{file_id}_{file_name}` | 图片原件，每个会话目录各写一份 |

- 不写 `user.json`；导入时允许它出现在 manifest 与第一个会话之间并跳过。
- 图片条目名对 id 与文件名做安全化：`/`、`\` 换成 `_`，空值、`.`、`..` 换成 `unnamed`。
- 未引用的图片条目跳过；被引用但缺失的图片只保留附件元数据。
- 会话 id 不能含路径分隔符；消息 id 是会话内自增整数，父消息 id 必须小于子消息 id。

## 3. 内容范围

| 内容 | 导出 | 导入 |
| --- | --- | --- |
| 会话标题、插入与更新时间 | 是；空标题写 `null` | 是 |
| 完整消息树（全部分支） | 是 | 是 |
| 当前分支 | `current_message_id` 指向可见路径末尾；空会话写 `0` | 还原为该会话的选中链 |
| 思考块 | 正文 + `elapsed_secs` | 正文 + `elapsedSeconds`；没有起止时间 |
| 模板文本 | `TEMPLATE_RESPONSE` | `TextBlock.isTemplate` |
| 搜索 / 打开网页 / 页内查找 / 阅读链接 | 对应片段；阅读链接带签名、URL、标题 | 还原为工具块；搜索与打开网页不带原调用 ID，按位置生成 |
| 图片原件 | 只导出有本地原件的图片 | 有原件时写入 `attachments/<新 id>` 并补 MIME；无原件时 `local_path = NULL` |
| 文档等非图片附件 | 只有元数据，`export_path = null` | 只有元数据，不进入请求 |
| 附件引用关系 | 是 | 是；附件 id 一律换成新的本地 id，避免覆盖旧原件 |
| API Key、设置、草稿、`serverId` | 否 | 保留本机设置与 Key，不导入归档内任何设置 |

导出时按以下规则丢弃归档无法表达的字段，与 chat-demo 一致：

- 模型名、思考签名、工具调用 ID、结构化错误（类型/状态码/重试）、用量明细；
- 正文引用角标（`citations`）、非图片附件原件、`latest_reminder` 快照；
- 非当前分支的节点选择。

数据模型保留这些字段供展示与请求使用，只是不写进 ZIP；再次导入后按当前设置与默认值重建。

### 3.1 状态映射

| 本地状态 | 归档状态 | 导入后的本地状态 |
| --- | --- | --- |
| `done` + `stopReason = refusal` | `CONTENT_FILTER` | `done` + `stopReason = refusal`，丢弃思考与普通正文，保留工具块 |
| `done` + `stopReason = max_tokens` | `INCOMPLETE` | `stopped`（归档无法区分 `max_tokens` 与用户停止） |
| `done` 其他 | `FINISHED` | `done` |
| `stopped` | `INCOMPLETE` | `stopped` |
| `error` | `FAILED` | `error`（无 `error` 字段，正文来自导出时的模板文案） |
| `pending` / `streaming` | `WIP` | `stopped` |

- 导出与导入前，残留的 `pending` / `streaming` 按 `stopped` 处理（`data-model.md` §4）。
- 所有导入的 assistant 回复 `prefix = false`，不能续写；模板回复与工具块回复本来也不能续写。
- 错误与拒绝提示：导出时若回复没有模板文本，按导出时的界面语言写入
  `TEMPLATE_RESPONSE`；正常空回复与 `max_tokens` 不补造提示。重复导出不会重复追加。

## 4. 导入校验

校验顺序与失败后果：

1. 文件不是 ZIP、首个条目不是 `manifest.json`、条目名不安全或重复 → `unrecognized`。
2. `export_format_version > 3` → `newerVersion`；不等于 3 → `invalidVersion`。
3. ZIP 结构损坏或 CRC 不符 → `unrecognized`；JSON 解析失败 → `invalidJson`。
4. 容器与元数据字段不合法、索引与会话文件不一一对应 → `incomplete`。
5. 消息树损坏（重复 id、父节点缺失或更大、角色不交替、根不是提问、`current_message_id` 不存在）→ `invalidBranches`。
6. 图片路径落在会话目录外、同一条目对应不同附件 → `invalidFiles`。
7. 超过大小上限 → `tooLarge`（见 §7）。

- 单个内容片段不合法时只丢弃该片段；容器、元数据和消息树仍严格校验。
- 附件 id 含路径分隔符、`.`、`..` 或盘符时整包失败（`invalidFiles`）：id 会参与本地路径，不能按可丢弃片段处理。
- 未知片段类型（`TIP`、`CONTENT_RISK`、`PARTIAL_FILE_READ`、`TOOL_IMAGE_SEARCH` 等）直接丢弃，不显示占位。
- 校验失败不停止正在生成的回复，也不改动现有数据。
- 界面按上面的错误码显示对应文案；未归类的异常显示通用导入失败文案。

## 5. 覆盖导入状态机

```text
idle
  │ 选择文件
  ▼
confirm ──取消──→ idle
  │ 确认
  ▼
validate（解码 + 全部校验，内存中完成）
  │ 失败 ──→ failed（数据与生成状态不变）──→ idle
  ▼
stop（停止全部活动会话的生成）
  ▼
writeFiles（图片按新附件 id 写入 attachments/<新 id>，先写文件）
  │ 失败 ──→ failed（数据库未改；新文件成为启动清理的孤儿）
  ▼
replace（单事务清空 sessions/messages/attachments，再写入归档内容）
  │ 失败 ──→ failed（事务回滚，旧数据保留；新文件由启动清理回收）
  ▼
done（删除旧附件原件，返回导入会话数）──→ idle
```

- 覆盖范围：`sessions`、`messages`、`attachments`、`message_attachments` 全部替换。
- 保留范围：`shared_preferences` 中的全部设置、安全存储中的 API Key、正在上传的草稿任务表。
- 不自动备份旧历史：确认框明确提示会覆盖，并建议先导出。旧数据在事务提交前始终可回滚。
- 导入的附件 id 全部重新生成；旧原件因此不会被覆盖。失败时新文件成为孤儿，由启动清理回收。
- 提交后旧附件原件按引用删除；删除失败不回滚数据库，启动孤儿清理会再试。
- 导入期间用不可关闭的进度框阻止再次发起导入 / 导出；聊天页仍可浏览，但生成已停止。
- v1 不提供中途取消：上限保证操作时间可控，事务保证失败一致性。

## 6. 导出状态机

```text
idle
  │ 点击导出
  ▼
snapshot（记录导出开始时的会话列表）
  ▼
read（逐会话读数据库与图片原件；会话在读取中消失则整次失败）
  ▼
encode（内存中生成 ZIP）
  ▼
save（系统保存面板；用户取消则结束）
  ▼
done
```

- 导出期间的列表与标题使用开始时的快照；不写界面详情缓存。
- 没有图片原件的图片只导出元数据；文档附件从不写原件。
- 导出不修改数据库。

## 7. 大小上限与内存

ZIP 读写整包驻留内存（`archive` 包的限制）。为避免移动端被大包拖垮：

| 项 | 上限 |
| --- | --- |
| 导入 ZIP 文件 | 256 MiB |
| 单个 JSON 条目 | 32 MiB |
| 单个图片条目 | 64 MiB |
| 全部条目解压后总量 | 512 MiB |

- 超限直接失败并提示「文件过大」，不进入覆盖流程。
- 导出在编码完成后按 ZIP 字节数检查 256 MiB 上限。
- `shortcut: 整包驻留内存，命中上限后再改为流式 ZIP`。

## 8. 界面与文案

- 设置页新增「数据管理」：导入历史对话、导出所有历史对话两行；导入带确认框。
- 入口由 `app/` 注入 `HistorySection(stopGeneration: …)`，设置页不直接 import 功能目录。
- 新增 ARB 键：`settingsData`、`historyImport*`、`historyExport*`、`historyError*`。
- 导入成功提示会话数；导出成功提示已保存；取消保存或选择文件不提示错误。

## 9. 测试接缝

1. `features/history/history_zip.dart`：ZIP 字节 ↔ 领域对象，覆盖格式、字段映射、校验与错误码。
2. `ChatRepository.replaceAllHistory`：单事务整体替换、旧附件返回与空历史。
3. `HistoryService`：内存库 + 临时目录的端到端导出后再导入、图片原件、失败不改数据。
4. `HistorySection`：假文件选择器，覆盖确认、进度、成功与错误提示。

真实系统文件选择器与保存面板留手动验证，不进默认测试套件。

## 10. 不做

- 旧版归档迁移（只支持格式版本 3）。
- 导入包内设置、API Key 或草稿。
- 自动备份、增量合并、按会话导入导出、分享面板。
- ZIP64、加密、分卷与流式解压。
