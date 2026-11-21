# shadcn_ui 界面规格

票：`10-ui-spec`。本文把票 09 / 20 的原型结论固化为可实现的界面规格，并吸收
本次会话补充的参考截图：

- 助手正文通栏、来源胶囊（站点图标叠加 + `N 个网页`）、底部操作条；
- 输入区激活开关为蓝色样式；
- 会话历史为分组抽屉，顶部品牌占位文案 `Fleepseek`，底部为设置按钮；
- 系统设置为带两段导航的底部 Sheet（通用设置 / 数据管理）。

关联文档：`architecture.md` §8、`markdown.md`、`search.md`、`attachments.md`、
`safety.md`、`history.md`、`i18n-theme.md`、`user-metadata.md`、`speech.md`。
术语见根目录 `GLOSSARY.md`。

- 组件库：`shadcn_ui` 0.60.0 + `lucide_icons_flutter`。
- 主题：票 18 的种子 `#4D6BFE` 生成浅深两套；原型的中性色板不进入生产。
- 品牌：界面显示名使用占位品牌 `Fleepseek`；不引入 DeepSeek logo 资源。
  `DeepSeek API Key` 作为服务名保留原文。
- 平台：iOS + Android，手机竖屏优先，横屏与平板单列适配；桌面 / Web 不在范围。
- 本次会话的参考截图未入库；实现以本文文字规格与数值为准。
- 本文的 Sheet / Dialog / Toast 分别指底部弹层、对话框、轻提示；
  主题 token 指颜色、圆角、间距、字号等设计变量。

## 0. 决策摘要

| 主题 | 决策 |
| --- | --- |
| 主路由 | 聊天页为根；会话列表改为左侧抽屉，不再使用独立列表首页 |
| 设置 | 底部 Sheet，占屏 92%，顶部两段导航；数据管理为同一 Sheet 内的视图 |
| 品牌 | 界面显示 `Fleepseek`；抽屉顶部为蓝色文字标，不使用 logo 图片 |
| 主题来源 | `ColorScheme.fromSeed(#4D6BFE)` → 映射 `ShadColorScheme`；不维护第二套色表 |
| 激活开关 | 蓝色系：浅蓝底 + 蓝描边 + 蓝图标 / 文字；未激活为透明底 + 灰描边 |
| 助手布局 | 通栏无气泡；用户消息右对齐浅灰气泡 |
| 来源 | 回复底部「站点图标叠加 + N 个网页」胶囊；点击打开底部来源抽屉 |
| 操作条 | v1 只保留复制、重新生成、朗读；点赞 / 点踩 / 分享不渲染 |
| 顶部栏 | 菜单、左对齐的会话标题、新建对话；分享不渲染 |
| 输入区 | 大圆角容器、无阴影；附件、麦克风、发送 / 停止；朗读入口只在消息操作条 |
| 超长消息 | 不做 8 行折叠；完整渲染 Markdown，单块超过 200000 字符按纯文本降级 |
| 模型切换 | 不保留；v1 固定 `deepseek-flash` |
| 断点 | 单列；`<600` 紧凑，`>=600` 宽屏；聊天内容最大 760，设置最大 640 |
| 动效 | 交互 150–180 ms；尊重 `MediaQuery.disableAnimations` |
| 无障碍 | 44×44 最小点击区、动态字体 2.0、语义标签、减少动画、4.5:1 对比度 |

## 1. 页面与路由

### 1.1 应用壳

- 使用 `ShadApp`，同时提供：
  - `theme` / `darkTheme`：`ShadThemeData`，由同一 Material 种子派生；
  - `themeMode`：跟随 `ui.themeMode`（票 18）；
  - `locale` / 本地化委托：沿用票 18；
  - `materialThemeBuilder`：把同一套 Material 主题传给 `gpt_markdown`、
    `mermaid_flutter` 与仍使用 Material 控件的子组件。
- `ShadApp` 自带 `ShadToaster` 与 `ShadSonner`；全应用只使用这一处 Toast 宿主。
- 路由继续使用 `Navigator` 1.0。v1 无深链、无 Web URL，不引入 `go_router`。
- 根路由为聊天页；设置、来源、图片查看等用 Sheet / Dialog / 全屏路由。

### 1.2 路由与呈现清单

| 界面 | 入口 | 呈现 | 关闭 | 说明 |
| --- | --- | --- | --- | --- |
| 聊天页 | 应用启动 | 根页面 | 系统返回退出 | 顶部栏 + 消息区 + 输入区 |
| 会话抽屉 | 顶部菜单按钮；右滑 | 左侧 Sheet，宽 `min(300, 屏宽-48)` | 遮罩、返回、面板收起按钮 | 新建 / 打开 / 重命名 / 删除 / 设置入口 |
| 系统设置 | 抽屉底部设置行 | 底部 Sheet，高 92% | 关闭按钮、返回、遮罩 | 两段导航：通用 / 数据管理 |
| 数据管理 | 设置导航「数据管理」 | 设置 Sheet 内视图 | 关闭按钮、遮罩 | API Key、导入 / 导出 / 删除全部对话 |
| 来源抽屉 | 「N 个网页」胶囊、搜索行、查看全部 | 底部 Sheet，最高 85% | 下拉、遮罩、关闭按钮 | 全局去重来源列表 |
| 附件来源 | 回形针按钮 | 底部 Sheet | 遮罩、返回 | 从相册选择 / 选择文件 |
| 语言选择 | 设置「语言」行 | 锚定弹层 | 选中、遮罩 | 跟随系统 / 简体中文 / English |
| 所在地选择 | 设置「位置信息」胶囊 | 锚定弹层 | 选中、遮罩 | 中文系统省市；其他系统国家 / 地区 |
| 音色选择 | 设置「朗读音色」行 | 锚定弹层 | 选中、遮罩 | Stella / Tide |
| API Key | 数据管理顶部输入框 | 内联输入 | 键盘完成提交 | 校验并保存；已保存时可清除 |
| 重命名会话 | 会话行菜单 | Dialog | 取消、遮罩 | 输入框 + 保存 |
| 删除会话 | 会话行菜单 | Dialog | 取消、遮罩 | 危险按钮 |
| 清除 Key | 数据管理「清除已保存的 Key」 | 直接清除 | — | 输入框回到未设置 |
| 导入确认 | 数据管理「选择文件」后 | Dialog | 取消、遮罩 | 覆盖提示 |
| 导入 / 导出进度 | 确认后 / 点击导出 | Dialog | 不可关闭 | 阻塞重复操作 |
| 删除全部对话 | 数据管理红色按钮 | Dialog | 取消、遮罩 | 二次确认 |
| 图片查看 | 点击消息图片 | 全屏路由 | 关闭按钮、系统返回 | 黑色背景、缩放 |
| 文件选择 / 保存 | 系统选择器 | 系统 UI | 系统 | 不进入应用路由栈 |

### 1.3 聊天页结构

从上到下：

1. **顶部栏**：高 46；左侧菜单按钮（36×36，Lucide `menu`）；会话标题左对齐、
   左右外边距 12（15sp / w500，单行省略；空标题显示「新对话」）；右侧新建对话按钮
   （36×36，Lucide `circlePlus`）。分享按钮不进入 v1。
2. **消息区**：`ListView`，水平内边距 16，顶部 4，底部 8；消息间距 16；
   宽屏内容最大 760 并居中。
3. **输入区**：左右外边距 16；容器圆角 28、1px 描边、无阴影；内部
   左 16 / 上 12 / 右 12 / 下 10。
4. **免责声明**：10.5sp、`mutedForeground`、底部 8；文案「内容由 AI 生成，请仔细甄别」。

空态：消息区垂直居中显示「今天有什么可以帮到你？」（20sp / w500），
不显示 logo、建议卡或快捷问题。加载态：顶部不确定进度条 + 3 条骨架 +
「正在加载会话…」。错误态：错误提示 + 重试按钮。

自动滚动：用户在底部附近时，新内容到达后保持贴底；用户主动上滑后停止自动滚动；
滚回底部后恢复。

### 1.4 会话抽屉

外观照搬 chat-demo 侧边栏的移动端形态（`AppSidebarColors`，见 §3.2）：

- 全高、贴左侧、右侧不留圆角；宽度 `min(300, 屏宽-48)`；背景 `AppSidebarColors.fill`；
  右缘 1px `AppSidebarColors.border` 描边；上 6 / 左右 12 内边距；安全区。
- 顶部搜索入口：高 40，圆角 999，`AppSidebarColors.inputFill` 底 + 1px
  `AppSidebarColors.border`；左侧 `search` 16 `labelTertiary`，间距 8，
  占位「搜索对话内容…」16sp / `labelTertiary`；下距 8。入口只作按钮，
  不接收输入，点击推入全屏搜索页。侧栏不提供品牌文字标、收起按钮与新建对话入口。
- 多选入口：44×44 点击区，叠在列表第一行分组头的右侧，与当前吸顶的日期标签
  同一行；图标 Lucide `listChecks` 16，`labelTertiary`；不单独占一行，滚动时
  固定在列表右上。
- 会话分组：`置顶` / `今天` / `昨天` / `7 天内` / `更早`；组标题移动端 14sp / 22 / w500 /
  `AppSidebarColors.labelTertiary`，内边距 4 / 10 / 3，滚动时吸顶，
  底色同 `AppSidebarColors.fill`；组间 16。组内按 `updatedAt` 倒序。
  「置顶」组只在存在置顶会话时显示；置顶会话不重复出现在时间分组。
- 会话行：高 44，内边距 左 12 / 右 12，圆角 16；标题 16sp / 22，单行省略。
  - 当前会话：浅色底 `#E4EDFD` + 蓝字 `#3964FE`；深色底 `#353638` + 白字。
  - 其他会话：透明底，文字 `AppSidebarColors.labelPrimary`。
  - 行尾不再放三点菜单。长按会话行（非多选模式）弹出操作卡：`重命名` /
    `置顶`（已置顶为 `取消置顶`）/ `多选` / `删除`；卡片宽 `min(240, 屏宽-64)`，
    圆角 16，`AppSidebarColors.menuFill` 底 + 三层投影，项间 1px
    `AppSidebarColors.border`；项高 44，图标 18 + 文案 16sp / 24；删除项文字与
    图标 `danger`。卡片锚定该行弹出，点任一项关闭；长按同时给一次轻震动。
  - 重命名：整行变输入框（高 44，圆角 16，`brand` 1px 描边，`inputFill` 底，
    16sp）；回车或失焦提交，`Escape` 取消；`trim` 后为空或未改动不写库。
  - 删除确认：Dialog 宽 `min(380, 屏宽-32)`，圆角 24，内边距 24 / 22，`card` 底；
    标题 16sp / 24 / w500，描述 14sp / 22 / `mutedForeground`；按钮胶囊形右对齐，
    间距 8；危险按钮 `AppSidebarColors.danger` 底白字；遮罩浅色 36%、深色 60%。
    批量删除标题为「删除 N 个对话」，描述与单条删除相同。
- 多选模式：搜索入口整行替换为标题「选择对话」/「已选择 N 个对话」（16sp / w500 /
  `labelPrimary`，左内边距 10，与分组标题对齐）与右侧圆形关闭按钮
  （36×36，Lucide `x`，`menuFill` 底三层投影）。整块高 48（40 + 下距 8），
  与搜索入口等高，切换多选时列表不上下跳动。
  会话行左侧加 22 圆形勾选：选中为 `brand` 底 + 白色 `check`，未选中为 1px
  `labelTertiary` 空心；行内其余操作失效。进入 / 退出多选：搜索入口与选择标题
  200ms 淡入淡出；勾选圈槽位宽度 0 → 32，同时淡入并放大，行文字随槽位右移，
  退出反向。底部设置行替换为置顶 / 删除操作栏：
  两项各占一半，中央 1px `border` 分隔线，图标 20 + 文案 16sp；0 选中时
  `labelTertiary` 且不可点；可点时置顶为 `labelPrimary`、删除为 `danger`。
- 会话搜索页的外观与结果行见 §1.4.1。
- 首次加载骨架：6 行会话行形状的静态灰块，行高 44，圆角 12，
  `AppSidebarColors.activeItemFill` 底色；无动画。搜索页骨架见 §1.4.1。
- 底部设置行：上下留白 12；左侧 `settings` 20，间距 10，文案「设置」16sp / 22 /
  `labelPrimary`；内边距 9 / 10，圆角 12；点击关闭抽屉并打开系统设置 Sheet。
- 空态：居中「还没有会话」14sp / `labelTertiary`。加载：骨架列表；
  失败：14sp 文案 + 重试按钮。

### 1.4.1 会话搜索页

点击侧栏搜索入口后，侧栏从当前宽度向右展开到全屏，对话层继续右移直到完全
移出屏幕；搜索框随侧栏展开到全宽。返回箭头或系统返回让对话层滑回，搜索层收回
抽屉宽度。背景 `AppSidebarColors.fill`：

- 顶部安全区下横排：返回按钮（Lucide `chevronLeft`，20，点击区 36×44）+
  搜索框，间距 8；左内边距 8、右内边距 16，搜索框右侧留白。
- 搜索框：高 40，圆角 999，`AppSidebarColors.inputFill` 底 + 1px
  `AppSidebarColors.border`；左侧 `search` 16 `labelTertiary`，间距 8，
  占位「搜索对话内容…」16sp / `labelTertiary`；输入文字 `labelPrimary`；
  非空时尾部圆形 X（Lucide `x`，14，`labelTertiary`，点击区 36）。打开自动聚焦。
- 空白态：只显示顶部栏，下方留空。
- 加载：6 行搜索结果骨架：左侧 44 圆 + 右侧两行灰条，行高 78，无动画。
- 无结果：垂直居中，虚线圆放大镜 40（`labelTertiary`）+ 下距 12，
  「暂无相关结果」14sp / `labelTertiary`。
- 结果行：高 78，内边距 左右 16 / 上下 12；左侧 44 圆形描边（1px
  `AppSidebarColors.border`）+ `messageCircle` 20 `labelTertiary`，间距 12；
  右侧上下两行：
  - 第一行：标题 16sp / 22 / w500 / `labelPrimary`，单行省略；最右相对时间
    14sp / 22 / `labelTertiary`，与标题间距 12。
  - 第二行：片段 14sp / 22 / `labelTertiary`，单行省略，按截断位置加「…」。
- 行间无分隔线；结果按 `updatedAt` 倒序平铺，不分组，置顶不插队。
- 相对时间：今天 `HH:mm`；昨天「昨天 / Yesterday」；今年内「M月d日 / MMM d」；
  更早「yyyy年M月d日 / MMM d, yyyy」。

### 1.5 系统设置 Sheet

- 底部 Sheet，高 92%，顶部圆角 24，背景 `background`，遮罩 40%（深色 60%）。
- 顶部：标题「设置」20sp / w600；右侧关闭按钮（36×36，Lucide `x`）。
- 导航行：水平排布两个入口，间距 8：
  - 通用设置（Lucide `settings2`）
  - 数据管理（Lucide `database`）
  - 选中项为灰底胶囊（`muted`，圆角 999，高 44）；未选中透明底，
    文字 `mutedForeground`。两项在当前 Sheet 内切换。
- 内容：水平内边距 20，顶部 24，底部 `SafeArea` + 48；宽屏最大 640 居中。

**通用设置**

1. `主题`：浅色 / 深色 两张等宽卡片一行，跟随系统整行；卡片间距 8，高 88，
   圆角 14，1px 描边；图标 20（`sun` / `moon` / `monitor`），文案 13；
   选中卡片 `muted` 底，未选中 `card` 底。
2. `语言`：行高 52；左侧标签 15；右侧下拉胶囊（高 36，`muted` 底，圆角 999，
   内边距 14，文字 13 + `chevronDown` 14）。选项：跟随系统 / 简体中文 / English。
3. `朗读音色`：同样的下拉胶囊；选项 Stella · 女声 / Tide · 男声。
4. `位置信息`：中文系统为省份 / 城市两颗并排胶囊，其他系统为单颗国家 / 地区
   胶囊；行下说明「只随消息发送给你配置的 API，不申请定位权限」。
5. `语音`：麦克风权限状态行；已拒绝时显示「打开系统设置」描边按钮。
- 下拉胶囊点击打开锚定弹层：圆角 16、1px 描边，最大高 320，内部滚动；
  选项高 44，选中项右侧 `check` 18。

**数据管理**

1. 顶部 `输入 API Key 开始使用`：单行输入框，占位「请输入 API Key」，
   键盘完成时校验并保存；已保存时下方显示「已保存」与
   「清除已保存的 Key」。
2. 导入历史对话（上传）、导出所有历史对话（下载）、删除所有对话（删除，
   危险色描边）三行；版式与状态见 §5.9。

### 1.6 浮层

- **Dialog**：最大宽 420，圆角 18，内边距 20；标题 17sp / w600，描述 13sp /
  1.5；操作按钮右对齐，间距 8。危险操作使用 `ShadButton.destructive`。
- **Sheet**：底部圆角 24；顶部拖拽把手 36×4，`border`；标题 15sp / w600；
  内容滚动；最大高度按界面清单。
- **Toast**：使用 `ShadToast`，顶部、聊天顶栏下方 8；最大宽 480；默认 4 s，
  错误 5 s；同屏只显示一条。权限拒绝带「打开系统设置」动作。
- **进度 Dialog**：不可关闭、遮罩不可点、无取消按钮；不确定进度条 + 状态文案。
- **图片查看**：全屏黑色；`InteractiveViewer` 最小 1×、最大 4×；右上关闭按钮
  44×44；图片 `BoxFit.contain`；语义标签为文件名。

## 2. 组件映射

### 2.1 shadcn_ui 基础映射

| 界面需求 | 组件 | 约束 |
| --- | --- | --- |
| 应用壳 | `ShadApp` | 主题、locale、themeMode、Material 桥接 |
| 主按钮 / 发送 | `ShadButton` | 高 34–44；主色底 |
| 次按钮 / 描边 | `ShadButton.outline` | 继续、重试、导入导出 |
| 危险按钮 | `ShadButton.destructive` | 清除 Key、删除全部 |
| 文字按钮 | `ShadButton.link` | 编辑、展开全文（如需） |
| 图标按钮 | `ShadIconButton.ghost` | 菜单、关闭、操作条；视觉 28–36，点击区 ≥44 |
| 输入 | `ShadInput` | 输入区、API Key、重命名 |
| 开关 | `ShadSwitch` | 深度思考、智能搜索、设置默认值 |
| 进度 | `ShadProgress` | 加载、导入、导出；搜索时间线不使用进度条 |
| 错误块 | 自绘红字行（同 chat-demo `notice`） | 回复请求错误；拒答不用红色 |
| 对话框 | `ShadDialog` + `showShadDialog` | 确认、Key、进度 |
| 底部弹层 | `ShadSheet` + `showShadSheet` | 设置、来源、选择器、附件来源 |
| 弹出菜单 | `ShadPopover` | 会话行重命名 / 删除 |
| 工具提示 | `ShadTooltip` | 图标按钮的长按 / 悬停提示 |
| Toast | `ShadToast` + `ShadToaster` | 全局提示 |
| 分隔线 | `ShadSeparator` | 设置卡片行分隔 |

所有图标使用 `lucide_icons_flutter`，不混用 Material Icons；该包由 `shadcn_ui`
重新导出，不新增直接依赖。仍由渲染包绘制的
Markdown / Mermaid 内容使用 `materialThemeBuilder` 提供的 Material 主题。

### 2.2 组件清单

| 组件 | 实现 | 位置 | 用途 |
| --- | --- | --- | --- |
| `ChatHeader` | 自绘 + `ShadIconButton` | `features/chat/` | 菜单、标题、新建对话 |
| `SessionDrawer` | 自绘 + `ShadSheet` | `features/sessions/` | 分组会话列表、设置入口 |
| `SettingsSheet` | 自绘 + `ShadSheet` | `features/settings/` | 两段导航系统设置 |
| `SettingsNav` | 自绘 | `features/settings/` | 通用 / 数据管理导航 |
| `SettingsSection` | 自绘 | `features/settings/` | 设置分组、卡片、分隔线 |
| `SettingsValueRow` | 自绘 | `features/settings/` | 标签 + 行尾值 / 操作 |
| `SettingsSwitchRow` | 自绘 + `ShadSwitch` | `features/settings/` | 开关行 |
| `SettingsDropdownPill` | 自绘 | `features/settings/` | 语言、音色下拉胶囊 |
| `ThemeCard` | 自绘 | `features/settings/` | 浅色 / 深色 / 跟随系统 |
| `Composer` | 自绘 + `ShadInput` | `features/chat/` | 输入、开关、附件、语音、发送 |
| `ComposerToggle` | 自绘 | `features/chat/` | 深度思考 / 智能搜索胶囊；激活蓝色 |
| `SendButton` | 自绘 | `features/chat/` | 发送 / 停止圆形按钮 |
| `UserMessage` | 自绘 | `features/chat/` | 右对齐气泡、附件、编辑、版本切换 |
| `AssistantMessage` | 自绘 | `features/chat/` | 思考、时间线、正文、来源、操作 |
| `ThinkingHeader` | 自绘 | `features/chat/` | 展开 / 收起、计时、状态标签 |
| `ToolStepRow` | 自绘 | `features/chat/` | 搜索 / 浏览 / 查找 / 阅读行 |
| `SourcePill` | 自绘 | `features/search/` | 站点图标叠加 + N 个网页 |
| `SourceSheet` | 自绘 + `ShadSheet` | `features/search/` | 来源列表 |
| `SourceCard` | 自绘 | `features/search/` | 来源卡片 |
| `CitationBadge` | 自绘 `TextSpan` / `WidgetSpan` | `features/search/` | 行内引用角标 |
| `BranchSwitcher` | 自绘 + `ShadIconButton` | `features/chat/` | 上一版 / 下一版 |
| `MessageActions` | 自绘 + `ShadIconButton` | `features/chat/` | 复制 / 重新生成 / 朗读 |
| `ContinueButton` | `ShadButton.outline` | `features/chat/` | 停止 / 超长后的继续生成 |
| `ReplyError` | 自绘红字行（同 chat-demo `notice`） | `features/chat/` | 请求错误 + 重试 |
| `AttachmentStrip` | 自绘 | `features/chat/` | 草稿附件条 |
| `AttachmentChip` | 自绘 | `features/chat/` | 图片缩略图 / 文档卡 |
| `MessageAttachments` | 自绘 | `features/chat/` | 消息内附件 |
| `ImagePreview` | 自绘 + `InteractiveViewer` | `features/chat/` | 全屏图片 |
| `RecordingStatus` | 自绘 | `features/chat/speech/` | 录音计时 + 5 根电平条 |
| `VoiceButton` | 自绘 / `ShadIconButton` | `features/chat/speech/` | idle / recording / transcribing |
| `ReadAloudButton` | 自绘 | `features/chat/speech/` | idle / loading / playing |
| `ApiKeyField` | 自绘 + `ShadInput` | `features/settings/` | 数据管理内联 Key 输入 |
| `ConfirmDialog` | `ShadDialog` | `features/settings/` | 删除 / 清除 / 导入覆盖 |
| `ProgressDialog` | `ShadDialog` + `ShadProgress` | `features/settings/` | 导入 / 导出不可关闭进度 |
| `ImportExportRows` | 自绘 + `ShadButton` | `features/history/` | 数据管理三行 |

自绘组件优先放在所属功能目录；只有被两个以上功能复用的组件才下沉到
`shared/`。主题与 token 放 `lib/app/theme.dart`，不新建第二套 UI 库。

## 3. 主题 token

### 3.1 构建方式

种子、深浅行为与中文排版以 `i18n-theme.md` §5 为准；下面是界面层映射。

```dart
const appThemeSeed = Color(0xFF4D6BFE);

ShadThemeData buildShadTheme({required Brightness brightness}) {
  final material = ThemeData(colorSchemeSeed: appThemeSeed, brightness: brightness);
  final c = material.colorScheme;
  return ShadThemeData(
    brightness: brightness,
    colorScheme: ShadColorScheme(
      background: c.surface,
      foreground: c.onSurface,
      card: c.surfaceContainerLow,
      cardForeground: c.onSurface,
      popover: c.surfaceContainerLow,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.secondaryContainer,
      secondaryForeground: c.onSecondaryContainer,
      muted: c.surfaceContainerHighest,
      mutedForeground: c.onSurfaceVariant,
      accent: c.secondaryContainer,
      accentForeground: c.onSecondaryContainer,
      destructive: c.error,
      destructiveForeground: c.onError,
      border: c.outlineVariant,
      input: c.outlineVariant,
      ring: c.primary,
      selection: c.primary.withValues(alpha: 0.24),
    ),
    radius: const BorderRadius.all(Radius.circular(10)),
    textTheme: buildShadTextTheme(material.textTheme),
  );
}
```

- `ShadTextTheme` 必须显式覆盖全部 13 个样式，字体清空为系统字体；未覆盖的
  样式会回退 shadcn 自带 Geist 字体，违反票 18 的「系统字体」约束。
- `ShadApp.materialThemeBuilder` 返回同一个 `ThemeData`，保证 Markdown、Mermaid、
  代码高亮与原生控件颜色一致。
- 不新增第二套色表；禁止在 widget 内写死十六进制颜色。

### 3.2 颜色 token

| 用途 | 取值 | 说明 |
| --- | --- | --- |
| 页面背景 | `background` | Material `surface` |
| 正文 / 图标 | `foreground` | `onSurface` |
| 卡片 / 输入区 / 来源卡 | `card` | `surfaceContainerLow` |
| 次级文字 / 图标 | `mutedForeground` | `onSurfaceVariant` |
| 用户气泡 / 选中会话 / 选中开关 | `muted` 或 `primary` 10% | 见各组件 |
| 主按钮 / 激活态 | `primary` | 种子生成 |
| 主按钮文字 | `primaryForeground` | `onPrimary` |
| 错误 / 删除 | `destructive` | `error` |
| 错误背景 | `errorContainer` | 仅错误块 |
| 边框 / 分隔线 | `border` | `outlineVariant` |
| 遮罩 | 黑色 40% / 深色 60% | Sheet / Dialog |
| 流式光标 | `primary` | 2×16 |
| 引用角标 | `muted` 底 + `mutedForeground` 字 | 见 §8.3 |
| 搜索缩略图占位 | `muted` 底 + `mutedForeground` 图标 | 站点图标缺失时 |

聊天专用颜色全部由上述 token 派生，不新增 `custom` 颜色；
唯一例外是会话抽屉：照搬 chat-demo 的独立侧栏色组 `AppSidebarColors`，
只被抽屉引用：

- 用户气泡：`muted`；
- 助手区域：`background`；
- 思考 / 工具行：`mutedForeground`；
- 来源胶囊：`card` 底 + `border` 描边；
- 会话抽屉：独立色组 `AppSidebarColors`（照搬 chat-demo），浅深各一套：
  侧栏底 `#F9FAFB` / `#1B1B1C`、右缘描边 黑 4% / 白 6%、
  主文字 `#0F1115` / `#F9FAFB`、三级灰 `#81858C` / `#ADB2B8`、
  品牌蓝 `#3964FE` / `#5686FE`、高亮底 `#E4EDFD` / `#353638`、
  高亮字 `#3964FE` / `#FFFFFF`、浮起底 `#FFFFFF` / `#43454A`、
  输入底 `#FFFFFF` / `#2C2C2E`、菜单底 `#FFFFFF` / `#353638`、
  危险红 `#EC1313` / `#F25A5A`；不并入全局色表；
- 输入区激活开关：`primary` 10%（深色 16%）底，`primary` 45% 描边，
  图标 / 文字 `primary`；
- 录音状态点：`destructive`；
- 选中文本：`selection`。

### 3.3 圆角

| Token | 值 | 用途 |
| --- | --- | --- |
| `radiusXs` | 4 | 行内代码 |
| `radiusBadge` | 6 | 引用角标 |
| `radiusSm` | 8 | 小按钮、代码块复制按钮、抽屉菜单项 |
| `radiusMd` | 10 | 菜单项 |
| `radiusLg` | 12 | 附件缩略图、代码块、工具行、抽屉菜单外壳、底部设置行 |
| `radiusXl` | 14 | 来源卡、主题卡 |
| `radiusRow` | 16 | 抽屉会话行、重命名输入框 |
| `radius2xl` | 18 | 设置卡片、Dialog |
| `radius3xl` | 20 | 用户气泡 |
| `radiusSheet` | 24 | 底部 Sheet 顶部 |
| `radiusComposer` | 28 | 输入区容器 |
| `radiusFull` | 999 | 胶囊、圆形按钮 |

### 3.4 间距与尺寸

| Token | 值 | 用途 |
| --- | --- | --- |
| `space2` | 2 | 图标与文字微调 |
| `space4` | 4 | 角标、紧凑间距 |
| `space6` | 6 | 图标与文字 |
| `space8` | 8 | 按钮组、卡片间距 |
| `space10` | 10 | 行内边距、缩略图 |
| `space12` | 12 | 抽屉内边距、卡片内边距 |
| `space16` | 16 | 页面水平内边距、消息间距 |
| `space18` | 18 | 设置分组间距 |
| `space20` | 20 | 设置水平内边距、Dialog 内边距 |
| `space24` | 24 | Sheet 头部、分组标题 |
| `space32` | 32 | 大区块 |
| `space48` | 48 | 列表底部留白 |

固定尺寸：

- 顶部栏 46；设置标题 20；设置 Sheet 标题区 56。
- 输入区开关高 34；发送按钮 34；图标按钮视觉 28–36，点击区 ≥44。
- 附件条高 76；图片缩略图 64；消息图片纯图 120、混排 64；文档卡最大宽 210。
- 来源胶囊高 36；站点图标 20，叠加偏移 -6；操作条图标 18，视觉 36，点击区 ≥44。
- 思考图标 14；工具行图标 16；引用角标字号 10。
- Dialog 最大宽 420；Toast 最大宽 480；设置内容最大宽 640；聊天内容最大宽 760。

### 3.5 字体与字号

系统字体；不打包字体。中文正文行高 1.6；英文正文保持 1.5。

| 用途 | 字号 / 行高 | 字重 |
| --- | --- | --- |
| 设置标题「系统设置」 | 20 / 28 | w600 |
| 空态标题 | 20 / 28 | w500 |
| 设置分组标签 | 15 / 22 | w500 |
| 设置行标签 | 15 / 22 | w400 |
| 设置行值 / 下拉胶囊 | 13 / 20 | w400 |
| 设置导航 | 13.5 / 20 | w500 |
| 聊天正文 | 16 / 1.6 | w400 |
| 用户气泡 | 16 / 1.6 | w400 |
| 助手思考正文 | 13 / 1.6 | w400 |
| 思考标题 / 工具行 | 12.5–13 / 18 | w400–500 |
| 顶部栏标题 | 15 / 20 | w500 |
| 会话抽屉品牌 | 20 / 22 | w600 |
| 会话行 | 16 / 22 | w400 |
| 抽屉分组标题 | 14 / 22 | w500 |
| 抽屉菜单项 | 14 / 24 | w400 |
| 抽屉新建对话 / 空态 | 14 / 22 | w500 / w400 |
| 输入框 / 占位 | 16 / 1.6 | w400 |
| 开关胶囊 | 12.5 / 16 | w500（激活）/ w400 |
| 来源胶囊 | 13 / 18 | w500 |
| 来源卡片标题 | 13.5 / 19 | w500 |
| 引用角标 | 10 / 14 | w600 |
| 按钮 | 13.5–14 / 20 | w500 |
| 免责声明 / 辅助文字 | 10.5 / 14 | w400 |

动态字体：全部字号由 `MediaQuery.textScaler` 缩放；不为文字设置固定高度；
放大到 2.0 时允许换行、卡片重排与列表滚动，不裁切。

应用字号设置：七档 0.82 / 0.88 / 0.94 / 1.00 / 1.12 / 1.24 / 1.35；默认跟随系统，
关闭跟随后固定档位。跟随系统时系统字号夹到 0.8–2.0。

### 3.6 Markdown / 数学 / Mermaid / 代码 / 表格 / 引用

| 元素 | 规格 |
| --- | --- |
| 正文段落 | 16 / 1.6；段间距 12 |
| H1 | 22 / 30 / w600；上 16 下 8 |
| H2 | 20 / 28 / w600；上 16 下 8 |
| H3 | 18 / 26 / w600；上 12 下 6 |
| H4 | 16 / 24 / w600；上 12 下 6 |
| 列表 | 左缩进 20；项间距 4；项目符号 `mutedForeground` |
| 行内代码 | 13.5 等宽；`muted` 底；圆角 4；水平 4 / 垂直 2 |
| 代码块 | `card` 底 + `border`；圆角 12；内边距 12；13 / 1.5 等宽；水平滚动；右上复制按钮 |
| 引用 | 左边框 3 `primary` 40%；左内边距 12；13 / 1.6；`mutedForeground`；不用斜体 |
| 表格 | 宽 100%；1px 边框；表头 `muted`；单元格 8×10；13 / 1.5；宽度不足时水平滚动 |
| 链接 | `primary`；无下划线；点击外部浏览器；仅 `http` / `https` |
| 图片 | 不加载网络图片；显示链接图标 + 地址；地址仅在 http(s) 时可点 |
| 数学 | 继承正文颜色；块级公式可水平滚动；解析失败显示原文 |
| Mermaid | `mermaid_flutter`；高 320；圆角 12 + 1px 描边；深浅主题切换；失败降级等宽源码 |
| 分隔线 | 1px `border`；上下 16 |
| 超长块 | 单个文本块 > 200000 字符按纯文本显示 |

代码高亮、Mermaid 主题与数学字体由渲染包控制；本规格只约束外框、间距与颜色。

### 3.7 深浅色差异

- 浅色：`background` 为浅表面，`card` 略深；用户气泡 `muted`；遮罩 40%。
- 深色：`background` 为深表面（不用纯黑）；`card` 比背景略亮；用户气泡
  `surfaceContainerHighest`；遮罩 60%；代码块、Mermaid 使用深色板。
- 边框在深色下必须可见；不使用纯黑 `#000` 作为页面背景。
- 选中 / 激活态在深色下提高透明度（10% → 16–18%），避免对比不足。
- 状态栏图标亮度按 `Brightness` 切换；导航栏沿用系统默认。

### 3.8 动效

| 场景 | 时长 / 曲线 |
| --- | --- |
| 开关、按钮颜色 | 150 ms / easeOut |
| 思考块展开 / 收起 | 180 ms / easeOut；箭头旋转 180 ms |
| Sheet / Dialog 进退 | 220–250 ms / easeOutCubic |
| 流式光标 | 650 ms 往返，透明度 0→1→0 |
| 朗读竖条 | 900 ms 循环；4 根相位错开 |
| 录音电平 | 100 ms 采样；只重建电平条 |
| 长消息展开 | 不做（v1 不折叠） |
| 分支切换 | 不淡入淡出，直接替换内容 |

`MediaQuery.disableAnimations` 为 true 时：流式光标静态显示、思考箭头不旋转、
朗读竖条静态、录音电平条静态或低频更新、Sheet / Dialog 使用无动画切换。
不以动画承载必要信息。

## 4. 响应式

| 断点 | 宽度 | 行为 |
| --- | --- | --- |
| 紧凑 | `< 600` | 手机竖屏 / 横屏；聊天水平 16；设置水平 20 |
| 宽屏 | `>= 600` | 平板 / 折叠屏展开；聊天内容最大 760 居中；设置内容最大 640 居中 |

- v1 不做双栏主从布局；抽屉始终为覆盖层，不常驻。
- 抽屉宽 `min(300, 屏宽-48)`；宽屏下仍为 300。
- 设置 Sheet 宽 100%，内容居中；横屏时高度 92%，内部滚动。
- 手机横屏：单列，键盘弹出时输入区贴键盘上方，消息区保持可滚动；
  空态改为顶部对齐，不使用固定 430 高。
- 小屏最小按 320 宽验证：设置三张主题卡允许换行（每行 2 或 3 张）；
  语言 / 音色行在文字放大或宽度不足时改为上下排布。
- 文本放大 2.0：设置行、会话行、来源卡、操作条允许换行；图标不放大；
  输入区最多 5 行后内部滚动。
- 安全区：聊天顶部与底部、抽屉、设置 Sheet、图片查看均使用 `SafeArea`；
  Sheet 底部留出系统手势区。
- 键盘：`resizeToAvoidBottomInset` 保持 true；输入区随键盘上移；
  Toast 固定在顶部，不受键盘影响。

## 5. 交互状态与按钮态

### 5.1 聊天页总体状态

| 状态 | 消息区 | 输入区 | 顶部栏 | 操作 |
| --- | --- | --- | --- | --- |
| 空会话 | 空态标题 | 可输入；发送按条件启用 | 标题「新对话」 | 发送首条消息时创建会话 |
| 加载会话 | 骨架 + 进度 + 「正在加载会话…」 | 禁用输入与发送 | 保留标题 | 加载完成或错误 |
| 就绪 | 可见路径消息 | 正常 | 当前标题 | 可发送 / 附件 / 语音 |
| 生成中 | 流式正文 / 思考 / 工具行 / 光标 | 发送变停止；附件与语音禁用；文本与开关可用 | 标题不变 | 输入区停止 |
| 已停止 | 已有正文 | 正常 | 标题不变 | 继续生成（满足条件时） |
| 错误 | 已收正文（如有）+ 错误块 | 正常 | 标题不变 | 重试（仅上传错误）/ 重新生成 |
| 拒答 | 拒答正文 | 正常 | 标题不变 | 无续写 / 无重新生成 / 无来源 |
| 录音中 | 不变 | 语音按钮录音态；发送与附件禁用 | 标题不变 | 点击语音结束并转写 |
| 转写中 | 不变 | 语音按钮加载态；发送与附件禁用 | 标题不变 | 点击取消 |
| 朗读中 | 操作条朗读态 | 录音入口禁用 | 标题不变 | 再点同条停止 |

### 5.2 输入区按钮态

发送可用条件（全部满足）：

1. 文本 `trim()` 非空，或草稿附件非空；
2. 所有草稿附件处于 `done`；
3. 语音状态为 `idle`；
4. 会话不在生成中。

| 条件 | 发送按钮 | 附件 | 语音 | 开关 | 输入框 |
| --- | --- | --- | --- | --- | --- |
| 无内容 | 禁用（主色 35%） | 可用 | 可用 | 可用 | 可用 |
| 有文本 / 有附件 | 可用（主色） | 可用 | 可用 | 可用 | 可用 |
| 附件上传中 | 禁用 | 可用（继续添加） | 可用 | 可用 | 可用 |
| 生成中 | 变为停止（主色圆形 + 实心方块图标，同发送底） | 禁用 | 禁用 | 可用 | 可用 |
| 录音中 | 禁用 | 禁用 | 录音态（可点击结束） | 可用 | 可用 |
| 转写中 | 禁用 | 禁用 | 加载态（点击取消） | 可用 | 可用 |
| 朗读中 | 可用（发送会先停朗读） | 可用 | 禁用 | 可用 | 可用 |
| 无 API Key | 可点击；提示 `errorNoApiKey` | 可用 | 点击提示 `errorNoApiKey` | 可用 | 可用 |

- 占位文案：`给 Fleepseek 发送消息` / `Message Fleepseek`。
- 多行输入最多 5 行，之后内部滚动；`minLines: 1`。
- 激活开关：浅蓝底 + 蓝描边 + 蓝图标文字；未激活：透明底 + 灰描边 +
  `mutedForeground`。开关只影响之后创建的回复，不打断当前生成。
- 录音 / 转写时文本编辑与两个开关保持可用（`speech.md` §2.1）。

### 5.3 回复状态与可见元素

| 回复状态 | 思考 / 时间线 | 正文 | 光标 | 分支 / 操作 | 朗读 | 继续 | 重新生成 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pending` | 有思考开关时显示标题「正在思考」 | 无 | 显示 | 隐藏 | 禁用 | 否 | 否 |
| `streaming` | 实时更新 | 流式 | 显示 | 隐藏 | 禁用 | 否 | 否 |
| `done` | 可折叠 | 完整 | 无 | 显示 | 可用（非拒答且有正文） | 仅 `max_tokens` 且满足续写资格 | 可用 |
| `stopped` | 保留 | 已收内容 | 无 | 显示 | 可用 | 满足续写资格 | 可用 |
| `error` | 保留 | 已收内容 + 错误 | 无 | 显示 | 有正文时可用 | 否 | 可用 |
| 拒答 | 隐藏 | 拒答文案 | 无 | 仅复制 / 版本切换 | 禁用 | 否 | 禁用 |

- 错误块：照搬 chat-demo `notice`——14/22 红色文本行，图标 `circleAlert`
  与首行顶端对齐，无标题无边框；`error_text.dart` 的本地化文案；仅 `upload`
  且 `retryable` 行内显示「重试」，其余通过「重新生成」重发。
- 拒答：正文样式，不用红色、不显示标题；隐藏时间线、来源胶囊与继续 / 重新生成。
- 停止后：无额外提示行；「继续生成」描边按钮在操作条内（满足条件时），
  图标靠左、继续生成靠右；继续后回到 `pending`。停止入口只在输入区，
  内容区不放停止按钮（同 chat-demo）。
- 操作条图标顺序：复制 → 朗读 → 重新生成；继续生成高 32、内边距 14、
  14/22 常规字重；透明底、前景同正文、1px `border` 描边（同 chat-demo outlined）。
- 分支切换器覆盖 user 与 assistant 消息；有兄弟版本时显示，格式 `当前 / 总数`，
  左右按钮 26×26；生成中禁用；切换会停止朗读。

### 5.4 思考与工具时间线

| 元素 | 状态 | 视觉 |
| --- | --- | --- |
| 思考标题 | 流式中 | 大脑图标 14 + 「思考中… N 秒」+ 光标 + 下箭头 |
| 思考标题 | 已结束有正文 | 「已思考（用时 N 秒）」；缺用时显示「深度思考」 |
| 思考标题 | 已结束无正文 | 「已停止」 |
| 思考正文 | 展开 | 13 / 1.6 muted；左边框 2；左内边距 10；不渲染链接与角标 |
| 搜索行 | `wip` | 地球图标 + 「搜索」+ 当前查询词（2 s 轮播）或「搜索中...」 |
| 搜索行 | `done` | 「已阅读 N 个网页」/「搜索到 N 个网页」；前 4 个站点缩略图；可点开来源抽屉 |
| 搜索行 | `failed` | 「联网搜索暂不可用」；用户停止时「搜索已停止」 |
| 浏览行 | `wip` / `done` | 「正在浏览网页」/「浏览 N 个页面」+ 前 5 个页面链接 |
| 浏览行 | 超过 5 页 | 追加「查看全部」 |
| 查找行 | `wip` / `done` / `failed` | 标签无图标 / 对勾 / 叉号；失败 tooltip「未查找到相关内容」 |
| 阅读行 | `wip` | 「正在阅读」+ 页名列表；结束后整行隐藏 |

- 工具行图标 16，文字 13，行间距 6，左侧图标列与正文对齐。
- 工具失败不提供单独重试；失败是回复内容的一部分。
- 思考 / 工具区只在开启深度思考时带可折叠标题；未开启时步骤区始终可见、
  无标题。
- 标题每秒刷新；搜索查询词每 2 s 轮播。

### 5.5 编辑、重新生成、继续生成

| 动作 | 入口 | 前置条件 | 结果 |
| --- | --- | --- | --- |
| 编辑提问 | 用户消息下方「编辑」 | 当前会话无生成中回复 | 输入区填入原文与附件；提交后新建同父 user 版本 + 新 assistant |
| 重新生成 | assistant 操作条 `refreshCw` | 非生成中、非拒答 | 同一 user 下新增 assistant 版本，旧分支保留 |
| 继续生成 | 满足续写资格 | 最后一条 assistant；`prefix` 为真；非拒答 / `tool_use`；无工具块与模板文本；状态为 `stopped` 或 `done + max_tokens` | 原 assistant 行状态改回 `pending`，追加块 |
| 版本切换 | 分支切换器 | 有兄弟版本、非生成中 | 改父节点 `selectedChildId` / `rootMessageId`，整条可见路径重载 |

- `prefix` 是本地「可续写前缀」标记，不是请求字段；收到客户端 `tool_use` 块即置 false。
- 续写资格以 `api.md` §6 为准，调用方还需确认它是可见路径最后一条 assistant。
- 提交编辑时停止朗读；旧分支不删除。
- 版本切换器位置：user 消息下方右侧；assistant 操作条左侧。
- 切换版本后保持滚动位置，不播放整页转场。

### 5.6 搜索与来源

- 来源登记、去重、编号与工具聚合以 `search.md` §3–§7 为准；本节只定视觉。
- 开关默认关闭，持久化；回复创建时快照。
- 「N 个网页」胶囊只在流结束、非拒答且 `searchResults` 非空时显示；
  位置在正文下方、分支 / 操作条上方。
- 胶囊：高 36，圆角 999，`card` 底 + `border`；左侧最多 4 个站点图标
  （20，圆形，叠加 -6），右侧「N 个网页」13sp；点击打开来源抽屉。
- 来源抽屉：标题「搜索结果」，全局去重列表；不做分页；下拉 / 遮罩关闭。
- 搜索行、浏览行「查看全部」、胶囊打开同一抽屉。
- 来源卡片：序号圆 18、站点图标 16、标题 13.5 两行、元信息 12、
  摘要 12 两行、URL 10 一行；整卡可点，外部打开。
- 角标：正文内 `[citation:N]` 替换为灰色数字小标签；10sp，水平 5 / 垂直 1，
  圆角 6；点击外部打开；来源缺失时移除 token。
- 思考正文不挂角标；代码块与行内代码不解析角标。

### 5.7 附件

| 阶段 | 草稿条 | 消息内 | 发送闸门 |
| --- | --- | --- | --- |
| 上传中 | 64×64 图片蒙层 + 进度；文档卡第二行「上传中...」 | 不适用 | 关闭 |
| 成功 | 正常缩略图 / 文档卡 | 图片缩略图 / 文档卡 | 打开 |
| 可重试失败 | 红描边 + 中心刷新图标；点击重试 | 不适用 | 关闭 |
| 不可重试失败 | 红描边 + 原因；只能移除 | 不适用 | 关闭 |
| 原件缺失 | 不适用 | 图片占位图标；文档「原件已丢失」 | 不进入请求 |

- 草稿附件条在输入框上方，高 76，水平滚动，间距 8；每项右上移除按钮。
- 文档卡：文件图标 16、文件名 12 单行省略、`扩展名 + 大小` 第二行；
  最大宽 210。
- 消息图片：纯图片 120×120；与文档混排 64×64；点击全屏。
- 上限：单次草稿 50 个；超限 Toast「上传文件最多支持 50 个」。
- 配额 / 大小 / 格式错误使用既有 ARB 文案；配额 Toast 带「删除文件」外链动作。

### 5.8 语音

- 输入区顺序：附件（回形针）→ 语音（麦克风）→ 发送 / 停止。
- 语音按钮：
  - `idle`：麦克风 18，`mutedForeground`；点击开始录音；
  - `recording`：红色图标 / 状态点，旁显「录音中 N 秒」；
  - `transcribing`：小型加载指示器，tooltip「正在转写，点击取消」。
- 录音状态行：输入区上方胶囊，高 36，`muted` 底；红色 8×8 状态点 +
  「录音中 N 秒」+ 5 根电平条；不显示真实波形。
- 权限拒绝：Toast「无法使用麦克风，请在系统设置中允许访问」+「打开系统设置」；
  已拒绝时朗读仍可用，语音入口不可用。
- 朗读按钮只在 assistant 操作条：
  - `idle`：`volume2` 18；
  - `loading`：4 根竖条扫光；
  - `playing`：4 根竖条起伏；
  - 点击同条停止；同一时间只有一条；录音 / 转写中置灰。
- 朗读中发送、停止生成、继续、重新生成、切会话、切分支、进后台均停止。
- 语音相关文案全部复用 `speech.md` §8 的 ARB 键。

### 5.9 系统设置交互

**通用设置**

- 主题卡片点击立即生效并持久化；选中卡片 `muted` 底。
- 语言下拉：选中立即刷新界面并关闭弹层；「跟随系统」删除 `user.locale`，
  读取时按系统语言解析。
- 位置信息：胶囊在同页锚定弹层内选择；未设置显示灰色占位；状态即时写入。
- 音色下拉：选中即写入，下一次朗读生效。
- 麦克风权限：只读三态；已拒绝时显示「打开系统设置」；`resumed` 刷新。

**数据管理**

| 操作 | 流程 | 关闭 | 结果 |
| --- | --- | --- | --- |
| Key | 输入 → 键盘完成 → 校验 | 允许 | 成功显示「已保存」；失败在输入框下显示红色错误 |
| 清除 Key | 「清除已保存的 Key」→ 直接清除 | — | 输入框回到未设置 |
| 导入 | 上传 → 覆盖确认 → 不可关闭进度 → 完成 | 进度期间禁止 | 成功 Toast 会话数；失败行内红字 |
| 导出 | 点击下载 → 进度 → 系统保存面板 | 进度期间禁止 | 成功 Toast「导出文件已保存」；失败红字 |
| 删除全部 | 删除 → 确认 → 删除 | 进度期间禁止 | 成功 Toast「已删除全部对话」 |

- 导入覆盖确认文案见 `history.md` §8；取消不提示错误。
- 导入 / 导出进度 Dialog 不可关闭，系统返回被拦截；
  生成停止与聊天页行为以 `history.md` §5 为准。
- 删除全部先停止全部生成，再在单事务内清空会话、消息与附件。

### 5.10 会话抽屉交互

- 打开：菜单按钮；关闭：左滑侧栏、点对话区、系统返回。抽屉不提供收起按钮。
- 新建对话：聊天页顶栏 `+`（当前会话有消息时显示）；空态直接用输入区开始。
  抽屉不提供新建入口。
- 会话搜索：点击侧栏搜索入口后侧栏向右展开到全屏（对话层完全移出），搜索页
  自动聚焦。输入 250ms 防抖；匹配会话标题与消息正文；防抖与查询期间显示骨架，
  空查询只显示顶部栏；无命中显示「暂无相关结果」。点结果打开会话并停在最新消息，
  同时关闭抽屉；返回箭头或系统返回让搜索层收回抽屉，系统返回在键盘打开时先收
  键盘。关闭抽屉清空查询。
- 置顶：长按菜单或多选批量操作；置顶会话进入顶部「置顶」组，组内按 `updatedAt`
  倒序；置顶不改变会话的活动时间。批量按钮按选中会话是否全部已置顶显示
  「置顶」或「取消置顶」。
- 多选：顶部工具行「多选」图标或长按菜单「多选」进入；后者进入时选中该行。
  0 选中时底部操作不可用；X、系统返回或批量操作完成都退出；与搜索互斥，
  进入一个模式自动退出另一个。
- 打开会话：替换当前聊天内容并关闭抽屉；不叠加路由栈。
- 重命名：行内输入框，回车或失焦提交，`Escape` 取消；`trim` 后为空或未改动不写库；
  空标题列表显示「新对话」。
- 删除：单条确认弹窗（「永久删除对话」+ 附件不可恢复说明）后停止该会话生成、
  删除数据库记录与孤儿附件；批量删除确认「删除 N 个对话」，先停止所选会话的生成，
  再逐个删除与回收孤儿附件。若删除当前会话，切到剩余最近会话；没有则回到空聊天。
- 当前会话高亮；列表随 drift `watchSessions()` 实时更新。
- 加载：骨架列表；失败：错误文案 + 重试。

### 5.11 Toast 与 SnackBar

- 使用 `ShadToast`，一次一条；不替代持久错误行。
- 用途：附件校验、上传配额、权限拒绝、导入 / 导出 / 删除结果、Key 校验、
  语音失败、朗读失败。
- 权限拒绝 Toast 带动作；配额 Toast 带「删除文件」动作。
- 自动消失时间 4 s；错误 5 s；到时自动消失，不提供滑动关闭。

## 6. 无障碍

### 6.1 触控与焦点

- 所有可点击目标最小 44×44；视觉图标可小于该尺寸，用透明内边距补足。
- Dialog 打开时焦点进入首个输入框或主要按钮；关闭后回到触发控件。
- Sheet 打开时焦点限制在 Sheet 内；关闭恢复。
- 硬件键盘：Tab 顺序按视觉顺序；输入区支持系统文本编辑快捷键。

### 6.2 语义标签

| 元素 | 语义 |
| --- | --- |
| 菜单按钮 | 按钮，「打开会话列表」 |
| 新建对话 | 按钮，「开启新对话」 |
| 会话标题 | Header |
| 会话搜索入口 | 按钮，「搜索对话内容」 |
| 搜索返回 | 按钮，「返回会话列表」 |
| 搜索输入框 | 文本域，占位「搜索对话内容」 |
| 清空搜索 | 按钮，「清空搜索」 |
| 多选入口 | 按钮，「多选」 |
| 会话行 | 按钮，标题 + 「当前会话」状态；长按动作「会话操作」；自定义动作「重命名」「置顶」「取消置顶」「多选」「删除」 |
| 搜索结果行 | 按钮，标题 + 相对时间 + 命中片段 |
| 选择模式标题 | 文本，「选择对话」/「已选择 N 个对话」 |
| 退出多选 | 按钮，「退出多选」 |
| 批量置顶 / 删除 | 按钮，「置顶」/「取消置顶」/「删除」；0 选中时 disabled |
| 设置入口 | 按钮，「设置」 |
| 设置导航 | Tab / 按钮，选中状态 |
| 主题卡片 | 单选按钮，选中状态 |
| 下拉胶囊 | 按钮，「语言：跟随系统」等当前值 |
| 输入框 | 文本域，hint「给 Fleepseek 发送消息」 |
| 深度思考 / 智能搜索 | 开关，选中状态 |
| 发送 / 停止 | 按钮，「发送」/「停止生成」 |
| 语音 | 按钮，随状态「语音输入」/「结束录音并转写」/「正在转写，点击取消」 |
| 用户消息 | 「你的消息」+ 文本；附件逐项标签 |
| 助手回复 | 「助手回复」；流式开始时播报一次，结束再播报一次 |
| 思考标题 | 按钮，展开状态 + 标题文本 |
| 工具行 | 文本状态；失败时包含「失败」 |
| 引用角标 | 「来源 N」+ 来源标题；不可用时从语义树移除 |
| 来源胶囊 | 按钮，「N 个网页，打开来源」 |
| 来源卡片 | 链接，标题 + 站点 + URL |
| 分支切换器 | 「上一个版本」「下一个版本」+ 「第 N 个，共 M 个」 |
| 操作条 | 「复制」「重新生成」「朗读」/「停止朗读」 |
| 附件移除 | 「移除附件」 |
| 图片 | 「查看图片」+ 文件名 |
| 录音状态 | 实时区域，只播报开始 / 转写 / 结束，不逐秒播报 |
| 朗读按钮 | 「朗读」/「停止朗读」 |

### 6.3 动态字体与对比度

- 支持 `textScaler` 0.8–2.0；不裁切、不重叠、不出现无法触达的按钮。
- 设置「字体大小」默认跟随系统；手动档位替代系统缩放。系统字号超过 2.0 时按 2.0 渲染。
- 正文与背景对比度 ≥ 4.5:1；大号文字与图标 ≥ 3:1。
- 不只用颜色表达状态：错误同时有图标 / 文本；选中有底色 + 字重；
  录音有状态点 + 文案。
- 深色模式下 `mutedForeground` 仍需可读；不使用纯灰 `#888` 硬编码。

### 6.4 减少动画与读屏

- `disableAnimations`：光标静态、箭头不转、朗读竖条静态、录音电平静态或低频、
  Sheet / Dialog 无动画。
- 流式回复不逐 token 播报；只在开始、停止、完成、出错时更新 live region
  （读屏实时区域）。
- 错误、Toast、权限结果使用 assertive / polite 合适通道；不要同时播报重复文案。
- 代码块提供「复制代码」语义；Mermaid 提供「图表」标签与源码降级文本。
- 长按文本可选择复制；`SelectionArea` 覆盖正文与代码文本。

## 7. 文案

### 7.1 规则

- 全部可见文案进 `lib/l10n/app_en.arb`（模板）与 `app_zh.arb`；禁止硬编码。
- 品牌 `Fleepseek`、`DeepSeek API Key`、URL、模型名不进翻译。
- 计数使用 ICU plural；占位符声明在模板。
- 中文用中文标点；英文用中性短句；不依赖固定宽度。
- 错误优先 `localMessage`，其次按条件映射；release 不显示服务端原文。

### 7.2 新增 / 修改的 ARB 键

| 键 | 中文 | English | 用途 |
| --- | --- | --- | --- |
| `settingsTitle` | 系统设置 | Settings | 设置 Sheet 标题（改值） |
| `settingsEntry` | 设置 | Settings | 抽屉底部设置行 |
| `newChat` | 开启新对话 | New chat | 抽屉新建按钮（改值） |
| `openSessionList` | 打开会话列表 | Open chat list | 菜单语义 |
| `sessionActions` | 会话操作 | Chat actions | 三点菜单语义 |
| `sessionGroupToday` | 今天 | Today | 会话分组 |
| `sessionGroupYesterday` | 昨天 | Yesterday | 会话分组 |
| `sessionGroupLast7Days` | 7 天内 | Last 7 days | 会话分组 |
| `sessionGroupEarlier` | 更早 | Earlier | 会话分组 |
| `sessionLoading` | 正在加载会话… | Loading chats… | 加载态 |
| `sessionsLoadFailed` | 无法加载会话 | Could not load chats | 加载失败 |
| `chatEmptyTitle` | 今天有什么可以帮到你？ | What can I help you with? | 空态标题 |
| `copy` | 复制 | Copy | 操作条 / 语义 |
| `edit` | 编辑 | Edit | 用户消息编辑 |
| `stopGeneration` | 停止生成 | Stop generating | 输入区停止按钮 |
| `thinkingForSeconds` | 思考中… {seconds} 秒 | Thinking… {seconds}s | 思考计时 |
| `webPages` | {count} 个网页 | {count, plural, =1{1 page} other{{count} pages}} | 来源胶囊 |
| `sourceNumber` | 来源 {index} | Source {index} | 角标语义 |
| `openSource` | 打开来源 | Open source | 来源语义 |
| `messageActions` | 消息操作 | Message actions | 操作条语义 |
| `assistantReply` | 助手回复 | Assistant reply | 消息语义 |
| `userMessage` | 你的消息 | Your message | 消息语义 |
| `versionPosition` | 第 {current} 个，共 {total} 个 | Version {current} of {total} | 分支语义 |
| `settingsTabGeneral` | 通用设置 | General | 设置导航 |
| `settingsData` | 数据管理 | Data | 设置导航 |
| `settingsLanguageSystem` | 跟随系统 | System | 语言选项（写回 `system`） |
| `settingsLanguageNote` | 切换后界面立即生效，已生成的回复保持原样。 | The interface updates immediately. Existing replies stay as-is. | 语言说明 |
| `settingsLocation` | 所在地 | Location | 设置行标签（改值） |
| `settingsLocationUnset` | 未设置 | Not set | 行尾所在地空值 |
| `settingsLocationNote` | 只随消息发送给你配置的 API，不申请定位权限。 | Sent only with messages to your API. No location permission is requested. | 所在地说明 |
| `settingsProvince` | 省份 | Province | 中文所在地选择 |
| `settingsCity` | 城市 | City | 中文所在地选择 |
| `settingsRegion` | 国家 / 地区 | Country / region | 其他系统所在地选择 |
| `settingsChooseProvinceFirst` | 先选择省份 | Choose a province first | 城市未选省 |
| `settingsModel` | 模型 | Model | 对话分组 |
| `settingsModelFixed` | v1 固定模型 | Fixed in v1 | 模型说明 |
| `settingsApiKeySaved` | 已保存 | Saved | Key 状态 |
| `settingsApiKeyMissing` | 未设置 | Not set | Key 状态 |
| `settingsApiKeyDescription` | 只保存在设备安全存储中，不随导出迁移。 | Stored in the device keystore. Never included in exports. | Key 说明 |
| `settingsVerifying` | 校验中… | Verifying… | Key 校验 |
| `settingsKeyVerified` | Key 校验通过 | API key verified | Key 成功 |
| `settingsClearKeyTitle` | 清除 API Key？ | Clear API key? | 确认标题 |
| `settingsClearKeyDescription` | 清除后需要重新填写才能发送消息。 | You will need to enter it again before sending. | 确认描述 |
| `clear` | 清除 | Clear | 确认按钮 |
| `done` | 完成 | Done | Sheet 完成按钮 |
| `settingsDeleteAll` | 删除全部对话 | Delete all chats | 数据管理 |
| `settingsDeleteAllDescription` | 只删除会话与附件，保留设置和 API Key。 | Removes chats and attachments. Keeps settings and the API key. | 说明 |
| `settingsDeleteAllTitle` | 删除全部对话？ | Delete all chats? | 确认标题 |
| `settingsDeleteAllConfirmDescription` | 所有会话、消息和附件将从本机删除，且无法撤销。 | All chats, messages and attachments will be deleted. This cannot be undone. | 确认描述 |
| `settingsDeleteAllAction` | 全部删除 | Delete all | 危险按钮 |
| `settingsDeleting` | 正在删除… | Deleting… | 进度 |
| `settingsDeleted` | 已删除全部对话 | All chats deleted | 成功 Toast |
| `replyFailedTitle` | 生成失败 | Generation failed | 错误块标题 |

新增键同时补 `app_en.arb` 与 `app_zh.arb`；占位符在模板的 `@key.placeholders`
声明。新增组 `session*`、`webPages`、`chatEmptyTitle` 归入会话 / 搜索文案；
`settingsLocationNone`（不指定，选择器选项）与 `settingsLocationUnset`（未设置，行尾）
含义不同，不复用。

### 7.3 复用已有键

| 范围 | 键 |
| --- | --- |
| 聊天空态 / 会话 | `noSessions`、`untitledChat`、`rename`、`renameSession`、`delete`、`deleteSession`、`deleteSessionConfirm`、`save`、`cancel` |
| 回复 | `regenerate`、`continueGeneration`、`retry`、`stopped`、`deepThinking`、`thoughtForSeconds`、`thinking` |
| 搜索 / 来源 | `searching`、`searchingQuery`、`searchingDots`、`searchStopped`、`searchUnavailable`、`noSuitableResults`、`noRelevantResults`、`searchedPages`、`readPages`、`browsingPages`、`browseFailed`、`browsePageFailed`、`findFailed`、`findKeywords`、`noMatchingContent`、`viewAll`、`searchResults`、`imageSearching`、`reading`、`browsingWeb` |
| 输入区 | `composerHint`、`send`、`stop`、`deepThinking`、`smartSearch` |
| 附件 | `uploadFile`、`uploadFromPhotos`、`uploadFromFiles`、`uploadUnsupportedFormat`、`uploadMaxMBSize`、`uploadMaxFiles`、`uploadFileStatusUploading`、`uploadFileStatusFailed`、`uploadRetry`、`uploadServerBusy`、`uploadParseFailed`、`uploadFileCountLimit`、`uploadStorageLimit`、`uploadDeleteFiles`、`removeAttachment`、`previewImage`、`missingAttachment` |
| 语音 | `voiceInput*`、`tts*`、`settingsTtsVoice*`、`settingsSpeech*`、`settingsMic*`、`settingsOpenSystemSettings` |
| 设置 | `settingsData`、`settingsTheme*`、`settingsLanguage*`、`settingsLocation*`、`settingsSaveKey`、`settingsClearKey` |
| 历史 | `historyImport*`、`historyExport*`、`historyError*` |
| 错误 | `errorNoApiKey`、`apiError*`、`replyFailed`、`replyRefused`、`replyImageBlocked` |

### 7.4 空态

| 场景 | 中文 | English |
| --- | --- | --- |
| 聊天空态 | 今天有什么可以帮到你？ | What can I help you with? |
| 空会话标题 | 新对话 | New chat |
| 会话列表空态 | 还没有会话 | No chats yet |
| 会话加载失败 | 无法加载会话 + 重试 | Could not load chats + Retry |
| 来源列表空 | 不出现入口（`searchResults` 为空不显示胶囊） | No entry shown |
| 所在地未设置 | 未设置（灰色） | Not set |
| Key 未设置 | 未设置 | Not set |

### 7.5 错误与重试

映射实现以 `lib/shared/error_text.dart` 与 `api.md` §5 为准；本表只列可见入口。

| 场景 | 中文 | English | 重试入口 |
| --- | --- | --- | --- |
| 401 | API Key 无效 | Invalid API key | 重新生成 |
| 402 | 余额不足 | Insufficient balance | 重新生成 |
| 413 | 请求内容过大 | The request is too large | 重新生成 |
| 429 | 请求过于频繁，请稍后再试 | Too many requests. Try again later. | 重新生成 |
| 5xx | 服务器繁忙，请稍后再试 | The server is busy. Try again later. | 重新生成 |
| 网络 | 网络错误，请检查连接 | Network error. Check your connection. | 重新生成 |
| 断流 / 未知 | 发生错误，请重试 | Something went wrong. Please try again. | 重新生成 |
| 内容审核 400 | 内容未通过安全审核，请修改后重试 | The content did not pass safety review. Edit it and try again. | 修改后重新生成 |
| 上传失败 | 按 `upload*` 文案 | See `upload*` copy | 仅 `retryable` 显示「重试」 |
| 无 Key | 未设置 API Key，请先在设置中填写。 | No API key set. Add one in Settings first. | 去设置 |
| 语音失败 | 语音识别失败，请稍后再试 | Speech recognition failed. Please try again later. | 再次点击录音 |
| 朗读不可用 | 这条回答暂时无法朗读 | This answer cannot be read aloud right now | 再次点击朗读 |
| 朗读失败 | 朗读失败，请稍后再试 | Read-aloud failed. Please try again later. | 再次点击朗读 |

### 7.6 确认弹窗

| 弹窗 | 标题（中 / 英） | 描述（中 / 英） | 确认（中 / 英） |
| --- | --- | --- | --- |
| 删除会话 | 删除会话 / Delete chat | 删除「{title}」？ / Delete "{title}"? | 删除 / Delete（危险） |
| 清除 Key | 清除 API Key？ / Clear API key? | 清除后需要重新填写才能发送消息。 / You will need to enter it again before sending. | 清除 / Clear（危险） |
| 导入覆盖 | 确认导入历史对话？ / Import chat history? | 上传的历史对话会覆盖当前所有对话和附件。如需保留，请先导出备份。 / The uploaded chat history will replace all your current chats and attachments. Export a backup first if you need to keep them. | 确认导入 / Import（危险） |
| 删除全部 | 删除全部对话？ / Delete all chats? | 所有会话、消息和附件将从本机删除，且无法撤销。 / All chats, messages and attachments will be deleted. This cannot be undone. | 全部删除 / Delete all（危险） |

取消统一使用 `ShadButton.outline`（中文「取消」/ English "Cancel"）；
危险确认使用 `ShadButton.destructive`。

### 7.7 Toast / 状态行

| 场景 | 中文 | English | 动作（中 / 英） |
| --- | --- | --- | --- |
| 权限拒绝 | 无法使用麦克风，请在系统设置中允许访问 | Microphone access is denied. Allow it in system settings. | 打开系统设置 / Open system settings |
| 上传配额 | 已上传文件占用空间达到上限（{limit}GB） | Storage quota reached ({limit} GB) | 删除文件 / Delete files |
| 上传数量 | 上传文件最多支持 {count} 个 | You can attach at most {count} files | — |
| 导入成功 | 已导入 {count} 个对话 | Imported {count} chats | — |
| 导入失败 | 按 `historyError*` 或通用失败 | See `historyError*` or generic failure | — |
| 导出成功 | 导出文件已保存 | Export saved | — |
| 导出失败 | 导出失败，请重试 | Export failed. Please try again. | — |
| 删除成功 | 已删除全部对话 | All chats deleted | — |
| Key 成功 | Key 校验通过 | API key verified | — |
| 语音空结果 | 未识别到语音内容 | No speech detected | — |
| 录音上限 | 已达到单次录音时长上限 | Maximum recording length reached | — |
| 朗读不可用 | 这条回答暂时无法朗读 | This answer cannot be read aloud right now | — |

## 8. 附件、语音、引用来源的呈现

### 8.1 附件

- **草稿条**：输入框上方，水平滚动；图片 64×64 圆角 12；文档卡最大宽 210，
  高约 40；上传中蒙层 / 状态行；失败红描边；右上移除。
- **消息内**：用户消息气泡上方右对齐；纯图片 120×120；与文档混排 64×64；
  文档卡只显示文件名、扩展名、大小；图片可全屏。
- **原件缺失**：图片显示 `image` 占位图标；文档显示「原件已丢失」；
  不进入请求，不提供补传。
- 具体选择、上传、补传与失败语义以 `attachments.md` §5–§7 为准；本节只定呈现。
- **禁用**：生成中、录音中、转写中禁用回形针。

### 8.2 语音

- 录音状态行在输入区上方，不占据消息区。
- 5 根电平条高 12，宽 3，间距 2，圆角 999；最低 2 dp；颜色 `destructive`。
- 录音计时每 500 ms 刷新整秒；120 秒自动结束。
- 转写中不显示电平条，显示加载指示器与「正在转写…」。
- 朗读入口只在 assistant 操作条，与复制 / 重新生成并列。
- 朗读竖条 4 根，高 12–16，宽 2，间距 3；`loading` 扫光，`playing` 起伏。

### 8.3 引用来源

- 来源登记、去重与编号规则以 `search.md` §6 为准；来源卡字段与降级以 §6.1 为准。
- 正文角标：灰色数字标签，10sp / w600；水平 5 / 垂直 1；圆角 `radiusBadge` 6；
  同一位置只出现一次；点击外部打开。
- 来源胶囊：见 §5.6；站点图标叠加顺序按来源编号；缺失图标用 `link` 占位。
- 来源抽屉卡片：序号 + 站点图标 + 站点名 + 日期 + 标题 + 摘要 + URL；
  标题两行，摘要两行，URL 一行；整卡可点。
- 来源抽屉只列 `searchResults`；只由正文引用登记的来源不进抽屉，但角标可点。
- 拒答不显示角标、来源胶囊与抽屉入口。

### 8.4 拒答、错误与长内容

- 拒答：正文样式，无红色、无标题、无时间线 / 来源；操作条只保留复制与版本切换。
- 请求错误：红色错误块 + 本地化文案；已收正文保留；错误行优先于拒答文案。
- 超长回复：完整渲染；不折叠；单块 > 200000 字符按纯文本；代码块 / 表格
  横向滚动；Mermaid 固定高 320。
- 空回复：不显示空白块；只显示状态或错误。

## 9. 现状差距与实现落点

| 现状 | 目标 |
| --- | --- |
| `HomePage` 会话列表为根页面 | 根页面改聊天页；会话列表迁入左侧抽屉 |
| `MaterialApp` + Material 主题 | `ShadApp` + `ShadThemeData` + Material 桥接 |
| 设置页为独立 Material 页面 | 系统设置 Sheet + 两段导航 |
| 聊天页使用 Material 控件 | 按 §2 组件映射替换；渲染包继续用 Material |
| 主题 / 语言 / 音色为下拉框 | 主题卡片 + 胶囊下拉 + 锚定弹层 |
| 无会话分组 | 今天 / 昨天 / 7 天内 / 更早 |
| 输入区开关为灰底选中 | 蓝色激活态 |
| 来源为样例行 / 横向卡片 | 站点图标叠加胶囊 + 底部抽屉 |
| 朗读入口在输入区原型 | 仅 assistant 操作条（已按 `speech.md` 实现） |

实现顺序建议：按屏幕分步迁移，保留 `material_ui` 渲染包，不做一次性重写；
每一步保持分析 / 测试通过。

1. `lib/app/theme.dart`：`buildShadTheme` 与 `buildShadTextTheme`；`lib/app/app.dart`
   换 `ShadApp`，保留 locale / themeMode / Material 桥接。
2. 聊天壳：`ChatHeader`、`SessionDrawer`、根路由切换；移除 `HomePage` 列表页。
3. 输入区：`Composer`、蓝色开关、附件条、语音按钮、发送 / 停止。
4. 消息区：`UserMessage`、`AssistantMessage`、思考 / 工具行、分支、操作条、
   来源胶囊与抽屉、引用角标。
5. 设置：`SettingsSheet` 两段导航、主题卡片、语言 / 所在地 / 音色锚定弹层、
   数据管理内联 Key 输入与历史行。
6. 无障碍与响应式收口：语义标签、动态字体 2.0、320 宽、横屏、平板、
   减少动画。
7. 文案：新增 ARB 键、同步中英、跑 `flutter gen-l10n`。

目标文件：

- `lib/app/theme.dart`、`lib/app/app.dart`
- `lib/features/chat/`：聊天页、消息、输入区、语音、附件
- `lib/features/search/`：来源胶囊、来源抽屉、来源卡片、引用角标
- `lib/features/sessions/`：抽屉会话列表
- `lib/features/settings/`：设置 Sheet 与行组件
- `lib/features/history/`：数据管理行
- `lib/shared/prefs/user_metadata_store.dart`：支持 `user.locale = system`，按系统语言解析
- `lib/l10n/app_en.arb`、`app_zh.arb`

## 10. 验收

### 10.1 自动测试

- 主题：浅深两套由同一种子生成；中文行高 1.6（含聊天正文）；状态栏亮度。
- 聊天壳：空态、加载、流式、停止、错误、拒答、长内容；发送 / 停止按钮态。
- 抽屉：分组、当前会话高亮、新建、重命名、删除、空态、加载失败。
- 输入区：蓝色激活开关、附件上传 / 失败 / 移除、录音 / 转写态、无 Key。
- 消息：思考折叠、工具行状态、来源胶囊、来源抽屉、角标点击、分支切换、
  操作条启用 / 禁用。
- 设置：两段导航、主题卡片、语言 / 音色 / 所在地锚定弹层、Key 校验成功 / 失败、
  导入确认 / 进度 / 失败、导出、删除全部。
- 无障碍：关键语义标签；动态字体 2.0 无溢出；减少动画；320 宽。
- 双语 × 浅深四组合：聊天、抽屉、设置、来源抽屉。

### 10.2 手动验收

1. 冷启动打开最近会话；无会话显示空态；发送首条消息创建会话。
2. 抽屉按今天 / 昨天 / 7 天内 / 更早分组；当前会话蓝色高亮；底部设置按钮打开设置。
3. 输入区激活开关为蓝色；发送 / 停止切换正确；附件与语音禁用态正确。
4. 助手正文通栏；来源胶囊显示图标叠加与 `N 个网页`；点击打开来源抽屉。
5. 思考 / 搜索时间线状态与文案符合 §5.4；拒答无来源与操作。
6. 分支切换覆盖 user / assistant；切换停止朗读；旧分支保留。
7. 系统设置两段导航；主题卡片即时生效；语言跟随系统 / 中 / 英；音色选择持久化。
8. Key 校验、清除、所在地选择、权限状态与跳系统设置正确。
9. 导入 / 导出 / 删除全部的状态行、确认与不可关闭进度正确。
10. VoiceOver / TalkBack 朗读顺序与标签正确；动态字体 2.0、减少动画、深色对比度通过。

## 11. 交接与未决

- 票 11：把本文并入 `spec.md` 的 UI 章节。
- 票 19：v1 验收用例引用 §10 与 `speech.md` §11。
- 实现票：按 §9 顺序拆分为可独立验收的改动；每步保持 `flutter analyze` 与
  `flutter test` 通过。
- 品牌 `Fleepseek` 为占位显示名；正式名称由发布票决定，不影响本文布局。
- 用户参考截图中的分享、点赞 / 点踩不在 v1 功能清单内，本文明确不渲染；
  若后续加入，另开票并补按钮态与无障碍标签。
- `search.md` 的来源卡视觉由本文 §8.3 收口；搜索步骤行不使用原型进度卡。
- 超长消息折叠、模型切换、抽屉搜索均不进入 v1。
