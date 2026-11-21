# 按住说话状态机与浮层行为

Type: grilling
Status: resolved
Blocked by: 02

## Question

依据《按住说话交互与 record 能力调研》的手势与 `record` 事实，锁定按住说话的完整状态机：

1. 时序：按下 → 权限/Key 检查 → 录音开始 → 浮层出现；检查失败各分支的反馈与是否停留浮层。首次麦克风授权时系统弹窗会让 pointer cancel 且授权后无 PointerUp——定「授权后不开录、提示再按住」还是「确认 pointer 仍 down 才开录」；定短按（按下即松）是走空录音提示还是直接取消静默。
2. 松手：停止 → 转写 → 自动发送；转写期间浮层与按钮状态；失败/空结果的提示与输入框归宿；发送被上传闸门拦住、Key 缺失、建会话失败时的行为——定自动发送失败是否回退把文本插入输入框，避免转写结果丢失。
3. 上滑：80dp 阈值以什么为基准、回拉是否恢复、松手取消的触感与文案；横向滑动是否也取消。
4. 浮层：覆盖范围（是否盖住顶部栏/输入卡）、蓝色渐变、文案「松手发送，上滑取消」/「松开取消」、波形（复用 `level` 还是定时动画）、深/浅色。
5. 中断：来电、路由变化、切会话、后台、页面销毁、120 秒上限；录音中面板展开或键盘弹起的处理。
6. 互斥：朗读中、生成中、附件上传中按麦克风的可用性与提示。
7. 无障碍：调研结论是长按没有语义等价（`Semantics.onLongPress` 只有单回调、无松手事件）；定是否改为「双击开始、再双击结束并发送」的 tap 切换，录音中提供「取消录音」自定义动作，以及状态播报文案。

## Deliverable

票内 Answer + 状态迁移表；票 07 汇总到 `speech.md`。

## Answer

2026-11-21 经一轮 grilling 确认。事实基线见 `evidence/hold-to-talk.md`；现有实现见 `lib/features/chat/speech/speech_controller.dart`。

### 1. 启动路径

- `onPointerDown` 立即：输入框失焦、收起键盘、收起附件面板、显示浮层骨架（静止低幅波形）。
- 随后单飞执行：读 Key → `isGranted()` → `request()` → `recorder.start()`。`_starting` 标记防连按双开。
- Key 缺失、权限拒绝、无设备、`start()` 失败：收起浮层，弹现有 Toast（`noApiKey` / `permissionDenied` / `noDevice` / `failed`）。
- 首次授权：系统弹窗会让 Flutter 收到 `PointerCancelEvent`，之后不会再有 `PointerUp`。授权成功后**不自动开录**，收起浮层并提示「已授权麦克风，请再按住说话」（新 ARB 键，票 07 汇总）。不存在「确认 pointer 仍 down」的可行实现。
- 松手早于 `start()` 返回：置取消标记，`start()` 返回后立即 `cancel()`，不转写、不提示。
- `start()` 已成功但录音极短：正常 `stop()` → 转写，空结果走现有 `VoiceInputFailure.empty`。不设最短时长门槛。

### 2. 松手与自动发送：先插入、再尝试发送

转写成功 → 把文本插入输入框 → 满足发送条件（无生成中、附件全部 `done`、有 Key、会话可用）才复用现有 `_send()`。

- 发送成功：由 `_send()` 现有逻辑清空输入。
- 任一条件不满足：只插入、不发送，用一行 Toast 说明原因；转写结果永不丢失。
- 转写期间用户手动输入了新文本：只插入、不自动发送。
- 有附件上传中/失败：只插入、不发送；上传闸门不因语音打开。
- 建会话或发送抛错：文本留在输入框 + Toast；空会话按现有 `_discardEmptySession` 清理。
- 转写失败/空结果：不插入，走现有 `empty` / `failed` Toast。
- 转写中按发送槽加载圈：取消转写、丢弃结果、不插入（现有行为）。
- 120 秒 cap 已触发后松手：no-op。

### 3. 上滑取消

- 阈值以按下瞬间的全局坐标为基准：`pressStartGlobalY - currentGlobalY >= 80`，与按钮/屏幕几何无关。
- 实时判定：越过进入取消态，回拉到 80dp 内恢复发送态，松手按当下状态结算。
- 横向位移不取消；手指滑出按钮范围不影响录音，只有抬起或 `PointerCancel` 结束。
- 触感：进入取消态 `HapticFeedback.mediumImpact`，恢复 `lightImpact`。
- 松手取消：静默丢弃、无 Toast，浮层消失。`PointerCancel` 一律丢弃；仅来电/路由中断保留 interrupted Toast。

### 4. 浮层

- 只贴底覆盖输入卡与草稿行并向上延伸（约 40% 屏高，内容自适应）：不盖顶部栏、不遮消息列表、不加全屏遮罩、不响应点击。
- 录音期间输入卡不可编辑（覆盖《空态布局、按钮矩阵与附件面板》中「录音期间输入框仍可编辑」一句；转写中浮层已消失，输入框恢复可编辑）。
- 文案：常态「松手发送，上滑取消」；取消态「松开取消」并转暖色/警示色，靠文案加颜色双重区分。
- 波形：复用 `SpeechState.level`，本地插值缓动到约 30fps，约 32 条、有静止基线；录音未开始时静态低幅骨架。
- 出现/消失 150ms 淡入 + 上移 8dp；取消态切换 120ms；减少动画时归零。
- 渐变色值与波形形态（深/浅色两套）由票《输入区视觉对图原型》确认。

### 5. 中断与页面交互

- 来电/路由变化：丢弃录音 + 现有 interrupted Toast，不自动恢复。
- 切会话、离开页面、进后台、页面销毁：静默丢弃（`stopAll`），转写取消、不上传、不插入。
- 120 秒：自动停止 → 转写 → 按第 2 节发送；保留 `limitReached` Toast；cap 后松手 no-op。
- 录音中 `+` 禁用、面板不会出现（票 03）；录音开始时必然已收起面板。
- 录音中按 Android 返回键/返回手势：第一次只取消录音并留在页面，不弹侧栏、不退出。
- 录音中键盘弹起不予处理（按下时已收起）。

### 6. 互斥

沿用票 03 矩阵。本票确认：上传中允许开始录音，转写结果按第 2 节只插入不发送；朗读中麦克风禁用且无提示；`_startRecording` 中「确认可录音后停朗读」保留作竞态缓冲。

### 7. 无障碍

- 麦克风外层 `Semantics(button: true)` 提供 `onTap` 切换：空闲点击开始（不需按住），录音中点击结束并转写发送。
- 录音中提供 `customSemanticsActions`「取消录音」。
- 读屏激活时语义点击优先于指针手势；普通用户仍走 `Listener` 按住路径。
- 播报：开始「录音中，双击结束并发送」，取消「已取消」，转写「正在识别」，发送失败「发送失败，已放入输入框」；浮层文案 liveRegion，仅状态变化时播报。ARB 键由票 07 汇总。

### 状态迁移表

| 当前 | 事件 | 动作 | 下一状态 | 可见 |
| --- | --- | --- | --- | --- |
| idle | 麦克风 pointer down | 失焦、收键盘、收面板、显示浮层骨架、启动单飞 | starting | 浮层骨架 |
| starting | `start()` 成功且 pointer 仍有效 | 建 session、启动电平/计时/cap | recording | 浮层波形 |
| starting | 已松手或已取消 | `session.cancel()`，不转写 | idle | 浮层消失 |
| starting | Key/权限/设备/启动失败 | 收起浮层 + 对应 Toast | idle | Toast |
| starting | 首次授权导致 pointer cancel | 不开录；授权成功提示再按住 | idle | Toast「已授权…」 |
| starting | 其他 pointer cancel | 置取消标记，`start()` 返回后 cancel | idle | 浮层消失 |
| recording | 上滑 ≥ 80dp | 进入取消态（medium 触感） | cancelling | 暖色「松开取消」 |
| cancelling | 回拉 < 80dp | 恢复发送态（light 触感） | recording | 蓝色「松手发送，上滑取消」 |
| recording | pointer up | stop → 转写 | transcribing | 浮层消失、发送槽加载圈 |
| cancelling | pointer up | 丢弃录音，静默 | idle | 浮层消失 |
| recording / cancelling | pointer cancel、来电、路由中断 | 丢弃；中断加 interrupted Toast | idle | 依分支 |
| recording / cancelling | 系统返回（页面未销毁） | 取消录音，停留页面 | idle | 浮层消失 |
| recording | 120 秒 cap | 自动 stop → 转写 → 尝试发送 | transcribing | `limitReached` Toast |
| transcribing | ASR 成功非空 | 插入输入框 → 可发送则 `_send()` | idle | 失败时 Toast |
| transcribing | ASR 空/失败 | 不插入，empty/failed Toast | idle | Toast |
| transcribing | 发送槽点击、后台、切会话 | 取消转写、丢弃 | idle | — |
| transcribing | cap 后松手 | no-op | transcribing | — |
| 任意 | 页面销毁 | `stopAll` 静默清理 | — | — |

## Comments

- 2026-11-21（票《输入区视觉对图原型》确认）：识别中保留同一蓝色动态浮层，文案「识别中」，波形退化为低幅基线；覆盖本票状态表中 transcribing「浮层消失、发送槽加载圈」的可见结果。浮层高光锚定按住位置，蓝色区域为漂移团块、动态不规则边缘；上滑取消复用同一蓝色效果，不再转暖色/红色（覆盖 §4 的「转暖色/警示色」）。识别中不提供取消入口，等 ASR 返回或失败；后台、切会话仍静默取消。
