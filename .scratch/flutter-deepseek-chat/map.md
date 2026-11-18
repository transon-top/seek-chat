# Map: Flutter DeepSeek Chat

## Destination

一份决策完备、可直接交给实现会话执行的 Flutter DeepSeek Chat App **v1 规格**与**子版本实施计划**：iOS + Android，shadcn_ui 界面，行为契约以 chat-demo 为准。v1 验收标准为下列 10 项功能；实现不在本图内。

## Notes

- 行为契约：`~/ZoneCode/chat-demo`（React 18 + rspack 纯静态应用）。
- API：`https://api.deepseek.com` 的 Anthropic 兼容 Messages API（`/anthropic/v1/messages`，SSE），默认模型 `deepseek-flash`；Key 用 `x-api-key`，`GET /models` 校验。
- 平台：iOS + Android 首发；桌面/Web 不在本图。
- **v1 验收功能（截图原文）**：
  1. 联网搜索、深度思考搜索、阅读链接
  2. 上传图片与文档
  3. 模型内容安全，包括图片审核
  4. 会话标题，重命名与删除会话
  5. 编辑消息、重新生成、继续生成
  6. 朗读回答与语音输入
  7. 在设置中选择语言和所在地，作为用户元信息标记传给模型
  8. 导入与导出历史对话（导入会覆盖已有对话）
  9. Markdown 渲染，包括 Mermaid 图表
  10. 中文与英文界面，浅色与深色主题
- 隐含基础能力：流式回复、深度思考、多会话、API Key 设置、代码高亮、数学公式。
- 技术基线（研究未推翻前成立）：Riverpod、drift + SQLite、flutter_secure_storage、App 直连 API。
- 安全风险：移动端 BYOK 的 API Key 可被逆向提取，安全存储只能降低不能消除；v1 接受此风险，生产分发需后端代理。
- 本机工具链已就绪：Flutter 3.50.0 stable、Xcode 26.3、Android SDK 36 / NDK 28.2；验证细节见票 04。
- 每个会话开始先读 `GLOSSARY.md`（如存在）与 `docs/adr/`；按需调用 grilling、domain-modeling、research、prototype 技能。
- 用户提供的 Mermaid 包清单来自网络，真实性未验证；以 research 票结论为准。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [Markdown 渲染库方案调研](issues/01-markdown-rendering.md): 主选 `gpt_markdown` 1.4.1（分段缓存、内置数学/高亮），备选 `flutter_markdown_plus` + `flutter_markdown_stream`；`super_markdown` 不存在。
- [Mermaid 渲染方案调研](issues/03-mermaid-rendering.md): 用户清单 7 个包全部存在；主选 `mermaid_flutter` + `mermaid_core`（纯 Dart、28 种图、MIT），备选 WebView + mermaid.js 兜底。
- [数学公式渲染方案调研](issues/02-math-rendering.md): 主选 `val_latex_flutter` 0.1.4（与 `gpt_markdown` 内置数学同一引擎），备选 `katex` + `katex_dart`；`flutter_math_fork` 在 Flutter 3.29+ 构建失败。
- [语音输入与朗读方案调研](issues/15-speech-research.md): ASR/TTS 为 DeepSeek 官方 API；主选 `record` 7.2.0 + `flutter_soloud` 5.3.0，备选 `just_audio` / `flutter_sound`。
- [Flutter 工具链安装与构建验证](issues/04-flutter-toolchain.md): Flutter 3.50.0 stable + Xcode 26.3 + Android SDK 36 + NDK 28.2 已就绪；空项目在 iOS 26.3 与 Android API 37 模拟器均跑通；Gradle/NDK 下载需镜像加速。
- [API 协议与流式客户端契约](issues/05-api-protocol.md): 契约写入 [`api.md`](api.md)；锁定请求体/SSE 合并/错误分类/停止续写/分支上下文/自动标题；Dart 用 `package:http` 1.5+ `AbortableRequest` + 自写 WHATWG SSE 解析，不设客户端超时，v1 固定 `deepseek-flash`。
- [会话、消息与分支数据模型](issues/06-data-model.md): drift 四表 `sessions`/`messages`/`attachments`/`message_attachments`，块存 JSON；UUID 主键 + epoch 毫秒；流式不写库、状态迁移落盘；详见 [`data-model.md`](data-model.md)，术语见根目录 `GLOSSARY.md`。

## Not yet specified

- 子版本切分与每版验收边界（等「子版本计划」票）
- 搜索进度、引用抽屉与来源卡片的交互细节（等搜索票）
- 图片审核失败与拒答的用户提示（等内容安全票）
- 导入覆盖前的备份与回滚（等导入导出票）
- 语言切换是否即时生效、是否影响已生成内容（等双语票）
- 代码高亮 / Mermaid / KaTeX 的主题与深浅色对应（等渲染方案与界面规格）
- 附件在消息中的呈现、预览与删除（等附件票）
- 深度思考与搜索开关在输入区的呈现（等原型）

## Out of scope

- 草稿、会话分组、会话置顶
- 桌面 / Web 平台适配
- 应用商店签名与发布
- 云同步、多账号、跨设备
- 服务端代理（v1 直连 API）
