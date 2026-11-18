# 语音输入与朗读方案调研

Type: research
Status: resolved

## Question

1. 核实 chat-demo 的 ASR / TTS 协议：`src/services/api/speech.ts`、`src/services/speech/recorder.ts`、`readAloud.ts` 的端点、请求 / 响应、流式方式、鉴权。
2. Flutter 录音：record / flutter_sound 等包的现状、格式（PCM / WAV / Opus）、采样率、权限、后台行为。
3. Flutter 播放：just_audio / audioplayers 的流式播放、中断、音量、进度。
4. 波形 / 频谱：audio_waveforms 等包；chat-demo 的 ReadingBars 对应实现。
5. iOS / Android 权限与隐私声明（麦克风、语音识别）。
6. 失败态：权限拒绝、无网络、服务端错误、录音中断。
7. 结论：主选 + 备选 + 风险。

产出：`docs/research/speech.md`，含来源与核查日期。

## Answer

调研完成（2026-11-18）。完整结论见 `research/speech` 分支：
`docs/research/speech.md`（commit `2ef5b5c373167898bb943b11522b92c100e92612`，未合并）。
https://github.com/transon-top/open-chat/blob/2ef5b5c373167898bb943b11522b92c100e92612/docs/research/speech.md

**协议归属**：`POST /v1/tools/asr` 与 `POST /v1/tools/tts` 是 DeepSeek 公开 API（2026-11-13 公告），不是 chat-demo 私有扩展。

**ASR**

- multipart `file`；16-bit PCM WAV 或 Ogg Opus；≤120 秒、≤8 MiB；立体声只识别左声道。
- 不支持流式识别，整段上传整段返回；响应 JSON 取 `text`。
- 错误码：400 / 408 / 413 / 429 / 503 / 504；单账号 50 并发。

**TTS**

- JSON：`text`、`voice_id`（`stella` 女声 / `tide` 男声）、`format`（`wav` / `pcm`）、`filter_markdown`。
- PCM 为 raw 16-bit signed mono 24 kHz；响应流式返回；另有 WebSocket 备选。
- 不支持取消 / 续传 / 变速；单请求最多 30 分钟音频；≤10,000 billed characters、请求体 ≤64 KiB。

**主选**

- 录音 `record` 7.2.0：WAV 16-bit / 16 kHz / 单声道，权限内置，BSD-3。
- 播放 `flutter_soloud` 5.3.0：`BufferType.s16le` + `addAudioDataStream()` 逐块喂 PCM，保留首帧流式，MIT。
- 波形 v1 用 `record.onAmplitudeChanged()`；真实波形 `audio_waveforms` 2.0.2；频谱用 `fftea` 自绘。

**备选**

- `just_audio` 0.10.6：整段 PCM 缓冲成 WAV 再播，最稳但失去首帧流式。
- `flutter_sound` 9.30.0：可 PCM 流式，但 2025-11 后停更、366 个开放 issue。

**不选 / 不存在**

- `audioplayers`：无裸 PCM 增量接口。
- `flutter_audio_waveforms` / `flutter_pcm_player`：SDK `<3.0.0`。
- `flutter_opus_wave` / `pcm_player`：pub.dev 404。

**风险**

- TTS PCM 字节序官方未写明，chat-demo 按小端；需 spike 验证。
- `record` 与 `flutter_soloud` 可能争抢音频会话；录音 → 播放切换需真机验证。
- `record` 7.x 要求 Flutter 3.44 / Dart 3.12。
- DeepSeek 语音 API 很新，限额与错误码可能调整。
- 移动端 BYOK 的 API Key 可被逆向提取；生产分发需后端代理。
- 后台播放 / 锁屏朗读未验证；v1 按前台设计。

**交接**：行为规格见票 21。
