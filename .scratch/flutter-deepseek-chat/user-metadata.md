# 用户元信息：语言与所在地

票：`16-user-metadata`。行为契约以 `https://github.com/deepseek-ai/chat-demo` 的
`services/chat/latestReminder.ts`、`services/location.ts`、`services/settings.ts` 与
`components/settings/SettingsDialog.tsx` 为准。插入位置与快照语义已由
[`api.md`](api.md) §3.3 锁定；本文锁定内容模板、设置交互与持久化。

- 关联：请求体与 `latest_reminder` 角色见 [`api.md`](api.md) §3.3；快照列与落盘时机见
  [`data-model.md`](data-model.md) §2、§4；术语见根目录 `GLOSSARY.md`。
- 交接：设置页分组与视觉细节 → 票 10 / 20；英文界面文案 → 票 18。

## 1. 决策摘要

| 主题 | 决策 |
| --- | --- |
| 字段 | 日期、星期、所在地、平台、语言五项，逗号连接 |
| 语言来源 | 一个语言设置同时驱动界面语言与元信息里的「语言」；不设第二个「模型语言」 |
| 语言默认值 | 首次启动跟随系统：系统语言以 `zh` 开头为中文，其余为英文；用户选择后持久化 |
| 位置默认值 | 未设置为空；元信息对应字段留空（保留逗号占位），不阻止发送 |
| 位置选择器 | 跟随**系统语言**而非应用语言：中文系统用省 / 市两级，其他系统用国家 / 地区列表 |
| 清除入口 | 省份 / 地区选择器提供「不指定」，选中即清空所在地；城市选择器的「不指定」退回省一级 |
| 平台标记 | `iOS` / `Android` 运行时判断；v1 无桌面 / Web |
| 快照时机 | 附件补齐成功、请求发出前生成并写入该 assistant 行；续写沿用原快照 |
| 隐私 | 只随同一条消息请求发给用户配置的 DeepSeek API；不申请定位权限、不采集设备位置 |
| 依赖 | 无新依赖；地区数据与名称静态内置于仓库 |

## 2. 内容模板

```
日期,星期,所在地,平台,语言
```

| 字段 | 取值 | 来源 |
| --- | --- | --- |
| 日期 | `YYYY-MM-DD`，设备本地时区；不转 UTC | chat-demo `utils/format.ts` |
| 星期 | 长名称，按应用语言：`星期三` / `Wednesday` | `latestReminder.ts` |
| 所在地 | 中文语言且为中国时取市 → 省 → `中国`；否则取地区名称；未设置为空 | `latestReminder.ts` `locationName` |
| 平台 | `iOS` 或 `Android` | 票 16 新增（Web → 原生） |
| 语言 | `中文` / `English`，按应用语言 | `i18n` `latestReminderLanguage` |

样例（2026-11-18 为星期三）：

```text
# 中文界面，浙江省杭州市，iOS
2026-11-18,星期三,杭州市,iOS,中文

# 中文界面，只选到省
2026-11-18,星期三,浙江省,Android,中文

# 中文界面，选中国但未选省市
2026-11-18,星期三,中国,Android,中文

# 英文界面，美国，即使曾选过中国省市也只发国家名
2026-11-18,Wednesday,United States,iOS,English
2026-11-18,Wednesday,China,iOS,English

# 中文界面，中国台湾（港澳台名称固定）
2026-11-18,星期三,中国台湾,iOS,中文

# 未设置所在地：空字段保留逗号
2026-11-18,星期三,,Android,中文
```

- 所在地名称按**应用语言**本地化（英文界面下中国为 `China`），与位置选择器使用的
  系统语言是两件事。
- 星期与语言名称只支持 `zh` / `en`；其他系统语言回退英文。

## 3. 设置与持久化

### 3.1 语言

- 存 `shared_preferences` 的 `user.locale`，取值 `system` / `zh` / `en`；缺失或非法值
  按 `system` 处理。`system` 按系统语言解析：以 `zh` 开头为中文，其余英文
  （`settings.ts` 的 `initialLocale`）。
- 选择后立即生效：界面语言（`MaterialApp.locale`）与之后创建的请求一起切换。
- 已生成的回复保留各自快照，切换语言不改写历史。

### 3.2 所在地

- 存 `shared_preferences` 的 `user.location`，JSON：`{"region":"CN","province":"330000",
  "city":"330100"}`。读取时按 chat-demo `normalizeLocation` 校验：地区必须在 ISO 列表
  内；中国可缺省省 / 市，有省必合法，有市必属于该省；非法数据整条丢弃。
- 选择器形态只看系统语言（chat-demo `isChineseBrowser`）：
  - 中文系统：省份 / 城市下拉，数据为 34 个省级行政区与下辖城市；
  - 其他系统：国家 / 地区下拉，`regionCodes` 全表，名称按应用语言显示并排序。
- 中文系统下的城市名称固定中文（与 chat-demo 相同）；只有元信息里的国家名跟随应用
  语言。
- 读取时按系统语言裁剪（chat-demo `initialLocation`）：中文系统丢弃非中国存量，
  其他系统只保留国家代码；裁剪只影响内存，不回写存储。
- 清除：省份 / 地区下拉的「不指定」清空整条所在地；城市下拉的「不指定」保留省、
  清掉市。chat-demo 无清除项，本票为满足「清除入口」补上。
- 未设置时不发定位、不弹权限；v1 不申请系统定位权限。

### 3.3 隐私

- 语言与所在地只存在本机，并随消息请求写入 `latest_reminder` 发给用户自己配置的
  DeepSeek API；不新增数据接收方，不与账号或设备标识关联。
- 设置页 v1 不单列隐私说明（与票 14 一致）；说明文案与位置由票 18 / 20 收口。
- 清除入口即 §3.2 的「不指定」；清除后下一轮快照该字段为空。

## 4. 请求注入与快照

插入位置、去重规则与历史回填已由 [`api.md`](api.md) §3.3 锁定；本文只补生成时机：

| 流程 | 快照 |
| --- | --- |
| 发送新提问 | 附件补齐成功后生成，写入新 assistant 行 |
| 重新生成 | 新生版本单独生成；旧版本快照不动 |
| 续写 | 沿用原回复快照；原快照为空则不插入 |
| 附件失效自动重传 | 同一次发送内重新生成并覆盖该行 |
| 上传失败后重试 | 请求尚未发出，重试时生成 |
| 编辑提问（后续实现） | 新回复单独生成 |
| 历史 / 导入数据 | 缺快照的轮次不插；不补写 |

- 生成发生在 `_ensureAttachments` 之后、`buildMessageRequest` 之前；落盘用
  `ChatRepository.setLatestReminder`，同时更新内存中的回复对象。
- 续写与「沿用快照」路径不重新生成，避免日期或设置变化改写已有上下文。
- 快照按行保存，因此同一分支中不同版本可以携带不同语言 / 所在地。

## 5. 实现落点

| 位置 | 内容 |
| --- | --- |
| `lib/shared/models/location.dart` | `UserLocation`、省市表、地区名称、`normalizeLocation` |
| `lib/shared/models/location_data.dart` | 由 chat-demo 数据与同源 CLDR 名称生成的静态表 |
| `lib/shared/models/latest_reminder.dart` | `buildLatestReminder` 纯函数 |
| `lib/shared/prefs/user_metadata_store.dart` | 持久化、默认值与 `userMetadataProvider` |
| `lib/features/settings/settings_page.dart` | 语言 / 所在地选择器（最小实现，版式待票 10 / 20） |
| `lib/app/app.dart` | `MaterialApp.locale` 跟随设置 |
| `lib/features/chat/chat_controller.dart` | 生成时机、落库与续写复用 |

## 6. 测试

- 纯函数：中文市 / 省 / 国家回退、英文界面下中国只发国家名、港澳台固定名称、未设置
  留空、日期与星期。
- 位置校验：合法国家 / 中国省市的接受，缺省省、非法省、市不属省、类型错误与未知
  地区代码的拒绝；港澳台固定名称与省市分组。
- 设置存储：系统语言默认值、持久化与重载、非法存量数据丢弃、按系统语言裁剪。
- 控制器：新回复插入并落库快照、续写复用且不重复插入、重新生成产生独立快照。
- 设置页：语言切换落盘、中文系统省市选择与清除、非中文系统国家列表。

## 7. 未决与交接

| 事项 | 交接 |
| --- | --- |
| 设置页分组、控件外观与间距 | 票 10 / 20 |
| 英文界面全量文案、语言切换的界面即时刷新范围 | 票 18 |
| 国家 / 地区列表的中文排序（Dart 无 `Intl.Collator`，当前按码点排序） | 视觉打磨时可替换为预排序表 |
