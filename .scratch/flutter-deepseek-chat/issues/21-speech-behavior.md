# 语音输入与朗读行为规格

Type: grilling
Status: open
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
