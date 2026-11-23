# 无 API Key 提示规格

状态：定稿（2026-11-23）。术语见根目录 [`GLOSSARY.md`](../../GLOSSARY.md) 的
「Key Prompt（API Key 提示条）」。

## 1. 范围

用户没有 API Key 时，让「缺 Key」这件事在聊天页可见、可一步解决：

1. 输入卡上方常驻 Key Prompt；有 Key 时不存在。
2. 点 Key Prompt 或点发送（无 Key）时，打开设置 Sheet 并直接落在「数据管理」页，
   聚焦 API Key 输入框。
3. 不禁用任何按钮；其余调用接口的入口沿用现有 `errorNoApiKey` 提示。

不在本规格：

- 开屏弹窗、引导页、首次启动流程。
- Key 有效性判定与 401 的专门提示。
- 任何按钮的禁用态。
- Key 输入、校验、保存、清除本身（沿用现有设置页逻辑）。

## 2. 状态判定

- 新增 `hasApiKeyProvider`（`lib/shared/providers.dart`），读取
  `apiKeyStoreProvider`，`trim()` 后非空即为有 Key。
- 不联网校验；401 继续由回复的 `apiErrorUnauthorized` 展示。
- 设置页保存或清除 Key 成功后 `ref.invalidate(hasApiKeyProvider)`，聊天页
  实时更新。
- 安全存储读取抛错按「无 Key」处理，仅写 debug 日志，不额外提示。
- 聊天页首帧读取完成前按「有 Key」渲染，避免提示条闪烁。

## 3. Key Prompt（提示条）

- 位置：输入卡外部上方、与输入卡同宽，间隔 8；位于输入卡与消息区之间，
  随输入卡一起贴底。
- 结构：左警示图标 + 中间说明文字 + 右侧「去填写」。整条可点击。
- 视觉：浅警示底色圆角条；文字最多两行，随字号缩放不裁切；不遮挡消息区。
- 不可关闭、不可滑动消失；只在有 Key 后消失。
- 读屏：整条暴露为按钮，标签包含说明文字与操作文字。
- 文案：

| ARB key | zh | en |
| --- | --- | --- |
| `keyPromptMessage` | 未设置 API Key，填写后即可开始对话 | No API key set. Add one to start chatting. |
| `keyPromptAction` | 去填写 | Add key |

## 4. 发送

- 有文本或附件时点发送且无 Key：打开设置 Sheet（见 §5），不发送、不弹 toast；
  输入内容与草稿附件原样保留。
- 从设置返回后不自动发送，需用户再次点发送。
- `_send` 原有的无 Key 守卫保留，作为兜底。
- 麦克风、`+` 附件、朗读、重新生成、续写、编辑提交、上传重试：行为不变，
  仍由现有 `errorNoApiKey` 提示。

## 5. 设置落点

- `showSettingsSheet` 新增参数：初始视图（通用 / 数据管理）与聚焦 Key 输入框。
- Key Prompt 与「无 Key 点发送」两条入口进入时：落在「数据管理」页，
  API Key 输入框自动聚焦。
- 保存成功不自动关闭 Sheet；提示条与按钮可用性随 `hasApiKeyProvider` 立即更新。
- 会话抽屉的设置入口不变，默认「通用」页。

## 6. 边界

- 流式回复进行中清除 Key：提示条立即出现，当前请求继续，不中断、不清空已收内容。
- Key 为空白字符串视同无 Key。
- Key 无效（401）不出现提示条。

## 7. 落点

- `lib/shared/providers.dart`：`hasApiKeyProvider`
- `lib/features/chat/composer.dart`：提示条（新增参数）
- `lib/features/chat/chat_page.dart`：订阅状态、发送直达设置、传入提示条
- `lib/features/settings/settings_page.dart`：初始视图 / 聚焦参数，
  保存与清除后 invalidate
- `lib/app/app.dart`：把「打开 Key 设置」回调接到 `ChatPage`
- `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`（+ `flutter gen-l10n`）

## 8. 自动化验收

- 无 Key：提示条出现；有 Key：提示条不存在；保存 / 清除后无需重进页面即变化。
- 点提示条：设置 Sheet 打开在「数据管理」页，Key 输入框有焦点。
- 无 Key 输入文本点发送：设置 Sheet 打开，文本保留，不创建会话。
- 有 Key 时发送行为不变。
- 现有 `tells the user to set a key when none is saved` 更新为「打开设置」断言。
- `flutter analyze` 无问题，`flutter test` 全绿。

## 9. 手动验收

- 浅色 / 深色、中文 / English、字号 0.8–2.0 下提示条不裁切、不遮挡。
- 流式中清 Key：提示条出现，回复继续。
