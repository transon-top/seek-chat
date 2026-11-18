# 票 20：设置、语言与数据管理界面原型

一次性粗原型，回答设置页的结构、交互与中英 × 浅深四组合观感。数据全部是假的，
没有数据库、网络、真实 Key 校验或系统权限；生产实现按票 10 的界面规格另做。

## 运行

```sh
flutter run -t prototype/settings/main.dart -d <设备 id>
```

截图与演示用参数：

```sh
flutter run -t prototype/settings/main.dart \
  --dart-define=PROTOTYPE_LANG=zh \
  --dart-define=PROTOTYPE_DARK=false \
  --dart-define=PROTOTYPE_SYSTEM=zh \
  --dart-define=PROTOTYPE_STATE=location
```

- `PROTOTYPE_LANG`：`zh`（默认）/ `en`
- `PROTOTYPE_DARK`：`true` / `false`（默认）
- `PROTOTYPE_SYSTEM`：`zh` / `other` / `auto`（默认跟随设备）
- `PROTOTYPE_STATE`：`location`、`key`、`import-confirm`、`import-failed`、`delete-confirm`

右上角「原型控制」可模拟系统语言（中文系统的省 / 市选择器，或其他系统的国家 /
地区列表），只影响位置选择器的形态；也可把导出结果切到失败，演示红色状态行。

## 结构答案

单页分组，从上到下：账户、对话、外观、语言与位置、语音、数据管理。没有照搬
chat-demo 的「通用 / 数据」两段导航：v1 设置项少，一屏扫完更直接；数据管理常被
误触，放在最底部并保留确认。语言与位置同区（票 16 / 18 的约束）。

- 账户：API Key 已保存 / 未设置两种态；点行打开「保存并校验」，清除 Key 需确认。
- 对话：模型固定 `deepseek-flash`；深度思考、智能搜索开关；朗读音色 Stella / Tide。
- 外观：跟随系统 / 浅色 / 深色三档胶囊，切换即时生效。
- 语言与位置：语言弹层单选，切换立即刷新界面；位置弹层按系统语言变形，未设置
  显示灰色「未设置」，两栏都有「不指定」。
- 语音：只做静态态——麦克风权限「未请求」、说明文案与系统设置入口；不接真实权限。
- 数据管理：导入历史对话（假文件面板 → 覆盖确认 → 不可关闭进度 → 成功 / 失败
  状态行）、导出所有历史对话（进度 + 成功 / 失败状态）、删除全部对话（确认 + 进度）。

## 覆盖的交互

- 中英切换立即刷新，主题切换立即生效；四组合截图为证。
- 中文系统：省份 / 城市两级胶囊，「不指定」清空所在地或只清城市。
- 其他系统：国家 / 地区列表，选中清掉省份 / 城市。
- 导入覆盖确认；超大文件在进度结束后显示红色失败状态；导出与删除的成功态。
- 清除 API Key 与删除全部对话都有确认框，危险按钮用 destructive 色。
- 原型控制里切换系统语言，验证两种位置选择器。

## 明确不做

- 真实文件选择、ZIP 解析、数据库替换、导出保存面板与真实权限请求。
- 真实 Key 校验、网络请求、安全存储；Key 前缀为假数据。
- 生产主题种子 `#4D6BFE` 与正式 ARB 文案；原型沿用票 09 的中性色板与内置双语文案。
- 票 10 的间距、无障碍与小屏适配。

## 截图

iPhone 17 Pro 模拟器采集：

| 文件 | 状态 |
| --- | --- |
| `screenshots/01-zh-light.png` | 中文 · 浅色主页面 |
| `screenshots/02-zh-dark.png` | 中文 · 深色主页面 |
| `screenshots/03-en-light.png` | 英文 · 浅色主页面 |
| `screenshots/04-en-dark.png` | 英文 · 深色主页面 |
| `screenshots/05-zh-location.png` | 中文系统位置弹层（省 / 市） |
| `screenshots/06-zh-import-confirm.png` | 导入覆盖确认 |
| `screenshots/07-zh-import-failed.png` | 导入失败状态（文件过大） |
| `screenshots/08-zh-delete-confirm.png` | 删除全部对话确认 |
| `screenshots/09-zh-region.png` | 其他系统位置弹层（国家 / 地区） |

测试只覆盖一条冒烟路径与关键确认，见
`test/prototype/settings_prototype_test.dart`。
