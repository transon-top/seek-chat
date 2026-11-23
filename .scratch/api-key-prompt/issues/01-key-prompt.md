# 无 API Key 提示条与发送直达设置

Type: task
Status: open

## Question

按 [`spec.md`](../spec.md) 实现无 Key 提示：

1. **状态**：新增 `hasApiKeyProvider`（`trim()` 后非空），设置保存 / 清除后
   invalidate；读取失败按无 Key；首帧读取完成前按有 Key 渲染。
2. **提示条**：无 Key 时输入卡上方常驻浅警示底色条（图标 + 说明 + 「去填写」），
   整条可点、不可关闭、有 Key 自动消失；文案 `keyPromptMessage` /
   `keyPromptAction`，中英同步。
3. **发送**：无 Key 点发送改为打开设置 Sheet（落在「数据管理」页、聚焦 Key 输入框），
   不弹 toast、保留草稿、返回后不自动发送；`_send` 守卫保留。
4. **设置**：`showSettingsSheet` 增加初始视图与聚焦参数；抽屉入口仍默认「通用」。
5. **其余入口**：麦克风、`+` 附件、朗读、重新生成 / 续写 / 编辑提交 / 上传重试
   行为不变，沿用现有 `errorNoApiKey` 提示。
6. **测试**：更新 `test/app/app_test.dart` 的无 Key 发送用例；补提示条显隐、
   点击跳转、保存 / 清除后实时更新用例。

预期落点：

- `lib/shared/providers.dart`
- `lib/features/chat/composer.dart`
- `lib/features/chat/chat_page.dart`
- `lib/features/settings/settings_page.dart`
- `lib/app/app.dart`
- `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`（+ `flutter gen-l10n`）
- `test/app/app_test.dart`、`test/features/settings/settings_page_test.dart`

## 验收

- `flutter analyze` 无问题。
- `flutter test` 全绿，覆盖 `spec.md` §8。
- 双主题、中英文、字号 0.8–2.0 手动检查提示条与跳转。
