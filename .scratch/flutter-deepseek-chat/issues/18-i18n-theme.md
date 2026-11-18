# 中英双语与浅深主题

Type: grilling
Status: resolved
Blocked by: 07

## Question

1. i18n 框架：flutter_localizations + ARB vs slang vs easy_localization；代码生成与测试。
2. 文案范围：界面文案、错误文案、空态、系统提示；DeepSeek 服务端模板文案是否翻译。
3. 语言切换：设置页入口、即时生效、默认跟随系统；与用户元信息票的模型语言关系。
4. 主题：浅色 / 深色 / 跟随系统；shadcn_ui token；代码高亮、Mermaid、KaTeX 的主题适配。
5. 中文排版：字体、行高、标点挤压；英文断行。
6. 持久化与首屏闪烁；状态栏 / 导航栏样式。
7. 验收：中英 × 浅深四组合的截图清单。

产出：`i18n-theme.md` 章节 + 文案清单结构 + 四组合验收表。

## Answer

结论写入 [`i18n-theme.md`](../i18n-theme.md)，实现在 `lib/app/`、`lib/l10n/` 与
`lib/shared/prefs/theme_store.dart`。要点：

1. **框架**：沿用官方 `gen_l10n` + ARB，模板 `app_en.arb`、中文 `app_zh.arb`，生成物入库；不引入第三方 i18n 包。
2. **文案范围**：全部客户端可见文案（含错误、空态、时间线、确认框）进 ARB；模型正文与服务端错误原文不翻译；冻结的拒答 / 审核文案保留中英双语副本；品牌名与 `DeepSeek API Key` 保持字面量。
3. **语言切换**：设置页下拉，立即生效；只存 `user.locale`，界面与元信息共用一个语言；已生成回复不改写；无第二个「模型语言」。
4. **主题**：浅色 / 深色 / 跟随系统，默认跟随系统，存 `ui.themeMode`；浅深两套由种子 `#4D6BFE` 生成；代码高亮、Mermaid、KaTeX 均随亮度适配；shadcn_ui 接入时用同一种子构建，不维护第二套色表。
5. **中文排版**：系统字体，中文正文行高 1.6、英文 Material 默认；v1 不做标点挤压。
6. **首帧与系统栏**：`SharedPreferences` 在 `runApp` 前读取，无闪烁；状态栏图标随 AppBar 亮度切换，导航栏用系统默认。
7. **验收**：中英 × 浅深四组合逐页检查清单见文档 §6；本轮未采集截图。
