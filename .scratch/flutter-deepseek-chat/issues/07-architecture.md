# 应用架构与项目结构

Type: grilling
Status: open
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
