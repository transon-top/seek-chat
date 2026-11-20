# 按住说话调研：`record` 7.2.0、手势与中断

- 调研日期：2026-11-20
- 范围：`record` 7.2.0 + `record_darwin` 2.0.0 + `record_android` 2.3.0 + `record_platform_interface` 2.2.0；Flutter SDK（本机 `/Users/transon/flutter`）；Apple / Android 官方文档。
- 目标：为票 05 的状态机与票 07 的规格回写提供可判定事实；不改产品代码。
- 术语按 `GLOSSARY.md`：Voice Input（语音输入）。

## 0. 结论摘要

1. **手势推荐 `Listener`**：在麦克风按钮上直接处理 `onPointerDown / onPointerMove / onPointerUp / onPointerCancel`，用 pointer id 过滤多指。`GestureDetector` 的长按默认 500 ms 才触发；更严重的是长按被接受后，系统发 `PointerCancelEvent` 时 `LongPressGestureRecognizer` 不会回调 `onLongPressCancel/End/Up`，按住状态会悬挂。
2. **按下即录需要新入口，不能复用 `toggleVoiceInput`**：现有 `toggleVoiceInput` 在 `transcribing` 分支会取消转写；120 秒上限先触发后，用户松手会误取消转写。应拆成显式 `startFromPress / finishFromRelease / cancelFromGesture`（或等价方法）。
3. **启动延迟不来自录音引擎本身，而来自串行前置步骤**：现有路径先读 Key（secure storage）→ 查权限 → 查设备列表 → 建临时目录 → 清理旧文件 → 才 `recorder.start()`。可确定的最坏界：Android 蓝牙 SCO 连接等待上限 2500 ms；首次权限请求等待用户，无上限。正常已授权路径的实际毫秒数**未验证**，需真机埋点。
4. **停止语义**：`stop()` 结束并释放录音资源、返回路径、不删文件；`cancel()` 结束并删除文件。两者都要等平台完成才返回。iOS 关闭 `AVAudioFile` 写入文件尾，Android flush 剩余 PCM 并停止 encoder；耗时**未验证**，但不应阻塞浮层收起。
5. **取消删除是「尽力保证」**：平台在 `cancel()` 返回前删除文件，失败被吞（iOS `try?`、Android 只捕获 `SecurityException`）；现有 wrapper 再删一次，下次启动还会清理残留。不能承诺文件系统层面 100% 删除。
6. **中断配置已正确**：`record` 配了 `audioInterruption: pause` + `audioRouteChange: pause`，来电/路由丢失都会发 `RecordState.pause` 且不自动恢复；现有 `session.interruptions` 会丢弃录音。建议改用 7.2.0 的 `onStopped()` 原因（interruption/routeChange/error）并处理 stream error。
7. **电平只有约 10 Hz 的 dBFS 峰值**：`onAmplitudeChanged(100ms)` 是 Dart `Timer.periodic` + 每 tick 一次平台 `getAmplitude()`；异步调用串行化，实际频率可能低于 10 Hz。浮层波形应复用 `SpeechController.level` + 本地缓动/插值，不要新增录音通道，也不存在真实波形数据（文件录音模式不暴露 PCM）。
8. **120 秒上限**：现有 cap timer 在 `recorder.start()` 完成后才开始计时，符合「实际录音 120 秒」。到期后自动停止 → 转写 → 成功后自动发送；松手事件必须变为 no-op，不能走 `toggleVoiceInput` 的「转写中取消」。自动发送失败时应回退插入文本，否则转写结果丢失（产品决议）。

## 1. 启动路径与延迟

### 1.1 现有路径分解

`_startRecording`（`lib/features/chat/speech/speech_controller.dart:244-310`）在真正开录前串行做：

1. `_readKey()`：`flutter_secure_storage.read`（`lib/shared/security/api_key_store.dart:12`），每次按下都读 Keychain / Keystore，无内存缓存。
2. `_permissions.isGranted()`：`permission_handler` 平台查询（`lib/shared/speech/permissions.dart:29-30`）。
3. 未授权则 `_permissions.request()`：系统权限弹窗，等待用户，无上限（`permissions.dart:33-36`）。
4. `if (state.reading) await stopReadAloud()`：现有按钮在朗读中禁用，按住说话同样应禁用，因此正常不可达。
5. `DeviceSpeechRecorder.start()`（`lib/features/chat/speech/recorder.dart:34-63`）内部再串行：
   - `AudioRecorder()` 构造，异步 `create` 平台 recorder（`record-7.2.0/lib/src/record.dart:32-41`）；
   - `listInputDevices()`（`recorder.dart:37`）；
   - `getTemporaryDirectory()` + `Directory.create()`（`recorder.dart:39-42`）；
   - `_removeStaleFiles()` 遍历删除旧文件（`recorder.dart:43, 66-75`）；
   - `recorder.start(config, path)`（`recorder.dart:45-57`）。
6. `AudioRecorder.start()` 等构造期的 `_createFuture`，再拿 semaphore，再调平台 `start`（`record-7.2.0/lib/src/record.dart:249-257`）。平台 `start` 的 Future 在「capture 真正运行或失败」时才完成（Android：`RecorderWrapper.kt:101-110`；iOS：`RecorderController.swift:138-173`，`engine.start()` 成功后才 `moveTo(.record)`）。

所以「按下 → 可录音」至少包含 2 次权限/存储通道往返 + 1 次 recorder create + 1 次设备枚举 + 2 次文件系统/路径调用 + 1 次音频引擎启动。`getTemporaryDirectory` 首次之后有缓存，但仍然 async。

### 1.2 两种时序

**A. 权限已授予、Key 存在（热路径）**

```
pointerDown
  → 同步进入「按下」视觉态（本地 setState，0 帧等待）
  → readKey（平台通道）
  → isGranted（平台通道）
  → AudioRecorder create（若未预热）
  → listInputDevices
  → temp dir + 清理旧文件
  → recorder.start：
       iOS: AVAudioSession setPreferredSampleRate / setCategory / setActive
            → AVAudioEngine open + installTap + prepare + start
       Android: 投递到控制线程 → 可选 Bluetooth SCO 等待 → AudioRecord/encoder 启动
  → phase=recording，开始 120 秒计时与电平订阅
```

可确定的界：
- Android 蓝牙 SCO：`SCO_CONNECT_TIMEOUT_MS = 2_500L`（`record_android-2.3.0/.../BluetoothManager.kt:12-13, 46-48`）。连接蓝牙耳机且 SCO 广播不来时，`start` 最多等 2.5 秒。无蓝牙设备时 `BluetoothReceiver` 立即 `notifyReady()`（`BluetoothReceiver.kt:95-103`）。
- 其余步骤的单次毫秒数无官方保证；**未验证**。需在真机用 `Stopwatch` 分阶段埋点（key / permission / create / list / dir / start）。

**B. 首次请求权限**

```
pointerDown
  → readKey
  → isGranted=false
  → Permission.microphone.request() → 系统弹窗（时长由用户决定）
  → 用户允许 → 继续 recorder.start
  → 用户拒绝 → Toast permissionDenied，不录音
```

关键边界：系统权限弹窗会让 App 进入 `inactive`（iOS 明确；Android 视系统版本/厂商）。弹窗出现时，Flutter 很可能收到 `PointerCancelEvent`，用户允许后也不会有对应的 `PointerUpEvent`。若此时直接开录，会出现「没有手指按着却在录音」。因此首次请求必须：
- 记录发起手势的 pointer 是否仍处于 down；
- 若已 cancel/up，授权成功后不开录（或按产品决议提示「请再按住说话」）；
- 或把首次授权改成「点击请求、下次按住才录」。

### 1.3 即时反馈与快速抬手

- **按下 0 延迟反馈**：`onPointerDown` 同步设置本地按下态（按钮缩放/浮层骨架/「启动中」），不要等 controller 的 `recording` 状态。`recording` 状态只在 `recorder.start()` 返回后设置（`speech_controller.dart:275-286`）。
- **浮层可立即出现，但计时/波形从实际开录算**：`_recordStartedAt` 目前在 start 成功后设置（`speech_controller.dart:278`），这是正确的；不要改成按下时间。
- **松手早于 start 完成**：必须支持「待取消」标记。start 返回后若手指已抬起/取消，立即 `session.cancel()`，不转写。否则会出现无人按住的录音，直到下次操作。
- **快速点击**：按下即录会让「点一下」也触发 start/stop。建议语义：短按仍按「空录音」处理（`EmptyRecordingException` / 空文本 Toast），或在 start 未完成时直接取消并不提示；需在票 05 定。

### 1.4 降延迟的最小改动（按收益排序）

1. **权限状态内存缓存**：App resume / 权限请求后刷新一个 `bool`；按下时若为 `true`，跳过 `isGranted()` 通道往返。权限在系统设置被撤销的情况由 resume 刷新兜底。
2. **预热 `AudioRecorder`**：构造 `AudioRecorder()` 只创建平台 recorder 与 event channel，不激活麦克风（iOS `RecorderChannel.create` 只建 controller/channel，`RecorderController` 构造不碰 `AVAudioSession`；Android 只建 wrapper）。在输入区挂载或 App 启动时创建，按下时直接 `start`。
3. **把 Key 读取移出关键路径**：转写前还会再读一次 Key（`speech_controller.dart:339`），所以按下时可以把 `_readKey()` 与权限检查并发；若 Key 缺失，start 后立刻 cancel 并 Toast。若产品要求「无 Key 不申请权限」，则保留前置顺序，仅做内存缓存。
4. **设备枚举移出热路径**：`start` 本身会在无设备时失败；Android 返回 `no_input_device`（`RecorderWrapper.kt:163-166`），iOS 把 `noInputDevice` 映射成 `startFailed`（`RecorderController.swift:169-170`）。可保留 `listInputDevices` 仅用于 iOS 的「无设备」文案，但缓存结果或并发执行，不要串行阻塞。
5. **旧文件清理移到非关键路径**：App 启动或上次转写成功后清理；不要每次按下都遍历目录。
6. **`stop()` 后不等 `dispose()`**：路径已由 `stop()` 返回，转写只需要文件；`record` 的 `dispose` 还会 `isRecording`、关流、平台销毁（`record.dart:198-213`），可 `unawaited` 放后台，缩短「松手 → 转写请求」。
7. **不要为了「已授权」而跳过权限检查仍开录**：麦克风权限可能在设置中被撤销；至少用缓存 + resume 刷新，启动失败走 Toast。

## 2. `record` 的 start / stop / cancel、临时文件与状态竞争

### 2.1 API 事实

| API | 文档/源码事实 | 对本功能的影响 |
| --- | --- | --- |
| `start(config, path)` | 「Starts new recording session」；IO 平台 `path` 必填；失败抛 `PlatformException`（code `record`）。平台侧在 capture 真正运行时才完成 Future（Android `RecorderWrapper.kt:101-110`；iOS `RecorderController.swift:157-163`）。同一 recorder 上再次 `start` 会先结束当前 take（`RecorderController.swift:144-145`；`RecorderController.kt:49-50`）。 | 必须用「start 完成」作为进入 `recording` 的界；不能用平台调用发出时间。我们在同一 take 内只调一次。 |
| `stop()` | 「Stops recording session and release internal recorder resource」「Returns the output path if any」；不删文件。iOS 关闭 `AVAudioFile` 写入文件尾（`AudioEngineCapture.swift:112-125`；`CaptureOutput.swift:84-93`）。Android 先 flush 剩余 PCM、停止 encoder/container，再返回路径（`PcmCaptureEngine.kt:109-117`；`RecorderWrapper.kt:117-118`）。 | 松手后路径可用；文件保留给转写。`speech_api` 读完后删除（`speech_api.dart:64-69`）。 |
| `cancel()` | 「Stops and discards/deletes the file/blob」。iOS `end(delete:true)` → `close(delete:true)` → `RecordFile.delete`（`RecorderController.swift:85-88, 184-199`；`CaptureOutput.swift:84-93`）。Android `endThenDispose(delete=true)` → `PcmCaptureEngine.stop(delete=true)` → `Utils.deleteFile`（`RecorderController.kt:121-122, 206-213`；`PcmCaptureEngine.kt:109-116`）。 | 取消手势与中断丢弃用它；平台删除是尽力而为。 |
| `dispose()` | 停掉仍在进行的 take（`delete:false`）、关流、平台销毁（`record.dart:198-213`）。 | 我们 wrapper 在 stop/cancel 的 `finally` 里 await dispose（`recorder.dart:101-127`）；可改为后台执行。 |
| `onStateChanged()` | 广播 `pause / record / stop`；失败 take 以 `stop` 结束，错误经 stream error 发出（`record.dart:132-138`；`record_state.dart:28-43`）。 | 现有中断检测依赖它；必须补 `onError`。 |
| `onStopped()` | 每个 take 一次，`RecordState.stop` 之后；说明原因（`stop / routeChange / interruption / error`）并带文件路径（`record.dart:140-151`；`record_platform_interface-2.2.0/.../record_stop.dart:2-29`）。 | 比 `onStateChanged` 更适合区分中断/路由/错误，且平台自行结束时不用再 `stop()` 拿文件。 |
| `onAmplitudeChanged(interval)` | Dart `Timer.periodic`，每 tick 异步 `isRecording()` + `getAmplitude()`；只在录音时更新（`record_amplitude.dart:43-46, 61-79`）。`Amplitude` 是 dBFS（`amplitude.dart`）。 | 约 10 Hz，异步串行，不能当 60 fps 波形源。 |

### 2.2 停止耗时与可靠性

- 没有官方时延承诺。可确定的是 `stop()`/`cancel()` 都等到平台把文件收尾后才返回；Android 还会 `readRemaining(flush = true)` 把 `AudioRecord` 缓冲和未完成 chunk 写掉（`PcmCaptureEngine.kt:109-116`）。
- WAV 16 kHz / 16-bit / mono 在 120 秒约 3.84 MB，远低于 ASR 的 8 MiB 上限（`speech.md` §3.3）；文件收尾本身不应是主要耗时，但**未在真机测量**。
- 设计上：松手瞬间就应把 UI 切到 `transcribing`（或收起浮层、显示转写胶囊），不要等 `stop()` 返回才反馈。现有代码在调用 `stop()` 前已经 `phase=transcribing`（`speech_controller.dart:320-324`），这点可沿用。

### 2.3 文件删除保证

- `cancel()` 返回前，平台已尝试删除；iOS 用 `try?`，Android 只捕获 `SecurityException`（`Utils.kt:6-17`；`CaptureOutput.swift:84-93`）。**不是文件系统层面的强保证**。
- 现有 wrapper 在 `finally` 再按已知路径删一次（`recorder.dart:118-125`），且下次 `start()` 会清理整个临时目录（`recorder.dart:66-75`）。因此残留会在下次录音前收敛。
- `stop()` 不删文件；删除发生在 `SpeechApi.transcribe` 读字节后的 `finally`（`speech_api.dart:60-69`）。上行失败/取消时 controller 也会删（`speech_controller.dart:329-345`）。

### 2.4 状态竞争（按住说话会新增的坑）

1. **并发 start**：快速连按两次，若两次都走完权限检查并 `recorder.start()`，会创建两个平台 recorder；第二次覆盖 `_recording`，第一次会话泄漏（麦克风保持打开）。必须加 `_starting` / `SpeechPhase.starting` 单飞保护。
2. **松手误取消转写**：`toggleVoiceInput` 在 `phase == transcribing` 时调 `_cancelTranscription()`（`speech_controller.dart:185-188`）。120 秒 cap 先触发后，用户松手会走到这里，转写被取消。新入口必须区分「松手完成」与「用户主动取消转写」。
3. **cap 与松手双触发**：现有 `_stopRecordingAndTranscribe` 用 `_recording == null` + `token` 做幂等（`speech_controller.dart:312-320`）。保留这个闸门；cap 的 `limitReached` Toast 只能由 cap 分支发一次（`speech_controller.dart:305-309`）。
4. **中断与松手**：中断已经把 phase 置回 idle（`_discardRecording`，`speech_controller.dart:393-405`）；随后松手必须 no-op，不能重新开录或转写。
5. **dispose / 切页与 start 并发**：现有 start 返回后有 `_disposed` 检查并 cancel（`speech_controller.dart:270-273`）；新增的 `_starting` 也要在 `handleLifecycle` / `dispose` 里标记取消，否则 start 完成时 App 已在后台。
6. **平台自行结束 take**：iOS `end()` 在平台侧结束时也会发 `onStopped`（`RecorderController.swift:194-197`）；之后 Dart 再调 `stop()` 会因 session 已空返回 null。必须用 `onStopped` 的原因/路径或直接丢弃，不能把 null 当「空录音」提示。
7. **stream error 未处理**：`interruptions` 由 `onStateChanged()` 经 `where().map()` 得到（`recorder.dart:92-99`），`listen` 没有 `onError`（`speech_controller.dart:292-295`）。`record_state.dart:38-42` 会把平台错误加到 stream；当前会成为未处理异步错误。改 `onStopped` 时一并补 `onError`。

## 3. 手势：按住 + 上滑取消

### 3.1 方案对比

| 方案 | 事实 | 判定 |
| --- | --- | --- |
| `Listener` | 原始 pointer 回调；`onPointerDown/Move/Up/Cancel`；不参与 gesture arena；指针 down 后，后续事件沿 down 时命中的 hit-test 路径派发，即使移出 widget 也继续收到（`flutter/lib/src/gestures/binding.dart:263-269, 432-438`）。`onPointerCancel` 表示输入不再导向该 receiver（API 文档）。 | **推荐**。按下即响应，能拿到移出按钮/屏幕后的 move/up，能无条件拿到 cancel。缺点：不抢 arena，不自动提供 semantics。 |
| `GestureDetector`（长按） | 默认 `kLongPressTimeout = 500 ms`（`gestures/constants.dart:28-29`）；`LongPressGestureRecognizer` 只有在 `duration` 到期后才 accept（`long_press.dart:281-290, 641-647`）。accept 前移动超过 `kTouchSlop = 18 dp` 会失去手势（`constants.dart:60-65`）。**accept 后收到 `PointerCancelEvent` 时，`handlePrimaryPointer` 只调 `_checkLongPressCancel()`，而该函数仅在 state==possible 时回调（`long_press.dart:670-672, 716-722`），因此不会触发 `onLongPressCancel/End/Up`**。 | 不推荐。500 ms 延迟与「按下即录」冲突；18 dp 抖动容差过小；系统取消后状态悬挂。 |
| `RawGestureDetector` + `LongPressGestureRecognizer(duration: Duration.zero)` | 可把 deadline 配成 0（`long_press.dart:281-290`），但仍有 accept 前 18 dp 容差、仍存在上面的 cancel 不回调问题；需要手写 `GestureRecognizerFactory` 配置。 | 仅在需要赢 gesture arena（例如手势区进入可滚动父级）时考虑；单独用不比 `Listener` 小。 |
| 自定义 recognizer | 可做到「down 即 accept + 自己处理 cancel」，但需要继承 `OneSequenceGestureRecognizer` 或类似基类，代码量明显增加。 | 当前不需要。 |

**推荐一句话**：用 `Listener` 包住麦克风按钮（保持挂载），以 pointer id 跟踪单指；`onPointerDown` 启动、`onPointerMove` 按全局 `dy` 判断 80 dp 上滑、`onPointerUp` 完成、`onPointerCancel` 取消。只有将来手势区被放进可滚动父级、必须阻止父级滚动时，才换 `RawGestureDetector` + 自定义 recognizer。

### 3.2 边界

- **滑出按钮 / 滑出屏幕**：Flutter 在 pointer down 时做一次 hit test，后续 move/up 复用同一路径（`binding.dart:432-438`），所以不需要按钮保持手指下方；用 `event.position`（全局坐标）而不是 `localPosition` 计算 80 dp，避免浮层/布局变化干扰。
- **`PointerCancelEvent`**：Android 的 `ACTION_CANCEL` 语义是「current gesture has been aborted… You should not perform any action that you normally would as a result of this gesture」（Android `MotionEvent` 文档）；Flutter 把它映射为 `PointerCancelEvent`（`gestures/converter.dart:201-202`）。一律按「取消并丢弃」处理。
- **多指**：`Listener` 会收到每个 pointer。只跟踪第一个 `PointerDownEvent.pointer`；其他 pointer 的 down/move/up 全部忽略。首指 cancel → 取消录音；首指 up → 完成。若第二指先抬起，不影响。
- **系统返回手势**：Android 10+ 的 back 是左/右边缘向内滑；home/quick switch 是底部上滑，且不能像 back 一样通过 `setSystemGestureExclusionRects` 排除（Android gesture navigation 文档）。麦克风按钮位于输入卡右侧、`SafeArea` 之上，不在左右边缘；上滑取消从按钮位置开始，正常情况下不会触发 back。若系统仍接管，App 收到 `PointerCancelEvent`，按取消处理。
- **权限弹窗 / 系统弹窗**：可能触发 pointer cancel 或让 App `inactive`；首次请求场景见 §1.2。
- **widget 卸载**：Flutter 会把事件继续发给 down 时的 hit-test 目标，「即使它们已被 dispose」（`binding.dart:265-269`）；但不要依赖这个行为。录音期间保持 `Listener` 所在 widget 挂载（浮层用 `Stack` 盖在上面，不替换按钮）；页面销毁统一由 `SpeechController` 取消。
- **上滑阈值与回拉**：以 down 时的全局 `dy` 为基准，`dy <= -80` 进入取消态。是否允许回拉恢复（带 10 dp 迟滞）是产品决议；建议默认「越过 80 dp 即锁定取消」，避免误发。横向位移不参与判定。
- **按住按钮外的区域**：按下点必须在按钮上；不要监听整个输入卡，否则点输入框也会录音。

### 3.3 无障碍

- `Listener` 不自动产生 semantics，必须外层加 `Semantics`：
  - `button: true`、`label` 为「语音输入」/录音中为「停止并发送」；
  - `onTap`：开始/结束切换（第一次双击开始，第二次双击结束并发送）。Flutter 文档明确：`SemanticsConfiguration.onLongPress` 是 `SemanticsAction.longPress` 的 handler，TalkBack/VoiceOver 用户通过「双击后不抬指」触发（Context7 引用的 Flutter API 文档）；但这只给一个回调，没有对应的「松手」语义事件，无法映射「按住/松手」。
  - 录音中提供 `customSemanticsActions`：「取消录音」。也可用 `liveRegion` 或 `SemanticsService.announce` 播报状态。
- Android 侧 `ACTION_LONG_CLICK` 只是「long clicks on the node」（Android `AccessibilityNodeInfo.AccessibilityAction` 文档），同样没有 hold 的 up 事件；不要把它当作按住手势的等价物。
- 结论：**无障碍走 tap 切换，不走长按语义**；视觉按钮仍可按住。

## 4. 中断：来电、路由、后台、切会话

### 4.1 配置与现有行为

- `RecordConfig(audioInterruption: AudioInterruptionMode.pause, audioRouteChange: AudioRouteChangeMode.pause)`（`lib/features/chat/speech/recorder.dart:53-54`）。
- iOS：`AVAudioSession.interruptionNotification` → `.interrupted` → `TakePolicy` 在 `audioInterruption != none` 时返回 `.pause(.interruption)`（`IosAudioEnvironment.swift:114-143`；`TakePolicy.swift:41-46`）。`.pause` 模式下中断结束不自动恢复（`TakePolicy.swift:47-54`）。
- iOS 路由：输入设备丢失 → `inputLost` → `audioRouteChange.pause` 时 pause（`TakePolicy.swift:68-77`）。Apple 对路由变化的旧文档要求录音 App 在收到路由变化时停止/暂停录音；`record` 直接替我们 pause。
- Android：录音期间请求 `AUDIOFOCUS_GAIN`（`AudioSessionManager.kt:56-58, 112-160`）；焦点丢失 → `AudioInterruptionPolicy` 返回 Pause（`AudioInterruptionPolicy.kt:10-18`）；输入设备丢失 → `onRouteLost` → `audioRouteChange.pause` 时 `pause()`（`RecorderController.kt:148-170`）。
- 现有 `session.interruptions` 把非用户触发的 `pause`/`stop` 视为中断，controller 立刻 `_discardRecording` 并删除文件（`recorder.dart:90-99`；`speech_controller.dart:292-295, 393-405`）。

### 4.2 来电

- iOS：`IosAudioEnvironment` 在 iOS 14.5+ 设置 `prefersNoInterruptionsFromSystemAlerts(true)`，源码注释为「A ringing call only shows a banner. The take is interrupted only when the call is answered」（`IosAudioEnvironment.swift:83-91`）。Apple 文档该属性只对「横幅式来电」生效；若用户设置为全屏来电，来电响铃时系统仍会中断（Apple `prefersNoInterruptionsFromSystemAlerts` 文档，iOS 14.5+）。两种路径最终都是 pause → 丢弃，区别只是丢得早晚。
- Android：没有电话状态监听，依赖 audio focus。来电通常产生 transient focus loss → pause；具体时机随系统/厂商，**未验证**。若某机型不给 focus 事件，录音可能继续到用户松手；这是已知风险，需真机来电测试。
- `record_darwin` 2.0.0 changelog 明确修复了「iOS 来电在接通前不再中断录音」「通话后在同一文件恢复（pauseResume）」（`record_darwin-2.0.0/CHANGELOG.md`）。我们用的是 `pause`，不会恢复。

### 4.3 路由变化

- 蓝牙耳机接入：`record_darwin` 2.0.0 修复为「录音中接入设备不再停止录音，也不改变输入」（`record_darwin-2.0.0/CHANGELOG.md`），因此不应触发中断。
- 当前输入设备消失（拔耳机/断开蓝牙）：`pause`，发 `RecordState.pause`；现有代码丢弃。Apple 官方旧文档：录音中路由变化应停止录音；Android 由插件 pause。符合预期。
- 蓝牙 SCO 启动：仅影响启动耗时（§1.2）。

### 4.4 后台

- iOS：仓库 `Info.plist` 没有 `UIBackgroundModes: audio`，只声明了 `NSMicrophoneUsageDescription`（`ios/Runner/Info.plist:7-8`）。Apple 文档：要在后台继续录音必须在 `UIBackgroundModes` 加 `audio`；`record` 官方 `bg_recording.md` 也要求 iOS 加 `audio`、Android 用外部前台服务包。当前不支持，符合 `speech.md` §5.2「只支持前台」。
- Android：manifest 只有 `INTERNET` 与 `RECORD_AUDIO`，没有 microphone 类型的 foreground service（`android/app/src/main/AndroidManifest.xml:3-4`）。Android 14+ 的 `RECORD_AUDIO` 是 while-in-use 权限，后台不能创建 microphone FGS，后台访问麦克风也受限（Android FGS service-types / restrictions-bg-start 文档）。当前设计在 `inactive/paused/hidden` 时主动取消（`lib/app/app.dart:48-51`），不依赖后台录音。
- 进入后台时 `cancel()` 的平台调用可能来不及完成就被挂起；文件残留由下次启动清理（§2.3）。**未验证**具体系统时序。

### 4.5 切会话 / 离开页面

- 聊天页 dispose 时 `stopAll()`（`lib/features/chat/chat_page.dart:90, 113`），等于 `handleLifecycle()`：录音取消、转写中止、朗读停止（`speech_controller.dart:225-240`）。按住说话不改变这条路径；新增的 `_starting` 也要在其中取消。
- 切换会话时页面销毁，`Listener` 不在树中；不要依赖收到 up。controller 的取消是唯一可靠收尾。

### 4.6 建议

- 用 `onStopped()` 替代/补充 `onStateChanged()` 做中断判定：
  - `reason == interruption` → 丢弃并提示「已中断」；
  - `reason == routeChange` → 丢弃；
  - `reason == error` → 丢弃 + 失败提示；
  - `reason == stop` 且 `_closing == false` → 平台/其他路径结束，丢弃并删除 `path`。
- 订阅必须加 `onError`，否则 `record_state.dart:38-42` 的错误会成为未处理异常。
- 不要用 `pauseResume`；现有 `pause` 与「中断即丢弃」语义一致。

## 5. 电平与浮层波形

### 5.1 事实

- 订阅：`onAmplitudeChanged(const Duration(milliseconds: 100))`（`recorder.dart:86-88`），映射 `((current + 50) / 50).clamp(0, 1)`。
- 实现：Dart `Timer.periodic(interval)`，每个 tick 先 `await isRecording()`，再 `await getAmplitude()`（`record_amplitude.dart:43-46, 61-79`）。两次平台调用都可能超过 100 ms；`AudioRecorder` 的 semaphore 会把重叠 tick 串行化（`record.dart:249-256`）。因此**没有稳定的 10 Hz 保证**，实际是「约 10 Hz 或更低」。
- 值域：两端静音底都是 `-160.0` dBFS（`record_darwin/.../Amplitude.swift:4`；`record_android/.../CaptureEngine.kt:8`），峰值 `0`。现有 `[-50, 0] → 0..1` 的映射合理；静音会落到 0。
- 文件录音模式没有 PCM 数据给波形；`startStream` 是另一条 API，不能同时写文件。真实波形需要改录音方式，本图已明确不做。
- 电平在 `SpeechController` 里已经进入 `state.level`，每次更新只通知 select 了 level 的 widget；现有状态行选择 `(phase, seconds, level)`（`lib/features/chat/composer.dart:352-360`），所以录音中状态行每 100 ms 重建一次，范围很小。

### 5.2 浮层建议

- **复用 `SpeechController.level`**，不新增录音通道、不在浮层里再调 `record`。
- 波形条数量与形态由视觉原型定；数据上只有**一个 0..1 标量**。用本地 `AnimationController` / `TweenAnimationBuilder`（80–150 ms 缓动）在该标量之间插值，再给每根条不同权重/相位，避免 10 Hz 的台阶感。
- 不要降低 interval 到 50 ms 以下来「提高帧率」：每个 tick 是平台往返，重叠会被 semaphore 排队，收益低且增加主线程负载。
- 浮层单独 `ConsumerWidget` 只 select `level`，不要让整个 Composer 随电平重建；状态胶囊与浮层可以共享同一个 level。
- 启动后的前 100 ms 没有样本；波形从基线开始，不要闪空。

## 6. 120 秒上限与自动转写、自动发送

### 6.1 现有事实

- `speechMaxRecordingProvider` 默认 120 秒（`speech_controller.dart:117-120`）。
- cap timer 在 `recorder.start()` 成功后创建（`speech_controller.dart:305-309`），所以计时从「实际开录」算，符合 `speech.md` §3.2「录音中按墙钟计时」。
- 到期动作：发 `limitReached` 提示 → `_stopRecordingAndTranscribe()`（`speech_controller.dart:305-309`）。停止后进入 `transcribing`，成功后调用 `onTranscript` 插入文本（`speech_controller.dart:354-367`），当前**不会自动发送**。
- 自动发送必须另走聊天页的发送路径：`_send`（`chat_page.dart:128-158`）会再检查 Key、附件上传闸门、会话创建，并调用 `ChatController.send`。按住说话只在「无文本无附件」时出现（map 按钮矩阵），所以发送闸门通常满足。

### 6.2 建议时序

```
recording (start 完成时启动 capTimer)
  → 120s cap 触发（同一 isolate 事件循环）
      → 标记 capTriggered，取走 session（幂等）
      → phase=transcribing，取消 timer
      → stop() → 读 Key → transcribe
      → 非空：callback(text, autoSend: true) → send
      → 空/失败：Toast，不发送
  → 用户此刻松手：finishFromRelease 看到 phase != recording，no-op
```

- **cap 与松手的竞态**：两者都在主 isolate 顺序执行；用 `_recording == null` + `token` 保证只有一个 `stop`。cap 先跑则松手 no-op；松手先跑则 cap timer 已被 `_cancelRecordingResources()` 取消（`speech_controller.dart:319, 407-417`）。保留现有幂等闸门。
- **cap 后不能取消转写**：松手不能走 `toggleVoiceInput` 的 transcribing 分支（会取消）。转写中的取消只来自发送槽的加载圈（map 决议）或生命周期。
- **自动发送失败**：转写已经成功但 `send` 返回 false（Key、上传闸门、会话创建失败）时，建议回退把文本插入输入框并 Toast，避免用户白说 120 秒；需在票 05 定。
- **空结果 / 转写失败**：不发送，Toast；录音文件已由 `speech_api` 删除。
- **自动发送不是「120 秒时发送」**：是停止后转写成功才发送；网络/转写耗时另计。
- **生命周期**：120 秒到点时若 App 进入后台，`handleLifecycle` 在 transcribing 分支会 `_cancelTranscription()`（`speech_controller.dart:230-231`），不会发送；符合「后台取消」。
- **提示文案**：`limitReached` 与「已发送」可能连续出现；避免两个 Toast 打架，票 05 决定是否只保留一个。

## 7. 推荐状态迁移（供票 05 锁定）

| 当前 | 事件 | 结果 | 备注 |
| --- | --- | --- | --- |
| idle | pointerDown（无文本/附件，非 busy/reading） | arming（立即显示按下态/浮层骨架） | 单飞 `_starting`，忽略第二次 down |
| arming | Key 缺失 | idle + noApiKey | 若采用并发 Key 检查，start 后 cancel |
| arming | 权限未请求 | 请求权限；不录音 | 授权后若 pointer 已不在 down，保持 idle 并提示再按住 |
| arming | 权限已授予且 recorder.start 成功 | recording | 计时从此刻开始；订阅 levels / interruptions |
| arming | recorder.start 失败 | idle + noDevice/failed | 收起浮层 |
| arming | pointerUp / pointerCancel | 取消启动；start 返回后 cancel session | 防止无人按住仍录音 |
| recording | pointerUp（未过取消阈值） | transcribing（autoSend=false） | 立刻收起浮层/显示转写态；不等 stop |
| recording | pointerMove 全局 dy ≤ -80 | cancelArmed（显示「松开取消」） | 是否允许回拉恢复待票 05 |
| cancelArmed | pointerUp | 取消：stop/cancel + 删除 + idle | 不上传 |
| recording | pointerCancel | 取消 + 删除 + idle | 系统手势/来电/弹窗 |
| recording | interruption / routeChange / lifecycle | 取消 + 删除 + idle | 来电、路由、后台、切会话 |
| recording | 120s cap | transcribing（autoSend=true）+ limitReached | 后续 pointerUp no-op |
| transcribing | 非空结果 | autoSend ? send : insert；idle | send 失败回退插入 |
| transcribing | 空/失败 | idle + empty/failed | 不发送 |
| transcribing | 发送槽加载圈点击 / lifecycle | abort + idle | 不走松手 |

## 8. 风险与未验证

1. **实际启动/停止毫秒数未验证**：本机没有 iOS/Android 真机埋点；只能给出源码结构与 Android SCO 2.5 秒硬上限。实现前建议用 `Stopwatch` 记录 key/permission/create/list/dir/start 六段。
2. **首次权限弹窗与 pointer 取消**：iOS 弹窗会让 App inactive，Flutter 很可能收到 pointer cancel；Android 视厂商。必须真机验证首次授权的完整路径。
3. **Android 来电**：依赖 audio focus，部分机型/系统可能不给 transient loss 或时机偏晚；需真实来电测试。隐私风险高于功能风险。
4. **iOS 来电样式**：`prefersNoInterruptionsFromSystemAlerts` 仅对横幅式来电生效；全屏来电会在响铃时中断。产品文案不要承诺「接通才中断」。
5. **`Listener` 不抢 gesture arena**：当前 Composer 不在可滚动父级中（`chat_page.dart` 布局），所以安全；若后续把输入区放进 scroll view，上滑会同时滚动页面。届时需要 `RawGestureDetector` + 自定义 recognizer 或 `AbsorbPointer` 方案。
6. **自动发送失败会丢转写**：`_send` 可能因 Key/上传闸门/会话创建失败返回 false；必须定回退策略。
7. **取消删除不是强保证**：平台删除失败被吞；依赖 wrapper 二次删除 + 下次启动清理。不要在 UI 上承诺「文件已彻底销毁」。
8. **`onStateChanged` 错误未监听**：现有 `interruptions.listen` 无 `onError`，平台错误会成为未处理异常；改造时补上。
9. **DeepSeek 参考行为无法作为一手来源**：未找到公开的 DeepSeek 按住说话交互规范；本图的视觉参考来自 `evidence/04-voice-overlay.jpg`（微信风格截图）。DeepSeek 行为标注「未验证」，不作为规格依据。
10. **Android 14+ 后台麦克风**：当前无 FGS，后台不能录音；设计已在前台取消，符合预期。若未来要后台录音，需要 microphone FGS + 前台启动限制，成本高。

## 9. 来源

### 9.1 本地源码（读取日期 2026-11-20）

仓库：

- `lib/features/chat/speech/speech_controller.dart:117-120, 175-190, 225-240, 244-310, 312-380, 393-417`
- `lib/features/chat/speech/recorder.dart:34-63, 66-75, 86-99, 101-127`
- `lib/features/chat/speech/speech_api.dart:60-69`
- `lib/features/chat/chat_page.dart:120-122, 128-158, 411-427`
- `lib/shared/speech/permissions.dart:29-36`
- `lib/shared/security/api_key_store.dart:12`
- `lib/app/app.dart:48-51`
- `ios/Runner/Info.plist:7-8`
- `android/app/src/main/AndroidManifest.xml:3-4`

pub cache：

- `~/.pub-cache/hosted/pub.dev/record-7.2.0/lib/src/record.dart:32-41, 51-97, 132-160, 198-213, 249-257`
- `~/.pub-cache/hosted/pub.dev/record-7.2.0/lib/src/part/record_amplitude.dart:10, 13-32, 43-46, 61-79`
- `~/.pub-cache/hosted/pub.dev/record-7.2.0/lib/src/part/record_state.dart:23-63`
- `~/.pub-cache/hosted/pub.dev/record_platform_interface-2.2.0/lib/src/types/record_stop.dart:2-29`
- `~/.pub-cache/hosted/pub.dev/record_platform_interface-2.2.0/lib/src/types/record_config.dart:65-104`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/RecorderController.swift:63-88, 138-173, 184-200, 222-270`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/engine/AudioEngineCapture.swift:46-65, 112-125`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/engine/CaptureOutput.swift:84-93`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/policy/TakePolicy.swift:41-79`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/ios/IosAudioEnvironment.swift:75-106, 114-143`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/util/RecordFile.swift:3-18`
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/darwin/record_darwin/Sources/record_darwin/core/model/Amplitude.swift:4`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/RecorderWrapper.kt:101-120, 163-166`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/recorder/RecorderController.kt:48-75, 119-122, 148-170, 206-245`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/recorder/engine/PcmCaptureEngine.kt:43-68, 109-117`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/bluetooth/BluetoothManager.kt:12-13, 20-59`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/audio_manager/AudioInterruptionPolicy.kt:10-18`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/audio_manager/AudioSessionManager.kt:56-58, 112-160`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/android/src/main/kotlin/com/llfbandit/record/record/util/Utils.kt:6-17`
- `~/.pub-cache/hosted/pub.dev/record_android-2.3.0/CHANGELOG.md`（2.1.0 cancel 删除修复）
- `~/.pub-cache/hosted/pub.dev/record_darwin-2.0.0/CHANGELOG.md`（来电、路由、onStopped 修复）

Flutter SDK：

- `/Users/transon/flutter/packages/flutter/lib/src/gestures/constants.dart:28-29, 60-65`
- `/Users/transon/flutter/packages/flutter/lib/src/gestures/long_press.dart:281-290, 641-647, 650-672, 716-722, 861-872`
- `/Users/transon/flutter/packages/flutter/lib/src/gestures/binding.dart:263-269, 428-438`
- `/Users/transon/flutter/packages/flutter/lib/src/gestures/converter.dart:201-202`

### 9.2 官方文档 URL（访问日期 2026-11-20）

`record`：

- https://pub.dev/documentation/record/latest/record/AudioRecorder-class.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/start.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/stop.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/cancel.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/onStopped.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/onStateChanged.html
- https://pub.dev/documentation/record/latest/record/AudioRecorder/onAmplitudeChanged.html
- https://pub.dev/packages/record
- https://github.com/llfbandit/record/blob/main/doc/bg_recording.md

Flutter：

- https://api.flutter.dev/flutter/widgets/Listener-class.html
- https://api.flutter.dev/flutter/widgets/GestureDetector-class.html
- https://api.flutter.dev/flutter/widgets/GestureDetector/onLongPressCancel.html
- https://api.flutter.dev/flutter/gestures/LongPressGestureRecognizer-class.html
- https://api.flutter.dev/flutter/widgets/RawGestureDetector-class.html
- https://api.flutter.dev/flutter/semantics/SemanticsConfiguration/onLongPress.html
- https://api.flutter.dev/flutter/semantics/SemanticsConfiguration/onTap.html
- https://api.flutter.dev/flutter/gestures/PointerCancelEvent-class.html

Apple：

- https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
- https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- https://developer.apple.com/documentation/avfaudio/avaudiosession/prefersnointerruptionsfromsystemalerts
- https://developer.apple.com/documentation/avfaudio/avaudiosession/setprefersnointerruptionsfromsystemalerts(_:)
- https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord
- https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html
- https://support.apple.com/guide/iphone/iph3e2e2281/ios（VoiceOver 手势，含 double-tap and hold）

Android：

- https://developer.android.com/media/optimize/audio-focus
- https://developer.android.com/develop/background-work/services/fgs/service-types（microphone 类型、while-in-use）
- https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- https://developer.android.com/reference/android/view/MotionEvent#ACTION_CANCEL
- https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav
- https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeInfo.AccessibilityAction#ACTION_LONG_CLICK
