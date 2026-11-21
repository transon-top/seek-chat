# 语音输入与朗读行为

票：`21-speech-behavior`。方案选型与协议事实见票 15 与其研究分支
[`docs/research/speech.md`](https://github.com/transon-top/open-chat/blob/2ef5b5c373167898bb943b11522b92c100e92612/docs/research/speech.md)；
数据模型见 [`data-model.md`](data-model.md)，错误文案总则见 [`architecture.md`](architecture.md) §5。

- 关联：`api.md` 的客户端只覆盖 Messages / Files；ASR 与 TTS 是独立的
  `/v1/tools/*` 接口，请求契约以本文为准。
- 交接：按钮与状态行的组件映射 → 票 10；设置页版式 → 票 20；v1 验收映射 → 票 19。

## 1. 决策摘要

| 主题 | 决策 |
| --- | --- |
| 语音输入 | **按住说话**：按下即录，松手转写并尝试自动发送；上滑 80dp 取消；不做实时流式识别 |
| 手势 | `Listener` 处理 pointer down / move / up / cancel，只跟踪首个 pointer；不用长按手势 |
| 录音规格 | `record` 7.2.0，16-bit PCM WAV、16 kHz、单声道，临时文件，用后删除 |
| 时长上限 | 120 秒自动结束并转写；客户端保证文件 ≤ 8 MiB（120 秒约 3.84 MB） |
| 转写端点 | `POST /v1/tools/asr`，`Authorization: Bearer`，multipart 字段 `file` |
| 转写结果 | 去首尾空白后先插入输入框（替换选区、光标落其后），再按发送闸门尝试自动发送；结果永不丢失 |
| 转写失败 | 除权限 / 无设备 / 空结果 / 超时上限外，**全部折叠为一条**「语音识别失败」；不自动重试 |
| 浮层 | 录音、识别、取消共用同一蓝色动态浮层（自绘 `CustomPainter`，不引依赖） |
| 朗读 | 仅 assistant 消息操作条入口；同一时间只朗读一条，首帧流式播放 |
| 朗读端点 | `POST /v1/tools/tts`，`format: pcm`、`filter_markdown: true`、`voice_id` 取设置 |
| 播放 | `flutter_soloud` 5.3.0，裸 PCM（s16le、24 kHz、单声道），首帧前缓冲 100 ms |
| 朗读状态 | `idle / loading / playing`；无暂停、无进度、无续传；再次点击同一条即停止 |
| 音色 | `stella`（默认，女声）/ `tide`（男声），存 `tts.voice`，开始朗读时读取 |
| 互斥 | 录音与朗读不能同时进行；新意图优先，朗读中开始录音会先停朗读 |
| 前后台 | v1 仅前台；进入非 `resumed` 状态即取消录音并停止朗读 |
| 波形 | 浮层内 32 根波形条，复用 `SpeechState.level` 做约 30fps 插值缓动；真实频谱不进 v1 |
| 持久化 | 语音与音频不写数据库、不进历史归档、不做 TTS 缓存 |
| 依赖 | 新增 `record`、`flutter_soloud`、`permission_handler`；不引入 `audio_session`、动效库 |

## 2. 入口与可见状态

### 2.1 语音输入

- 入口在输入区操作行，`+` 与发送 / 停止之间；按住说话，不做点击开始 / 再点结束。
- 按钮可见态只有两种：
  - `idle`：麦克风图标；有文本时隐藏，生成中隐藏，朗读中禁用。
  - 录音 / 转写中：浮层覆盖输入卡，按钮不可见。
- 浮层三态共用一套视觉：录音「松手发送，上滑取消」、取消「松开取消」、
  识别「识别中」；识别中不提供取消入口，等 ASR 返回或失败。
- 录音期间：浮层覆盖输入卡与草稿行，输入框不可编辑；发送、附件、开关均不可见。
  识别期间浮层仍在，输入框同样被覆盖。
- 发送条件增加 `voice == idle`，与 chat-demo 的 `canSend` 一致。
- 无 API Key 时按下：不录音，显示现有 `errorNoApiKey` 文案。

### 2.2 朗读

- 入口只在 assistant 消息操作条，与「重新生成」「继续生成」并列；输入区不再放
  第二个朗读按钮。原型输入区的喇叭按钮不进实现。
- 仅当回复满足以下条件时显示且可用（`canReadAloud`）：
  不在生成中（`!isInFlight`，即 `done` / `stopped` / `error` 均可）、非拒答、
  `ReplyView.answer` 非空。错误回复只要已有正文也可朗读。
- 朗读文本由聊天页从 `ReplyView.answer.text` 取出后，以 `String` 传入
  `SpeechController`；`shared/` 不 import `features/`。文本只含正文块纯文本，
  不含思考、搜索步骤、引用角标、`[citation:N]` 与模板 / 提示文案
  （chat-demo 会把 `presentation=response` 的提示并入朗读文本，本规格排除）。
  Markdown 清理由服务端 `filter_markdown` 完成。
- 按钮可见态：
  - `idle`：播放图标，tooltip「朗读」。
  - `loading`：4 根竖条扫光动画，tooltip「停止朗读」。
  - `playing`：4 根竖条起伏动画，tooltip「停止朗读」。
- 语音输入处于 `recording` / `transcribing` 时，所有朗读按钮置灰且不可点击。
- 动画遵循 `MediaQuery.disableAnimations`；开启减少动画时用静态竖条。

## 3. 语音输入状态机

运行时状态为 `idle`、`starting`、`recording`、`cancelling`、`transcribing`，
外加瞬态 `error`。`error` 只在失败提示展示期间存在，提示结束即回 `idle`。

```
idle ──pointer down──▶ starting ──start() 成功且 pointer 有效──▶ recording
  ▲                        │                                       │
  │                        ├─ Key / 权限 / 设备 / 启动失败 ──▶ idle  │
  │                        ├─ 已松手 / pointer cancel ──▶ idle      │
  │                        └─ 首次授权 pointer cancel ──▶ idle      │
  │                                                                ▼
  │                                        cancelling ◀──上滑 ≥80dp── recording
  │                                            │ 回拉 <80dp → recording
  │                                            └─ pointer up → 丢弃 → idle
  │                                                                ▼
  └────────── 成功插入 / 空结果 / 失败 / 后台或切会话取消 ─── transcribing
```

### 3.1 转移表

| 当前 | 事件 | 动作 | 下一状态 | 可见 |
| --- | --- | --- | --- | --- |
| `idle` | 麦克风 pointer down | 失焦、收键盘、收面板、显示浮层骨架、单飞启动 | `starting` | 浮层骨架 |
| `starting` | `start()` 成功且 pointer 仍有效 | 建录音 session、启动电平 / 计时 / cap | `recording` | 浮层波形 |
| `starting` | 已松手或已取消 | `session.cancel()`，不转写 | `idle` | 浮层消失 |
| `starting` | Key / 权限 / 设备 / 启动失败 | 收起浮层 + 对应 Toast | `idle` | Toast |
| `starting` | 首次授权导致 pointer cancel | 不开录；授权成功提示再按住 | `idle` | Toast「已授权…」 |
| `starting` | 其他 pointer cancel | 置取消标记，`start()` 返回后 cancel | `idle` | 浮层消失 |
| `recording` | 上滑 ≥ 80dp | 进入取消态（medium 触感） | `cancelling` | 文案「松开取消」 |
| `cancelling` | 回拉 < 80dp | 恢复发送态（light 触感） | `recording` | 「松手发送，上滑取消」 |
| `recording` | pointer up | stop → 转写 | `transcribing` | 浮层保留，文案「识别中」 |
| `cancelling` | pointer up | 丢弃录音，静默 | `idle` | 浮层消失 |
| `recording` / `cancelling` | pointer cancel、来电、路由中断 | 丢弃；中断加 interrupted Toast | `idle` | 依分支 |
| `recording` / `cancelling` | 系统返回（页面未销毁） | 取消录音，停留页面 | `idle` | 浮层消失 |
| `recording` | 120 秒 cap | 自动 stop → 转写 → 尝试发送 | `transcribing` | `limitReached` Toast |
| `transcribing` | ASR 成功非空 | 插入输入框 → 可发送则 `_send()` | `idle` | 失败时 Toast |
| `transcribing` | ASR 空 / 失败 | 不插入，empty / failed Toast | `idle` | Toast |
| `transcribing` | 后台、切会话、页面销毁 | 取消转写、丢弃 | `idle` | — |
| `transcribing` | cap 后松手 | no-op | `transcribing` | — |
| 任意 | 页面销毁 | `stopAll` 静默清理 | — | — |

### 3.2 按住、启动与手势

- `onPointerDown` 同步执行：输入框失焦、收起键盘、收起附件面板、显示浮层骨架；
  随后单飞执行读 Key → `isGranted()` → `request()` → `recorder.start()`。
  `_starting` 标记防止连按双开。
- 用 `Listener` 直接处理 pointer down / move / up / cancel，只用 `List` 跟踪
  第一个 pointer id；不用 `GestureDetector` 长按（500 ms 延迟，且长按被接受后
  系统 cancel 不回调结束事件，状态会悬挂）。
- 取消阈值以按下瞬间的全局坐标为基准：`pressStartGlobalY - currentY >= 80dp`，
  实时判定，可回拉；横向位移不取消；手指滑出按钮范围不影响录音，只有抬起或
  `PointerCancel` 结束。
- 首次授权：系统弹窗会让 Flutter 收到 `PointerCancelEvent`，之后不会有
  `PointerUp`。授权成功后不自动开录，收起浮层并提示「已授权麦克风，请再按住说话」。
- 松手早于 `start()` 返回：置取消标记，`start()` 返回后立即 `cancel()`，
  不转写、不提示。`start()` 成功但录音极短：正常 stop → 转写，空结果走
  `voiceInputEmpty`；不设最短时长门槛。
- 触感：进入取消态 `HapticFeedback.mediumImpact`，回拉恢复 `lightImpact`；
  松手取消静默，无 Toast。
- 启动失败、无输入设备或权限在启动时被撤销：释放已占资源，回 `idle`。
- 录音中按墙钟计时；到达 120 秒只触发一次停止。不以样本数或电平回调计时。
- 录音被系统中断（来电、其他应用占用音频、蓝牙路由断开）：
  `record.onStateChanged()` / `onStopped()` 出现非用户触发的原因即视为中断，
  取消本次录音并丢弃，不尝试恢复。配置选择路由变化时停止，不做自动切换。
- 录音中系统返回：第一次只取消录音并留在页面，不弹侧栏、不退出。
- 启动时清理语音临时目录中的残留文件。

### 3.3 转写请求

- `POST {origin}/v1/tools/asr`，头 `Authorization: Bearer <apiKey>`；
  字段名 `file`，文件名 `recording.wav`。不得改用 `x-api-key` 或 Messages 端点。
- 上传前检查：文件非空且 ≤ 8 MiB；不满足则不发请求，按空结果或
  `voiceInputFailed` 处理。120 秒上限已保证正常文件远小于 8 MiB。
- 响应必须是 JSON 且 `text` 为字符串；只读取 `text`，忽略 `request_id` /
  `duration_ms`。非 JSON、缺字段或类型错误按协议失败处理。
- 请求可取消：复用 `http.AbortableRequest` 的 `abortTrigger`；
  multipart 请求体先 finalize 为字节再发送。取消后丢弃响应，不插入任何文本。
- 识别中浮层不提供取消入口；取消只来自后台、切会话、离开页面与页面销毁。
- 不设客户端超时；ASR 官方要求上传在 10 分钟内完成，v1 不额外计时。

### 3.4 插入与自动发送

- 转写成功先把文本插入输入框：取 `TextEditingController.value` 的 `selection`，
  无效选区（`-1`）用文本末尾；`before + transcript.trim() + after`，光标折叠到
  插入内容之后；不改变附件与开关状态。
- 随后判断发送条件（全部满足才复用现有 `_send()`）：无生成中、草稿附件全部
  `done`、有 API Key、会话可用，且转写期间用户没有手动输入新文本。
- 发送成功：沿用 `_send()` 清空输入。任一条件不满足：只插入、不发送，并 Toast
  说明原因：无 Key → `errorNoApiKey`；生成中 → `voiceInsertedGenerating`；
  附件未完成 → `voiceInsertedUploading`；其他（用户已输入、会话不可用）→
  `voiceInsertedNotSent`。转写结果永不丢失。
- 建会话或发送抛错：文本留在输入框，Toast `voiceSendFailedInserted`；空会话按
  现有 `_discardEmptySession` 清理。
- 转写失败 / 空结果：不插入，走 `voiceInputEmpty` / `voiceInputFailed`。
- 120 秒 cap 已触发后松手：no-op。

## 4. 朗读状态机

```
idle ──点击可朗读回复 / 有 Key──▶ loading ──首块 PCM──▶ playing
  ▲                                  │                     │
  │                                  ├── 点击同一条 / 发送 / 停止生成
  │                                  ├── 切换消息 / 切会话 / 离开页面
  │                                  ├── 进后台 / 音频中断
  │                                  └── 出错 / 空流
  └──────────────────────────────────┴─────────────────────┘
```

状态只有 `idle`、`loading`、`playing`；没有暂停 / 继续、没有进度条、
没有后台 / 锁屏控制。

### 4.1 转移表

| 当前 | 事件 | 结果 | 提示 |
| --- | --- | --- | --- |
| `idle` | 点击某条回复，无 Key | 保持 `idle`，不发请求 | `errorNoApiKey` |
| `idle` | 点击某条回复 | 请求 TTS → `loading` | 无 |
| `loading` / `playing` | 点击同一条 | 中止 HTTP、停播、释放资源 → `idle` | 无 |
| `loading` / `playing` | 点击另一条 | 先停止当前，再为新消息进入 `loading` | 无 |
| `loading` | 收到首个非空 PCM 块 | 进入 `playing` | 无 |
| `playing` | 播放结束 | 释放资源 → `idle` | 无 |
| `loading` / `playing` | 发送、停止生成、继续生成、重新生成 | 停止 → `idle` | 无 |
| `loading` / `playing` | 切换会话、离开聊天页、切换分支 | 停止 → `idle` | 无 |
| `loading` / `playing` | 进入后台 / 音频焦点丢失 | 停止 → `idle`，不自动续播 | 无 |
| `loading` / `playing` | 失败（含空流、流中途异常） | 停止、释放 → `idle` | 见 §6.2 |

切换分支时本规格要求停止朗读；chat-demo 的版本切换器不停止，这是有意的安全扩展，
避免继续朗读已隐藏分支的内容。会话切换与离开页面在 chat-demo 中同样会停止
（`App.tsx` 监听 `activeId`）。

### 4.2 请求与播放

- 请求 JSON：

  ```json
  {
    "text": "<正文纯文本>",
    "voice_id": "stella | tide",
    "format": "pcm",
    "filter_markdown": true
  }
  ```

  头 `Authorization: Bearer <apiKey>`、`Content-Type: application/json`。
- `voice_id` 在开始朗读时从 `tts.voice` 读取一次快照；播放中修改设置只影响下一次。
- 不截断文本：超过 10,000 billed characters 或 64 KiB 时由服务端 400 拒绝，
  映射为「这条回答暂时无法朗读」。不缓存、不写临时音频。
- PCM 参数按文档：raw 16-bit signed、单声道、24 kHz；按小端 `s16le` 喂给播放器。
  奇数字节留到下一块再拼接。字节序在上线前用已知音频 spike 验证（§10）。
- 使用 `flutter_soloud`：懒初始化；`bufferingTimeNeeds` 100 ms；
  首批数据到达后 `addAudioDataStream` 并 `play`；后续分块追加；
  HTTP 正常结束后 `setDataIsEnded`。停止时取消请求、`stop(handle)`、
  `disposeSource(source)`，释放后同一时间不保留第二条音频。
- 正常结束以播放器排空且 `setDataIsEnded` 后回调为准；流在收到任何音频前结束
  视为失败。已有部分音频后传输中断按失败处理：停止播放并提示，不静默播半截。
- 不设首字节超时；`loading` 中用户可点击停止。

### 4.3 互斥与音频会话

- 全局只有一个音频通道，由 `SpeechController` 统一持有：
  `idle | recording | transcribing | loading | playing` 是同一状态机的互斥分支。
- 语音输入优先：录音开始前先停止朗读并等待播放器释放；权限被拒绝时保持原朗读。
- 朗读进行中且语音为 `idle` 时，朗读按钮可用；语音非 `idle` 时朗读入口置灰。
- 转写结束到朗读开始之间，必须确认录音器已停止并释放音频会话后再初始化播放器。
  录音停止后直接播放的会话切换需真机验证；若冲突，按 §10 的备选处理。
- 不引入 `audio_session`；中断处理由 `record`、`flutter_soloud` 的原生事件
  加应用生命周期兜底。iOS 中断事件可靠；Android 部分后端不上报，
  以后台生命周期停止作为兜底。

## 5. 权限、前后台与隐私

### 5.1 权限

- 唯一权限：麦克风。朗读不需要权限。
- iOS：`Info.plist` 添加 `NSMicrophoneUsageDescription`，并提供
  `zh` / `en` 的 `InfoPlist.strings`；不添加 `NSSpeechRecognitionUsageDescription`。
- Android：主 `AndroidManifest.xml` 显式声明
  `android.permission.RECORD_AUDIO` 与 `android.permission.INTERNET`
  （Flutter 模板默认只在 debug / profile 带 INTERNET，release 必须显式声明）。
- 权限请求与状态统一走 `permission_handler` 13.0.2。其 `PermissionStatus`
  没有 `notDetermined`，因此另存 `speech.micRequested` 布尔值（首次请求后置
  `true`）来区分「未请求」与「已拒绝」：
  - 首次按住说话时调 `Permission.microphone.request()`；首次系统弹窗后本次手势
    一律不开录：`granted` 时提示 `voiceMicGrantedRetry` 让用户再按住，拒绝时按
    上一行处理。后续按住才走「检查 → 开录」。
  - `granted` = 已允许；`micRequested == false` = 未请求；其余状态
    （`denied` / `permanentlyDenied` / `restricted` 等）= 已拒绝。
  - 已拒绝时不录音，提示并给出「打开系统设置」动作（`openAppSettings()`）；
    iOS 拒绝后不会再次弹系统框。
  - 设置页「语音」区只读上述三态；仅「已拒绝」显示「打开系统设置」按钮。
  - 从系统设置返回（`resumed`）时重新读取权限状态。
- 系统权限弹窗引起的短暂 `inactive` 只作用于已经开始的录音 / 朗读；
  首次授权会让本次按住收到 `PointerCancel`，按 §3.2 不开录、提示再按住。
- iOS CocoaPods 集成需在 `Podfile` 的 `post_install` 打开
  `PERMISSION_MICROPHONE=1`；使用 SPM 时按包文档启用麦克风宏。

### 5.2 前后台

- v1 只支持前台：不添加 iOS `UIBackgroundModes: audio`，不添加 Android
  前台服务或锁屏控制。
- 应用进入 `inactive`、`paused` 或 `hidden`：
  - 取消进行中的录音 / 转写，丢弃音频，不插入文本；
  - 停止朗读并释放播放器；
  - 回到 `resumed` 后保持 `idle`，不自动恢复。
- 切换会话、离开聊天页、导入历史对话：执行同样的取消 / 停止。
- 权限弹窗与系统设置往返按 §5.1 的例外处理。

### 5.3 隐私

- 录音会上传到 DeepSeek 做转写，朗读正文会发送到 DeepSeek 做合成；
  两者都不落库、不进历史归档、不进导出包。
- 不记录音频、正文、API Key 或请求头到日志。
- 商店隐私声明需覆盖 Audio Data 与用户文本；生产环境仍需后端代理，
  移动端 BYOK 的 Key 可被逆向提取（见 `api.md` / 架构 §7）。

## 6. 错误映射与重试

### 6.1 语音输入

| 场景 | 文案 |
| --- | --- |
| 权限被拒绝 / 受限 | `voiceInputPermissionDenied` + 「打开系统设置」 |
| 无输入设备 / 启动失败 | `voiceInputNoDevice` / `voiceInputFailed` |
| 空录音或 `text.trim()` 为空 | `voiceInputEmpty` |
| 达到 120 秒 | `voiceInputLimitReached`，随后自动转写 |
| 中断（来电、路由、后台、切页） | `voiceInputInterrupted`（仅当前页可见时） |
| ASR 400 / 401 / 402 / 408 / 413 / 429 / 503 / 504 | `voiceInputFailed` |
| 网络失败 / 非 JSON / 缺 `text` | `voiceInputFailed` |
| 后台、切会话、页面销毁取消转写 | 无提示 |
| 首次授权成功（本次未开录） | `voiceMicGrantedRetry` |
| 转写已插入但自动发送被挡 | `voiceInsertedGenerating` / `voiceInsertedUploading` / `voiceInsertedNotSent` / `errorNoApiKey` |
| 自动发送抛错 | `voiceSendFailedInserted` |

- 不区分 413 / 429 / 503 / 504，与 chat-demo 的 `voiceInputFailed` 折叠一致；
  唯一可操作差异由 UI 在重试时自然体现。
- 不自动重试；用户再次按住麦克风即可。
- release 构建不显示服务端原文；debug 构建只记录日志。

### 6.2 朗读

| 场景 | 文案 |
| --- | --- |
| TTS 400（正文不可合成 / 超限） | `ttsUnavailable` |
| 401 | `apiErrorUnauthorized` |
| 402 | `apiErrorInsufficientBalance` |
| 429 | `apiErrorRateLimited` |
| 503 / 504 / 其他 5xx | `ttsFailed` |
| 网络失败 / 协议错误 / 空流 / 播放器错误 | `ttsFailed` |
| 用户停止、切页、后台、音频中断 | 无提示 |

- 与 chat-demo 的状态码映射一致：400 单独区分，401 / 402 / 429 复用通用文案，
  其余折叠为 `ttsFailed`。
- 不自动重试；用户再次点击同一条即可重试。
- 400 后按钮保持可用；重复点击仍会重新请求。

## 7. 波形与动画

- 录音、识别、取消共用同一蓝色动态浮层：贴底覆盖输入卡与草稿行，约 60% 屏高，
  不盖顶部栏、不遮消息区、不加全屏遮罩、不响应点击。
- 蓝区自绘 6 枚缓慢漂移、互相重叠的径向椭圆，形成动态不规则上缘；顶部全透明、
  底部渐到实色；不引入渐变 / 动效库。
- 高光锚定按下 / 移动的真实 pointer 坐标，随 `SpeechState.level` 平滑值脉动；
  取消态不变色，仅把文案换成「松开取消」。
- 波形 32 根（高 28、宽 2.4、间距 1.6），由 `record.onAmplitudeChanged(100ms)`
  的 dBFS 值映射到 `[-50, 0] → 0..1` 后做约 30fps 插值缓动；录音未开始时为
  静止低幅骨架。识别中保留低幅波形。
- 电平与计时刷新不驱动整页重建，只重建浮层。
- 朗读按钮的 4 根竖条为纯装饰，不读取真实音频；开启减少动画时显示静态帧。
- 错误、权限与空态不使用动画，避免误读为进行中。

## 8. 文案表

新增键同时补 `lib/l10n/app_en.arb` 与 `lib/l10n/app_zh.arb`；占位符声明在模板。
键名前缀：`voiceInput*`、`tts*`、`settings*`。

| 键 | 中文 | English | 用途 |
| --- | --- | --- | --- |
| `holdToTalk` | 按住说话 | Hold to talk | 麦克风空闲语义 |
| `voiceHoldToSend` | 松手发送，上滑取消 | Release to send, slide up to cancel | 录音浮层 |
| `voiceReleaseToCancel` | 松开取消 | Release to cancel | 取消态浮层 |
| `voiceRecognizing` | 识别中 | Recognizing | 识别浮层 |
| `voiceMicGrantedRetry` | 已授权麦克风，请再按住说话 | Microphone access granted. Hold to talk again. | 首次授权 Toast |
| `voiceRecordSemantics` | 录音中，双击结束并发送 | Recording. Double-tap to finish and send. | 语义标签与播报 |
| `voiceCancelRecording` | 取消录音 | Cancel recording | 自定义语义动作 |
| `voiceCancelled` | 已取消 | Recording cancelled | 播报 |
| `voiceRecognizingSemantics` | 正在识别 | Recognizing speech | 播报 |
| `voiceSendFailedInserted` | 发送失败，已放入输入框 | Couldn't send. The text is in the message field. | 自动发送抛错 |
| `voiceInsertedGenerating` | 生成中，转写内容已插入输入框 | Generating. Transcription inserted. | 自动发送被挡 |
| `voiceInsertedUploading` | 附件上传中，转写内容已插入输入框 | Attachments uploading. Transcription inserted. | 自动发送被挡 |
| `voiceInsertedNotSent` | 转写内容已插入输入框，未自动发送 | Transcription inserted. Not sent automatically. | 其他拦截原因 |
| `voiceInputPermissionDenied` | 无法使用麦克风，请在系统设置中允许访问 | Microphone access is denied. Allow it in system settings. | 权限拒绝 |
| `voiceInputNoDevice` | 未检测到麦克风 | No microphone detected | 无输入设备 |
| `voiceInputFailed` | 语音识别失败，请稍后再试 | Speech recognition failed. Please try again later. | ASR 与录音失败 |
| `voiceInputEmpty` | 未识别到语音内容 | No speech detected | 空录音 / 空结果 |
| `voiceInputLimitReached` | 已达到单次录音时长上限 | Maximum recording length reached | 120 秒自动结束 |
| `voiceInputInterrupted` | 录音已中断 | Recording interrupted | 来电 / 路由 / 中断 |
| `ttsPlay` | 朗读 | Read aloud | 朗读按钮空闲态 |
| `ttsStop` | 停止朗读 | Stop reading | 加载 / 播放态 |
| `ttsUnavailable` | 这条回答暂时无法朗读 | This answer cannot be read aloud right now | TTS 400 |
| `ttsFailed` | 朗读失败，请稍后再试 | Read-aloud failed. Please try again later. | 其余朗读失败 |
| `settingsTtsVoice` | 朗读音色 | Read-aloud voice | 设置项标题 |
| `settingsTtsVoiceStella` | Stella · 女声 | Stella · female | 音色选项 |
| `settingsTtsVoiceTide` | Tide · 男声 | Tide · male | 音色选项 |
| `settingsSpeech` | 语音 | Speech | 设置分组标题 |
| `settingsMicPermission` | 麦克风权限 | Microphone access | 权限状态行标题 |
| `settingsMicNotRequested` | 未请求 | Not requested | 权限未请求 |
| `settingsMicGranted` | 已允许 | Allowed | 权限已允许 |
| `settingsMicDenied` | 已拒绝 | Denied | 权限被拒绝 / 受限 |
| `settingsSpeechDescription` | 语音输入需要麦克风权限；朗读不需要。v1 只在前台工作。 | Voice input needs microphone access; read-aloud does not. Works in the foreground only. | 设置说明 |
| `settingsOpenSystemSettings` | 打开系统设置 | Open system settings | SnackBar 动作与设置入口 |

复用现有键：`errorNoApiKey`、`apiErrorUnauthorized`、`apiErrorInsufficientBalance`、
`apiErrorRateLimited`。系统权限弹窗文案来自 `InfoPlist.strings`，不进 ARB。

## 9. 设置项与持久化

- `tts.voice`：`stella`（默认）/ `tide`，存 `shared_preferences`；非法值回退
  `stella`。设置页「对话」组的「朗读音色」行（票 20 已定位置），弹层单选；
  切换后下一次朗读生效。
- `speech.micRequested`：布尔值，首次请求麦克风权限后置 `true`，仅用于设置页
  区分「未请求」与「已拒绝」。
- 麦克风权限不提供应用内开关；只展示状态与系统设置入口。
- 导入历史时保留设置与 Key，因此 `tts.voice` 不受导入覆盖影响。
- 不新增数据库表、迁移或归档字段。

## 10. 实现落点

- 共享部分（chat 与 settings 共用，按架构 §1 下沉）：
  - `lib/shared/speech/permissions.dart`：`permission_handler` 状态、请求与跳设置。
  - `lib/shared/prefs/speech_store.dart`：`tts.voice`、`speech.micRequested`。
  - `lib/shared/error_text.dart`：增加 §6 的 `voiceInputErrorText` / `ttsErrorText`；
    不新建第二套映射点（architecture.md §5）。
- 聊天专属（只有 chat 使用，留在 feature 内）：
  - `lib/features/chat/speech/speech_api.dart`：ASR / TTS 请求、PCM 流读取。
  - `lib/features/chat/speech/recorder.dart`：`record` 封装、120 秒计时、电平回调。
  - `lib/features/chat/speech/player.dart`：`flutter_soloud` 封装、首帧缓冲、停止释放。
  - `lib/features/chat/speech/speech_controller.dart`：全局音频状态机、互斥与生命周期；
    新增显式 `startFromPress` / `finishFromRelease` / `cancelFromGesture` 与
    `_starting` 单飞，不把松手接到 `toggleVoiceInput`。
  - `lib/features/chat/speech/voice_button.dart`：`Listener` 按住手势 +
    `Semantics` tap 切换与「取消录音」自定义动作。
  - `lib/features/chat/speech/voice_overlay.dart`：蓝色动态浮层与波形，
    `CustomPainter` 自绘；取代 `recording_status.dart`。
  - `lib/features/chat/speech/read_aloud_button.dart`；在 `chat_page.dart` 的
    输入区与消息操作条接入。
  - 发送、停止生成、继续、重新生成、切换会话、切换分支、页面销毁时调用
    `SpeechController.stopReadAloud()`；`dispose` 调用 `stopAll()`。
- 设置页：
  - 「对话」组加入「朗读音色」下拉；新增「语音」区展示权限三态与系统设置入口；
    权限状态在 `resumed` 时刷新。
  - 只 import `shared/speech/permissions.dart` 与 `shared/prefs/speech_store.dart`，
    不 import `features/chat/`。
- 应用壳：
  - `lib/app/app.dart` 的 `didChangeAppLifecycleState` 增加对所有非 `resumed`
    状态调用 `speechController.handleLifecycle()`。
- 平台与依赖：
  - `pubspec.yaml`：`record: ^7.2.0`、`flutter_soloud: ^5.3.0`、
    `permission_handler: ^13.0.2`。
  - iOS `Info.plist` / `InfoPlist.strings`、Android manifest 见 §5.1。
- `architecture.md` 已把共用语音能力放在 `shared/speech/`；聊天专属的录音、
  播放、状态机与界面在 `features/chat/speech/`，不再单建 `features/speech/`。

## 11. 测试与验收

### 11.1 自动化

- 状态机单测（注入 fake recorder / player / API）：
  - `idle → starting → recording → transcribing → idle`；松手取消、上滑取消。
  - 松手早于 `start()` 返回：返回后 cancel，不转写、不提示；连按只开一次录音。
  - 首次授权 pointer cancel：不开录，提示再按住。
  - 上滑阈值纯函数：按下坐标基准、≥80dp 进入取消、回拉恢复、横向不取消。
  - 120 秒自动停止并只触发一次；cap 后松手 no-op；无样本与空文本。
  - 插入规则：选区替换、无效选区回退末尾、光标位置。
  - 自动发送闸门：无生成中 / 附件全 done / 有 Key / 会话可用 / 未手动改文本；
    被挡时只插入并给对应 Toast；发送抛错保留文本。
  - 朗读同条停止、切换条先停后播、发送 / 停止生成 / 切会话 / 切分支 / 切页停止。
  - 互斥：朗读中开始录音先停朗读；录音 / 识别中朗读入口不可用。
  - 生命周期非 `resumed` 取消录音并停朗读。
- 请求契约单测：ASR multipart 字段、文件名、Bearer 头；TTS JSON 字段、
  `filter_markdown: true`、音色快照；取消会中止请求。
- 错误映射单测：§6 两张表逐项覆盖；400 不显示服务端原文。
- 存储单测：`tts.voice` 默认、持久化、非法值回退；`speech.micRequested` 三态。
- Widget 测试：语音按钮三态、朗读三态、设置页权限状态与音色选择；
  中英文案与减少动画。
- 平台插件用 `integration_test` 在真机覆盖：真实权限、录音文件格式与时长、
  PCM 首帧播放、停止释放、来电 / 后台中断、录音后立即朗读。

### 11.2 手动验收

1. 按住麦克风 → 浮层出现；松手 → 识别 → 文本插入并自动发送；有文本时麦克风隐藏。
2. 首次按住 → 系统授权；授权后不开录，提示「已授权麦克风，请再按住说话」；
   再次按住才录音。拒绝权限 → 提示与「打开系统设置」。
3. 上滑 80dp → 「松开取消」+ 触感；回拉恢复；松手取消无 Toast、无插入。
4. 录满 120 秒 → 提示上限并自动转写发送；文件不超过 8 MiB。
5. 识别中无取消入口；切会话 / 进后台 / 来电 → 取消转写或丢弃录音，不插入文本，
   临时文件已删除。
6. 静音 / 空结果 → 「未识别到语音内容」。
7. 断网、无效 Key、429 / 503 等 ASR 失败 → 统一「语音识别失败」。
8. 生成中 / 附件上传中松手 → 只插入并提示对应原因；发送抛错文本留在输入框。
9. 点击可朗读回复 → `loading` → 首帧即播；再次点击停止；点另一条切换；
   全程只有一条在读。
10. 朗读中发送 / 停止生成 / 重新生成 / 切会话 / 进后台 → 立即停止。
11. TTS 400 → 「这条回答暂时无法朗读」；401 / 402 / 429 / 503 文案符合 §6.2。
12. 开启减少动画：朗读竖条静态、浮层蓝区与波形冻结；无障碍标签随状态变化。
13. 中英双语、浅深主题下浮层、Toast、设置区文案正确。

v1 截图第 6 项「朗读回答与语音输入」对应本节的 1–13；票 19 的验收对照表
应逐条引用这里的用例。

## 12. 风险与未决

1. **TTS PCM 字节序未在官方文档写明**：chat-demo 按小端。实现前用已知 PCM
   spike 验证 `BufferType.s16le`；若不符，播放器层做字节交换。
2. **`record` 与 `flutter_soloud` 的音频会话切换**必须真机验证；
   若冲突，先在录音停止后显式等待释放，仍失败则播放侧降级到 `just_audio`
   （整段 WAV，失去首帧流式），并在票内记录。
3. **Android 音频中断上报不完整**：来电 / 焦点丢失主要依赖应用生命周期兜底；
   真机验收必须覆盖。
4. **ASR 401 / 402、TTS 401 / 402 未在语音文档中列出**：ASR 侧按 §6.1 折叠为
   `voiceInputFailed`；TTS 侧 401 / 402 复用通用文案。用真实 Key 复核后如无
   这两个状态码，保留映射不增加分支。
5. **ASR 10 分钟上传窗口未由客户端计时**：只提供手动取消；长时弱网可能收到
   408 / 504，统一按 `voiceInputFailed` 处理。
6. **TTS 10,000 billed characters / 64 KiB 上限**：不做客户端截断；超限走 400。
7. **部分音频后断流**无法与正常结束区分，只能按传输异常处理；已播出的部分
   会停止并提示，不静默成功。
8. **后台 / 锁屏朗读与录音明确不支持**：需要时另立票，接后台音频模式与
   前台服务，不在 v1 隐式启用。
9. **隐私与商店声明**：上传录音与朗读正文需在隐私政策、App Store 隐私标签、
   Google Play Data Safety 中披露。
10. **`record` 7.x 要求 Flutter 3.44 / Dart 3.12**：当前工具链满足；若回退
    Flutter，需锁定 `record` 6.2.x 并复测。
11. **`Listener` 不参与 gesture arena**：输入区当前不在可滚动父级内，按住不会
    触发滚动；若将来把输入卡放进滚动容器，需改用 `RawGestureDetector`。
12. **首次授权会让本次按住收到 `PointerCancel` 且无 `PointerUp`**：基于 Flutter
    手势事实设计为「授权后不自动开录」；仍需 iOS / Android 真机各验证一次
    系统弹窗行为，若与事实不符再调整。
13. **上滑取消在无障碍下无等价手势**：读屏用户只能走语义 tap 切换与
    「取消录音」自定义动作，与按住手势不是同一路径，验收需分别覆盖。
