# 按住说话交互与 record 能力调研

Type: research
Status: resolved
Blocked by:

## Question

现有语音链路由 `record` 7.2.0 + `SpeechController` 实现「点击开始、再点结束」。改为「按下即录、松手结束、上滑取消」前，用一手来源（`record` 官方文档/源码、Flutter 手势文档、DeepSeek 参考行为）回答：

1. 启动延迟：按下后先做 Key 读取与麦克风权限检查（异步），录音真正开始的延迟范围；权限已授予与首次请求两条路径；如何给用户即时反馈（按下态）。
2. 结束语义：`record` 的 `stop()` / `cancel()` / 临时文件；松手时停止的可靠性与耗时；取消是否保证删除文件。
3. 手势：`Listener` vs `GestureDetector` vs `RawGestureDetector` 实现「按住 + 上滑取消」的推荐方案；`onPointerCancel`、滑出按钮、滑出屏幕、多指、系统返回手势的边界。
4. 中断：来电、音频路由变化、进后台、切会话时 `record` 的行为与现有 `interruptions` 流。
5. 电平：`onAmplitudeChanged` 频率、归一化区间、生成浮层波形的最小重构策略。
6. 上限：120 秒自动停止后自动转写并发送的时序。
7. 无障碍：TalkBack/VoiceOver 下长按的语义替代动作（semantics action）推荐实现。

## Deliverable

`evidence/hold-to-talk.md`：时序/状态迁移建议、API 事实与来源、风险；票内 Answer 摘要。不改产品代码。

## Answer

完整证据与来源见 `evidence/hold-to-talk.md`（2026-11-20，基于本机 `record` 7.2.0 / `record_darwin` 2.0.0 / `record_android` 2.3.0 源码、Flutter SDK 手势源码与 Apple/Android 官方文档）。

**手势一句话**：用 `Listener` 在麦克风按钮上直接处理 pointer down/move/up/cancel，按 pointer id 跟踪单指、以全局 `dy ≤ -80` 判定上滑取消；不要用 `GestureDetector` 长按（500 ms 才触发，且长按被接受后系统 cancel 不会回调 `onLongPressCancel/End/Up`，状态会悬挂）。

关键事实：

1. **启动路径**：现有 `_startRecording` 在 `recorder.start()` 前串行读 Key（secure storage）、查/请求权限；`DeviceSpeechRecorder.start` 内部还有 recorder create、`listInputDevices`、临时目录创建、旧文件清理。平台 `start` 的 Future 在 capture 真正运行时才返回。可确定的硬界只有 Android 蓝牙 SCO 等待上限 2500 ms（`BluetoothManager.kt:12-13`）；正常已授权路径的实际毫秒数**未验证**，需真机分段埋点。
2. **首次权限**：系统弹窗可能让 Flutter 收到 `PointerCancelEvent`，授权后不会有 `PointerUp`。若未检查 pointer 仍在按下就开录，会出现「无人按住仍录音」。首次授权应请求后不开录（或确认 pointer 仍 down），由票 05 定文案。
3. **即时反馈**：`onPointerDown` 同步显示按下态/浮层骨架；`recording` 与 120 秒计时只在 `recorder.start()` 成功后开始。松手早于 start 完成时，start 返回后立即 cancel，不转写。降延迟最小改动：缓存权限状态、预热 `AudioRecorder`、Key 读取并发/缓存、设备枚举移出热路径、旧文件清理移出、`stop()` 后不等 `dispose()`。
4. **stop/cancel**：`stop()` 收尾并返回路径、不删文件；`cancel()` 收尾并删文件；两者都等平台完成。iOS 关闭 `AVAudioFile` 写尾，Android flush 剩余 PCM 并停 encoder。删除是尽力保证（失败被吞），wrapper 二次删除 + 下次启动清理兜底。`SpeechApi` 在读字节后删除临时文件。
5. **状态竞争**：现有 `toggleVoiceInput` 在 `transcribing` 分支会取消转写，不能拿来当松手处理（120 秒 cap 先触发后，松手会误取消）。必须新增显式 `startFromPress / finishFromRelease / cancelFromGesture`，并用 `_starting` 单飞防连按双开录音；cap 与松手用现有 `_recording == null` + token 幂等闸门。
6. **中断**：`audioInterruption: pause` + `audioRouteChange: pause` 正确；来电/路由丢失都会发 `RecordState.pause` 且不自动恢复。iOS 14.5+ 的 `prefersNoInterruptionsFromSystemAlerts` 只对横幅式来电生效，全屏来电仍会响铃即中断。Android 依赖 audio focus，厂商差异**未验证**。后台：仓库无 `UIBackgroundModes: audio`、无 microphone FGS，只支持前台，现有生命周期取消正确。建议改用 7.2.0 `onStopped()` 的 reason（interruption/routeChange/error）并补 stream `onError`。
7. **电平/波形**：`onAmplitudeChanged(100ms)` 是 Dart 定时器 + 每 tick 两次平台调用并串行化，实际约 10 Hz 或更低；值是 dBFS（静音 -160）。复用 `SpeechController.level` + 本地缓动/插值做浮层波形，不要新增录音通道，也不要降到 50 ms 以下。
8. **120 秒**：cap 从实际开录计时；到期自动 stop → 转写 → 成功后自动发送。cap 先触发后松手必须 no-op；转写取消只来自发送槽加载圈或生命周期。自动发送失败（Key/上传闸门/建会话）建议回退插入文本，否则丢失转写结果；由票 05 定。
9. **无障碍**：`Listener` 不自动产生 semantics；外层 `Semantics(button, label, onTap)` 用 tap 切换开始/停止，录音中加 `customSemanticsActions`「取消录音」。不要依赖 `Semantics.onLongPress`：它只有单个回调，没有对应的「松手」语义事件。

仍存风险：启动/停止真实耗时未测；首次权限弹窗的 pointer cancel 行为需真机确认；Android 来电 focus 时机不确定；`Listener` 不参与 gesture arena，若输入区将来放进可滚动父级会同时滚动；DeepSeek 无公开交互规范，未作为一手来源（截图参考为微信风格）。
