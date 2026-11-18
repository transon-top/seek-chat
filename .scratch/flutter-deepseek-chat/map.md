# Map: Flutter DeepSeek Chat

## Destination

一份决策完备、可直接交给实现会话执行的 Flutter DeepSeek Chat App **v1 规格**与**子版本实施计划**：iOS + Android，shadcn_ui 界面，行为契约以 chat-demo 为准。v1 验收标准为下列 10 项功能；实现不在本图内。

## Notes

- 行为契约：`https://github.com/deepseek-ai/chat-demo`（React 18 + rspack 纯静态应用）。
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
- [应用架构与项目结构](issues/07-architecture.md): 功能优先 + `shared` 核心；`flutter_riverpod` 3.5 手写 Provider，聊天用 family + `keepAlive`；每会话单流、跨会话可并行（对齐 `chat-demo`）；设置走 `shared_preferences`，Key 走安全存储；`shadcn_ui` 0.60.x 为目标组件库；详见 [`architecture.md`](architecture.md)。
- [Markdown / 数学 / Mermaid 方案锁定](issues/08-markdown-decision.md): `gpt_markdown` 1.4.1 + 内置 `val_latex_flutter` + `mermaid_flutter` 0.3.2；流式按帧耗时自适应节流（50 ms–2 s）；图片转链接不加载；单块超 200000 字符转纯文本；详见 [`markdown.md`](markdown.md)。
- [shadcn_ui 聊天界面原型](issues/09-ui-prototype.md): 可运行原型在 [`prototype/`](../../prototype/README.md)；确定抽屉会话列表、非气泡助手/气泡用户、思考块折叠、来源卡与引用角标、分支与操作条、底部圆角输入区；截图与场景见票内。原型中的正文下横向来源卡后续由票 12 改为「N 个网页」胶囊 + 底部抽屉。
- [联网搜索、阅读链接与引用角标](issues/12-web-search-links.md): 两开关独立持久化、默认关；视图由块纯函数推导；角标点击外开；来源改为「N 个网页」胶囊 + 底部抽屉（取代原型横向来源卡）；详见 [`search.md`](search.md)。
- [图片与文档上传](issues/13-attachments.md): `file_picker` 单一依赖，回形针 → 相册/文件面板；选中即上传（并发 3）、发送时复制原件；白名单 + 32/64 MB + 50 个；补传与失效重传对齐 `chat-demo`；详见 [`attachments.md`](attachments.md)。
- [内容安全与图片审核](issues/14-content-safety.md): 所有请求恒 `safety_check: high`；拒答丢弃思考与正文、模板 > 图片审核 > 通用文案、正文样式、禁用续写与重新生成；仅 `400 Content Exists Risk` 单独归类；详见 [`safety.md`](safety.md)。
- [用户元信息：语言与所在地](issues/16-user-metadata.md): 一个语言设置同时驱动界面与元信息；所在地选择器跟随系统语言，支持清除；快照在附件补齐后生成、续写复用；详见 [`user-metadata.md`](user-metadata.md)。
- [历史对话导入与导出](issues/17-history-import-export.md): 对齐 chat-demo 归档版本 3；`archive` 整包内存读写、256 MiB 上限；单事务覆盖导入，保留设置与 Key，不自动备份；详见 [`history.md`](history.md)。
- [中英双语与浅深主题](issues/18-i18n-theme.md): 官方 `gen_l10n` + ARB，全部客户端文案进 ARB，模型正文不翻译；语言已即时生效；主题三档存 `ui.themeMode`、首帧同步读取、浅深共用种子 `#4D6BFE`；详见 [`i18n-theme.md`](i18n-theme.md)。
- [设置、语言与数据管理界面原型](issues/20-settings-prototype.md): 单页分组（账户 / 对话 / 外观 / 语言与位置 / 语音 / 数据管理）；语言与位置用行内弹层，位置按系统语言变形并保留「不指定」；导入走选择 → 覆盖确认 → 不可关闭进度 → 行内成败；语音只留静态态；详见 [`prototype/settings/`](../../prototype/settings/README.md)。

## Not yet specified

- 子版本切分与每版验收边界（等「子版本计划」票）
- 渲染性能预算的真机基准：票 08 已定目标值（50 ms–2 s 节流、单帧 ≤ 16.7 ms、200 条消息流畅），待真机实测回填

## Out of scope

- 草稿、会话分组、会话置顶
- 桌面 / Web 平台适配
- 应用商店签名与发布
- 云同步、多账号、跨设备
- 服务端代理（v1 直连 API）
