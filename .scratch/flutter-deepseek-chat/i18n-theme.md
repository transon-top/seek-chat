# 中英双语与浅深主题

票：`18-i18n-theme`。架构约束见 [`architecture.md`](architecture.md) §9；语言与元信息的
关系见 [`user-metadata.md`](user-metadata.md)；文案键落在 `lib/l10n/app_en.arb`
（模板）与 `lib/l10n/app_zh.arb`，生成物在 `lib/l10n/generated/` 并入库。

- 关联：主题种子与设置项见 [`architecture.md`](architecture.md) §6、§9；渲染栈的
  主题适配见 [`markdown.md`](markdown.md)。
- 交接：设置页版式与控件外观 → 票 10 / 20；v1 验收映射 → 票 19。

## 1. 决策摘要

| 主题 | 决策 |
| --- | --- |
| i18n 框架 | 官方 `gen_l10n` + ARB；不引入 slang / easy_localization |
| 支持语言 | 仅 `zh`、`en`；其他系统语言回退英文 |
| 默认语言 | 首次启动跟随系统：系统语言以 `zh` 开头为中文，否则英文 |
| 语言切换 | 设置页入口，立即生效；持久化 `user.locale`；不设第二个「模型语言」 |
| 已生成内容 | 不随语言切换重写；回复使用各自快照（票 16） |
| 文案范围 | 全部客户端可见文案；服务端返回的模型正文不翻译 |
| 主题 | 浅色 / 深色 / 跟随系统，默认跟随系统；持久化 `ui.themeMode` |
| 主题来源 | 同一个种子 `#4D6BFE` 生成浅深两套 Material 主题 |
| shadcn_ui | 尚未引入页面；接入 `ShadApp` 时用同一种子构建 `ShadThemeData` |
| 首帧 | `SharedPreferences` 在 `runApp` 前同步读取，无语言 / 主题闪烁 |
| 中文排版 | 系统字体；正文行高 1.6；v1 不做标点挤压 |
| 状态栏 | 图标亮度随 AppBar 底色切换；导航栏沿用系统默认 |

## 2. i18n 框架与文案范围

### 2.1 框架

- 模板为 `app_en.arb`，中文为 `app_zh.arb`；`l10n.yaml` 固定 ARB 目录、输出目录与
  `AppLocalizations` 类名。
- 委托在 `lib/app/localization.dart` 统一导出；Material 委托来自 `material_ui`，
  不能换成 `flutter_localizations` 的实现（两套 `MaterialLocalizations` 不兼容）。
- 生成物入库，构建不依赖额外的代码生成步骤；生成文件带
  `ignore_for_file: deprecated_member_use`，无需修复模板引用。
- 测试用固定 `Locale('zh')` / `Locale('en')` 的 widget 测试覆盖，不依赖宿主语言。

### 2.2 文案范围

| 类别 | 是否翻译 | 说明 |
| --- | --- | --- |
| 界面文案、按钮、工具提示 | 是 | 含空态、确认弹窗、进度与错误横幅 |
| 客户端错误映射 | 是 | `error_text.dart` 与服务端条件映射为 ARB 键 |
| 模板拒答 / 图片审核文案 | 是 | 服务端模板在客户端有对应 ARB 文案，按模板 ID 选择 |
| 模型正文、思考内容、搜索摘要 | 否 | 原样展示；语言由请求时的用户语言影响，不做后处理 |
| 服务端错误 `message` | 否 | release 不展示；debug 仅显示原文，见架构 §5 |
| 品牌名 `Open Chat`、`DeepSeek API Key` | 否 | 两种语言一致，保留字面量 |
| 星期、语言名、所在地名 | 是 | 按应用语言生成 `latest_reminder`（票 16） |

## 3. 文案清单结构

ARB 键按界面区域分组，新增文案必须同时补 `en` / `zh`：

| 前缀 | 范围 | 示例 |
| --- | --- | --- |
| `settings*` | 设置页：标题、主题、语言、所在地、语音、数据管理 | `settingsTheme` |
| `voiceInput*` / `tts*` | 语音输入与朗读：按钮、状态、错误 | `voiceInputFailed` |
| `apiError*` / `error*` / `reply*` | 请求与回复错误 | `apiErrorRateLimited` |
| `upload*` | 附件选择、大小 / 数量、上传状态、配额 | `uploadMaxFiles` |
| `history*` | 导入导出、确认、错误码 | `historyImportConfirm` |
| `newChat` / `rename*` / `delete*` / `noSessions` | 会话列表 | `deleteSessionConfirm` |
| `regenerate` / `continueGeneration` / `chatEmpty` | 聊天操作与空态 | `chatEmpty` |
| `deep*` / `search*` / `thinking` / `reading` / `stop*` / `find*` / `browse*` | 思考与搜索时间线 | `searchedPages` |
| `composerHint` / `send` / `stop` / `smartSearch` | 输入区 | `smartSearch` |

规则：

- 占位符一律声明在模板 `@key.placeholders`；英文计数用 ICU plural，中文用单一形式。
- 冻结文案（拒答、审核）允许中文标点与固定措辞；普通界面文案用中性、无缩写的短句。
- 新增文案不得硬编码在 widget 中；`Text('...')` 只允许品牌名、符号与纯数据。
- 中英长度差异按控件最大行数与省略处理，不依赖固定宽度。

## 4. 语言切换

- 设置页「语言」下拉与所在地同区；选择后立即重建 `MaterialApp.locale`，当前页面
  文案同步刷新。
- 语言只存 `user.locale`；界面语言与 `latest_reminder` 的「语言」共用这一个值。
- 切换只影响之后的请求；历史消息、已生成回复、错误快照不改写。
- 未选择时跟随系统；系统语言不是中文时使用英文。非法存量按默认值处理。

## 5. 主题

### 5.1 三档与持久化

- `ThemeMode.system`（默认）/ `light` / `dark`，存 `shared_preferences` 的
  `ui.themeMode`，取值 `system|light|dark`；非法值回退 `system`。
- 设置页「主题」下拉切换后立即生效，`MaterialApp.themeMode` 直接跟随 Provider。
- 偏好与语言一样在 `main()` 中同步读取，首帧即为最终主题；不引入启动占位页。

### 5.2 颜色与组件 token

- 浅深两套均由 `ThemeData(colorSchemeSeed: #4D6BFE, brightness: ...)` 生成；
  页面统一使用 `Theme.of(context).colorScheme`，不写死颜色。
- 原型里的 shadcn 中性色板仅用于原型；正式接入 `shadcn_ui` 时由同一种子构建
  `ShadThemeData`，不维护第二套色表。
- 代码高亮随 `Theme.brightness` 在 `gpt_markdown` 内置浅 / 深色板间切换。
- Mermaid 按亮度使用 `MermaidTheme.defaultTheme` / `darkTheme`。
- KaTeX 公式继承正文 `onSurface` 颜色，无需单独换色。

### 5.3 中文排版

- 使用平台系统字体（iOS PingFang SC、Android 系统中文无衬线），不打包字体。
- 中文界面的 `bodyLarge` / `bodyMedium` / `bodySmall` 行高 1.6；英文保持 Material 3
  默认行高。
- v1 不做标点挤压、不调字距；英文按默认断行规则，不强制断词。

### 5.4 状态栏与导航栏

- `AppBarTheme.systemOverlayStyle` 按亮度设为 `dark` / `light`，保证状态栏图标可读。
- 导航栏沿用系统默认；v1 不启用 edge-to-edge 特殊配色。

## 6. 验收：中英 × 浅深四组合

每格都应在真机或模拟器上检查；截图存入票 09 同级的 evidence 目录（本轮未采集）。

| 组合 | 主界面 | 聊天页 | 设置页 |
| --- | --- | --- | --- |
| 中文 · 浅色 | 空态、会话列表、菜单 | 空态、流式、思考 / 搜索时间线、来源抽屉 | 标题、主题 / 语言 / 所在地、Key 操作、数据管理 |
| 中文 · 深色 | 同上，颜色与对比度正确 | 同上，代码块与 Mermaid 为深色板 | 同上 |
| 英文 · 浅色 | `No chats yet`、`New chat`、`Rename` / `Delete` | `Send a message…`、`Searching…`、`Read N pages` | `Settings`、`Theme`、`Save and verify` |
| 英文 · 深色 | 同上，颜色与对比度正确 | 同上，代码块与 Mermaid 为深色板 | 同上 |

逐项检查：

1. 切换语言后当前页面立即刷新；返回再进入仍保持。
2. 切换主题后当前页面立即刷新；重启后保持；系统主题变化时「跟随系统」跟随。
3. 首次启动无语言 / 主题闪烁；系统为英文时首屏即英文。
4. 中英文计数、占位符与复数形式正确；无硬编码中文残留。
5. 深色下正文、次要文字、边框、错误色对比度可读；状态栏图标清晰。
6. 已生成回复在切换语言后内容不变。

## 7. 实现落点

| 位置 | 内容 |
| --- | --- |
| `lib/l10n/app_en.arb` / `app_zh.arb` | 全部界面文案与占位符声明 |
| `lib/app/localization.dart` | 本地化委托 |
| `lib/app/theme.dart` | 种子、中文行高、状态栏样式 |
| `lib/shared/prefs/theme_store.dart` | `ui.themeMode` 持久化与 `themeModeProvider` |
| `lib/shared/prefs/user_metadata_store.dart` | `user.locale` 与默认值 |
| `lib/app/app.dart` | `MaterialApp.locale` / `themeMode` 接线 |
| `lib/features/settings/settings_page.dart` | 主题与语言入口 |
| `lib/features/chat/`、`lib/features/sessions/` | 全量文案改用 ARB |

## 8. 测试

- 主题构建：浅深亮度、状态栏图标亮度、中文正文行高。
- 主题存储：默认跟随系统、持久化与重载、非法值回退。
- 设置页：主题切换落盘、语言切换落盘、英文界面关键文案。
- 应用壳：保存的主题在首帧生效；主题与语言切换立即刷新；中英 × 浅深四组合
  中的中文浅色、中文深色、英文浅色、英文深色均有 widget 测试覆盖。
- 现有聊天 / 设置 / 会话 widget 测试继续以中文文案断言，防止文案回退。
