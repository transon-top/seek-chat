# 应用架构与项目结构

Type: grilling
Status: resolved
Blocked by: 06

## Question

锁定 Flutter 项目的模块边界与分层：

1. 目录结构：feature-first（chat / search / attachments / speech / settings / history）还是 layer-first；`lib/` 下具体树。
2. Riverpod 分层：Provider / Notifier / Repository / DataSource 的职责；流式回复用 StreamProvider 还是 Notifier 手动管理。
3. 并发：同一会话只能有一个进行中的回复；切换会话时后台流是否继续；App 进入后台 / 被杀的处理；语音录制与播放的互斥。
4. 错误处理：统一 `ApiFailure` 类型、UI 错误映射、日志。
5. 依赖注入与配置：API origin、默认模型、搜索开关、Feature flag。
6. 安全：`flutter_secure_storage` 封装；Key 不落日志、不进备份、不进导出。
7. i18n 架构：中英双语的资源组织与代码生成接入点（具体行为见双语票）。
8. 测试边界：单测（协议解析、状态合并、归档读写）、widget 测试、集成测试各自覆盖什么；质量门槛。
9. 代码生成：freezed / json_serializable / drift 生成链与 CI 命令。

产出：架构章节 + 目录树 + 依赖清单（含版本策略）。

## Answer

架构与目录树写入 [`docs/architecture.md`](../../../docs/architecture.md)，逐轮确认的决策摘要：

1. **目录**：功能优先 `features/`（chat、sessions、settings、attachments、search、speech、history）+ `shared/`（api、data、models、prefs）+ `app/` + `l10n/`；依赖方向 `features → shared`。
2. **状态管理**：`flutter_riverpod` 3.5，手写 Provider；基础设施用同步 Provider；会话列表用 `StreamProvider` + drift `watchSessions()`；聊天用 `NotifierProvider.autoDispose.family(sessionId)`，流式期间 `keepAlive`。路由沿用 `Navigator` 1.0。
3. **并发**：全局单流；离开聊天页继续；App 暂停时补写、被杀后启动置 `stopped`；录音与朗读互斥（票 21 细化）。
4. **数据层**：`AppDatabase` 即数据源，`ChatRepository` 封装事务，不另设 DataSource 层。
5. **错误**：统一 `ApiException`，按 `ApiErrorCondition` 映射本地化文案；服务端原文仅 debug；日志仅 `kDebugMode`，不记录 Key、请求头与请求体。
6. **配置**：API origin 走 `--dart-define`；模型固定 `deepseek-flash`；无 Feature flag / 远程配置。设置对齐 `chat-demo`（语言、主题、所在地、音色、思考、搜索、侧栏），用 `shared_preferences` 持久化。
7. **安全**：iOS `first_unlock_this_device`；Android 默认密码套件、不启用生物识别；Android `allowBackup="false"`；Key 不进库、日志、导出与备份；401 不清 Key。
8. **UI**：目标 `shadcn_ui` 0.60.x，现有页面在票 09 / 10 前保持 `material_ui`。
9. **i18n**：`gen_l10n` + ARB（`lib/l10n`），生成物入库；语言与主题状态由设置票定稿。
10. **测试**：单元 / widget / 平台集成三层；门槛为 `flutter analyze` + `flutter test`，不设覆盖率百分比。
11. **代码生成**：仅 drift 与 gen_l10n；不引入 freezed / json_serializable；生成物入库；暂不加 CI。
