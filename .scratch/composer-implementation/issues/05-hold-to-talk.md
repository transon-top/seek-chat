# 05: 按住说话状态机与手势

**What to build:** 麦克风从「点击开始、再点结束」改成按住说话：按下即录，
松手转写并尝试自动发送，上滑 80dp 取消。录音期间用基础浮层覆盖输入卡；首次
授权、无 Key、无设备与中断都有明确提示。浮层最终视觉由下一票完成。

**Blocked by:** 02
**Status:** resolved
**Type:** task

- [x] 状态机为 `idle → starting → recording → transcribing → idle`，另有
      `cancelling`；提供显式开始 / 松手结束 / 手势取消入口，`_starting` 单飞防连按。
- [x] 按下同步失焦、收键盘、收面板并显示浮层骨架；随后读 Key、检查并请求麦克风
      权限、启动录音。首次授权导致 pointer cancel 时不开录，提示
      `voiceMicGrantedRetry`；松手早于启动完成则取消且不转写、不提示。
- [x] 用 `Listener` 跟踪首个 pointer：只认 pointer down / move / up / cancel；
      以按下全局 Y 为基准，上滑 ≥80dp 进入取消态、可回拉；横向位移不取消，
      滑出按钮范围不结束；进入取消态 `mediumImpact`，恢复 `lightImpact`。
- [x] 松手 → 停止录音 → 转写；空结果 / 失败沿用 `voiceInputEmpty` /
      `voiceInputFailed`；120 秒上限自动停止并转写，保留 `voiceInputLimitReached`
      提示，cap 后松手 no-op。
- [x] 转写成功先按当前选区插入输入框，再满足「无生成中、附件全部 done、有 Key、
      会话可用、转写期间未手动输入」时复用发送流程；不满足只插入并按原因提示
      `voiceInsertedGenerating` / `voiceInsertedUploading` / `voiceInsertedNotSent` /
      `errorNoApiKey`；发送抛错保留文本并提示 `voiceSendFailedInserted`。
- [x] 取消：上滑松手静默丢弃；来电 / 路由中断丢弃并提示 `voiceInputInterrupted`；
      录音中系统返回第一次只取消录音并停留页面；切会话、离开页面、进后台、
      页面销毁静默取消并丢弃。录音开始时停止朗读。
- [x] 权限拒绝、无设备、启动失败、无 Key 分别提示既有文案；资源释放干净。
- [x] 基础浮层覆盖输入卡与草稿行、约 60% 屏高、不盖顶部栏、不响应点击；
      录音显示「松手发送，上滑取消」，取消态「松开取消」，识别中「识别中」。
- [x] 无障碍：麦克风语义 tap 切换开始 / 结束（无需按住），录音中提供「取消录音」
      自定义动作；浮层文案为 liveRegion，只播报开始、取消、识别、发送失败。
- [x] 新增 ARB：`holdToTalk`、`voiceHoldToSend`、`voiceReleaseToCancel`、
      `voiceRecognizing`、`voiceMicGrantedRetry`、`voiceRecordSemantics`、
      `voiceCancelRecording`、`voiceCancelled`、`voiceRecognizingSemantics`、
      `voiceSendFailedInserted`、`voiceInsertedGenerating`、
      `voiceInsertedUploading`、`voiceInsertedNotSent`。
- [x] 测试覆盖：转移表、连按单飞、首次授权、松手早于启动、阈值纯函数、cap、
      自动发送各闸门与 Toast、后台 / 切会话取消、语义 tap 与取消动作。

## Answer

- `speech_controller.dart`：相位扩为 `idle / starting / recording / cancelling /
  transcribing / loading / playing`；公开 `startFromPress` / `finishFromRelease` /
  `cancelFromGesture` / `setCancelArmed` / `cancelFromSemantics` / `cancelFromBack`。
  `_starting` 单飞；`_releasePending` / `_cancelPending` / `_cancelWhileGranting`
  记录启动期间的手势结束。首次授权弹窗取消开录并提示 `voiceMicGrantedRetry`；
  已授权时松手早于 `start()` 返回则静默取消。
- 转写回调改为 `VoiceTranscriptHandler`，返回 `VoiceAutoSendOutcome`；聊天页先按
  选区插入，再按无 Key / 生成中 / 上传中 / 手动输入闸门决定是否复用 `_send()`，
  控制器按结果提示既有或新增原因。`_send()` 改为返回是否已发送。
- `voice_button.dart` 换成 `Listener` + 首个 pointer id + 全局 Y 80dp 阈值纯函数
  `shouldCancelVoice`；进入 / 离开取消态分别 `mediumImpact` / `lightImpact`。
  语义 tap 在空闲时开始、录音时结束；录音 / 取消态暴露「取消录音」自定义动作。
- `recording_overlay.dart`（新增，GLOSSARY 的 Recording Overlay）基础浮层：贴底
  60% 屏高、`IgnorePointer`、三种文案、liveRegion 语义、`ShadTheme` 主色；票 06
  替换为蓝色动态视觉。旧 `recording_status.dart` 与废弃 ARB（`voiceInput*`
  状态文案）随状态行一并删除并重跑 `gen-l10n`。
- 启动期间已滑过 80dp 的取消标记会保留，开录后直接进入 `cancelling`；120 秒上限
  在取消态只结束并丢弃，避免误发送。草稿行、输入框与两个开关在浮层期间不可操作。
- 录音开始时先停朗读；权限被拒绝时若朗读未停则恢复原相位。系统返回在
  `starting` / `recording` / `cancelling` 时只取消录音并留在页面；转写中返回由
  页面销毁路径静默取消。输入框在录音期间 `readOnly` + `IgnorePointer`。
- 文案新增 13 个键（中英）；复用权限 / 无设备 / 失败 / 空 / 上限 / 中断文案。
- 测试：状态机与手势单测、TTS 回归、按钮语义与阈值、浮层文案 / liveRegion /
  不拦截点击、聊天页端到端（按住 → 插入 → 自动发送、无 Key、系统返回取消）。
- 验证：`flutter analyze` 无问题；`flutter test` 471 通过。
- 遗留：浮层最终蓝色动态视觉、波形与减少动画冻结留给票 06；真机手势与系统
  权限弹窗的证据留给票 07。
