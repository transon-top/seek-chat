# 语音输入与朗读行为规格

Type: grilling
Status: resolved
Blocked by: 15

## Question

基于票 15 的协议与包调研，锁定行为：

1. 语音输入状态机：idle / recording / transcribing / error；点击、取消、120 秒上限、空结果。
2. 转写结果插入：光标位置、是否覆盖选区、失败文案（是否区分 413 / 429 / 503 / 504）。
3. 朗读：`voice_id` 默认（stella / tide）、音色设置入口、Markdown 过滤、首帧流式播放。
4. 播放状态：idle / loading / playing；同一时间只允许一条；切换消息时的停止逻辑。
5. 错误映射：400 / 401 / 402 / 429 / 503 / 504 的中英文案与重试。
6. 权限：麦克风拒绝、跳系统设置的路径；iOS `NSMicrophoneUsageDescription` / Android `RECORD_AUDIO`。
7. 音频会话：录音结束到播放开始的切换；来电 / 音频焦点丢失。
8. 波形：v1 电平条；真实波形与频谱是否进 v1。
9. 后台 / 锁屏行为：明确 v1 只支持前台。
10. 验收：录音 → 转写 → 插入、朗读 → 停止、失败态、权限拒绝。

产出：`speech.md` 章节 + 状态机 + 文案表。

## Answer

行为规格见 [`speech.md`](../speech.md)，状态机、错误映射、中英文案表与验收用例均在文内。

- **语音输入**：`idle → recording → transcribing`，失败进入瞬态 `error` 后立即回
  `idle`；再次点击结束并转写、转写中再点取消、120 秒自动结束；结果去空白后替换
  选区插入光标处，不自动发送。除权限 / 无设备 / 空结果 / 上限 / 中断外，
  ASR 400/401/402/408/413/429/503/504 全部折叠为 `voiceInputFailed`，与 chat-demo
  一致；不自动重试。
- **朗读**：只在 assistant 操作条入口；`idle / loading / playing`；同条点按停止，
  换条先停再播；发送、停止生成、继续、重新生成、切会话、离开页面、后台均停止；
  服务端 `format: pcm` + `filter_markdown: true`，首帧流式；400 → `ttsUnavailable`，
  401/402/429 复用通用文案，其余 → `ttsFailed`；无自动重试。
- **互斥**：录音与朗读共享一个全局音频状态机；录音前先停朗读，语音非空闲时
  朗读入口置灰；录音释放后再初始化播放器。
- **权限**：只申请麦克风；`permission_handler` 统一状态 / 请求 / 跳系统设置；
  用本地「已请求」标志区分未请求与已拒绝；iOS 不申请语音识别权限。
- **前后台**：v1 仅前台；非 `resumed` 取消录音、停止朗读，不自动恢复。
- **波形**：v1 用 `onAmplitudeChanged(100ms)` 的 5 根电平条；真实波形与频谱不进 v1。
- **落点**：权限与音色偏好在 `lib/shared/speech/` 与 `lib/shared/prefs/`，
  录音 / 播放 / 状态机与按钮在 `lib/features/chat/speech/`；
  `architecture.md` 的 `features/speech/` 预留已改写。
- **实现前 spike**：TTS PCM 小端字节序、`record` 与 `flutter_soloud` 的音频会话切换、
  Android 中断上报；失败时播放侧降级 `just_audio`。其余风险见 `speech.md` §12。

本票解锁票 10 的语音部分；v1 截图第 6 项「朗读回答与语音输入」的验收用例见
[`speech.md`](../speech.md) §11。
