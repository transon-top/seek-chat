# 启动失败的错误界面

Type: grilling
Status: resolved
Blocked by: 02

来源：原 `.scratch/flutter-deepseek-chat/issues/22-startup-failure.md`。
原功能规格目录已在整理进 `docs/features/` 后删除；本文保留未实现的决策问题。

## Question

v1 规格汇总时发现启动失败只有行为原则、没有界面规格：

- 启动顺序中「启动失败的处理」没有完整覆盖；
- 数据模型规格只规定「迁移失败进入可重试错误态，不自动清库」。

需要决定：

1. 启动顺序中哪些失败可降级、哪些必须阻塞：数据库打开失败、迁移失败、
   `SharedPreferences` 读取失败、附件孤儿清理失败。附件清理已定为不阻塞，
   其余是否沿用同一降级策略？
2. 应用级错误界面的形态：文案、重试、退出、是否提供「重置本地数据」危险入口
   （默认不自动清库，重置是否进入 v1）。
3. 错误落点：`main()` 捕获后渲染专用页面，还是进入 `ProviderScope` 后由应用壳
   展示；与首帧主题 / 语言偏好的关系。
4. 测试接缝：内存库 / 注入失败替身覆盖哪些路径。

产出：决策文档、应用级错误界面规格、ARB 键与对应测试。
实现完成后，把稳定行为收敛到 `docs/features/`，再删除本目录。

## Answer

已解决（2026-11-23）。依据票 02（`research/startup-failure-best-practices`
分支 `584dff1`，`docs/research/startup-failure-best-practices.md`）。
用户已确认五题全部按推荐方案执行。

### 1. 启动链与降级策略

启动顺序改为：

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `SharedPreferences.getInstance()`（提前到数据库之前）
3. 打开数据库并 `resetInterruptedReplies()`
4. debug 样本写入（仅 debug）
5. 附件孤儿清理
6. `runApp` 真实应用

- **阻塞并进入启动失败页**：数据库打开/迁移失败、`resetInterruptedReplies()`
  失败、`SharedPreferences.getInstance()` 失败。
- **不阻塞**：debug 样本写入失败（现状）、附件孤儿清理失败（现状）。
- **重试 = 从头重跑整条启动链**：新建 `AppDatabase` 实例、重新
  `getInstance()`。不复用缓存的失败实例——drift 会缓存迁移错误，
  `LazyDatabase` 会缓存 opener 失败 Future。
- **前置改动**：`lib/shared/data/database.dart` 的 `onUpgrade` 按 drift
  官方建议包进事务。迁移失败回滚、schema version 不前进，重试才可重复。

### 2. 启动失败页

- **落点**：`main()` 内 try/catch。失败时二次 `runApp` 一个最小错误 App
  （`ShadApp`），不进入 `ProviderScope`；重试成功后二次 `runApp` 真实应用。
  错误 App 不塞进 `ErrorWidget.builder`（该钩子只兜 build 失败）。
- **主题与语言**：prefs 已读到时用已存 `ThemeMode` 与 `locale`；未读到时用
  `ThemeMode.system` + `locale: null`（由系统解析）。
- **布局**：错误图标 + 标题 + 说明 + 主按钮「重试」+ 危险按钮
  「清除本地会话与附件」。不设退出按钮。
- **可访问性**：文案全走 ARB；说明文字为 `liveRegion`；标题为语义 header；
  点击目标 ≥ 48×48；对比度 ≥ 4.5:1；随系统字号放大到 200%；页面不自动消失。
- **debug**：原始异常附在说明后；release 不显示。

### 3. 清除本地数据

- 二次确认后执行；确认文案逐项写明删除与保留范围。
- **删除**：先 `await database.close()`，再删
  `<support>/seek_chat.sqlite` 及 `-journal` / `-wal` / `-shm`、
  旧名 `open_chat.sqlite` 及同套附属文件、`<support>/attachments/` 整个目录。
- **保留**：`SharedPreferences` 中的设置与安全存储中的 API Key。
- 不调用 Android `clearApplicationUserData()`：会撤销权限、清通知，
  跨平台语义不一致。
- 删除成功后自动重试启动；删除失败留在错误页并显示失败提示，不清库、
  不自动重试，用户可再次操作。
- 重置不承诺原子性：部分删除后再次执行应继续完成剩余删除。

### 4. ARB 键

复用现有 `retry`（重试 / Retry）、`cancel`（取消 / Cancel）。新增：

| key | en | zh |
| --- | --- | --- |
| `startupFailedTitle` | Cannot open SeekChat | 无法打开 SeekChat |
| `startupFailedBody` | Local data could not be read. Try again; if the problem persists, clear local chats and attachments to start over. | 本地数据读取失败。可以重试；若持续失败，可清除本地会话与附件后重新开始。 |
| `startupClearData` | Clear local chats and attachments | 清除本地会话与附件 |
| `startupClearDataConfirmTitle` | Clear local chats and attachments? | 清除本地会话与附件？ |
| `startupClearDataConfirmBody` | All chats, messages, and attachment originals will be permanently deleted. Settings and the API key are kept. This cannot be undone. | 将永久删除全部会话、消息与附件原件。设置与 API Key 保留。此操作无法撤销。 |
| `startupClearDataConfirm` | Clear | 清除 |
| `startupClearDataFailed` | Could not clear data. Try again. | 清除失败，请重试。 |

### 5. 测试

抽 `bootstrap(deps)`：数据库工厂、prefs 加载、残留回复收尾、附件清理、
debug 样本全部可注入；`main()` 只注入真实实现与 `runApp`。

`test/app/startup_test.dart` 覆盖：

1. 数据库打开/迁移失败 → 启动失败页出现（标题、说明、重试、清除按钮）。
2. 重试：首次失败、第二次成功 → 数据库工厂被调用两次，进入聊天页。
3. prefs 失败 → 启动失败页，主题/语言取系统默认。
4. prefs 成功 + 数据库失败 → 启动失败页沿用已存主题/语言。
5. 附件孤儿清理抛 `FileSystemException` → 正常进入。
6. debug 样本写入失败 → 正常进入。
7. 清除数据：临时目录预置主库、`-journal`、`-wal`、`-shm`、旧库与附件，
   确认后全部删除；设置与 API Key 保留；随后重试成功。
8. 清除前数据库连接已关闭（替身记录 `close()` 先于文件删除）。
9. 清除失败 → 页面显示 `startupClearDataFailed`，数据不再被自动改动。
10. 错误页可访问性：`liveRegion`、语义标题、≥ 48×48 点击目标。
11. 迁移事务：迁移中途失败后回滚，schema version 不变，可再次迁移成功。

实现完成后：更新 `docs/features/README.md` 的未实现条目，新增启动行为规格，
补 ARB 生成物与测试，再删除本目录。本次不单独立 ADR：决策记录在本票，
若该错误壳扩展为通用运行时错误界面，再升级为 ADR。
