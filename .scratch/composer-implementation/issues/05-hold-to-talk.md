# 05: 按住说话状态机与手势

**What to build:** 麦克风从「点击开始、再点结束」改成按住说话：按下即录，
松手转写并尝试自动发送，上滑 80dp 取消。录音期间用基础浮层覆盖输入卡；首次
授权、无 Key、无设备与中断都有明确提示。浮层最终视觉由下一票完成。

**Blocked by:** 02
**Status:** open
**Type:** task

- [ ] 状态机为 `idle → starting → recording → transcribing → idle`，另有
      `cancelling`；提供显式开始 / 松手结束 / 手势取消入口，`_starting` 单飞防连按。
- [ ] 按下同步失焦、收键盘、收面板并显示浮层骨架；随后读 Key、检查并请求麦克风
      权限、启动录音。首次授权导致 pointer cancel 时不开录，提示
      `voiceMicGrantedRetry`；松手早于启动完成则取消且不转写、不提示。
- [ ] 用 `Listener` 跟踪首个 pointer：只认 pointer down / move / up / cancel；
      以按下全局 Y 为基准，上滑 ≥80dp 进入取消态、可回拉；横向位移不取消，
      滑出按钮范围不结束；进入取消态 `mediumImpact`，恢复 `lightImpact`。
- [ ] 松手 → 停止录音 → 转写；空结果 / 失败沿用 `voiceInputEmpty` /
      `voiceInputFailed`；120 秒上限自动停止并转写，保留 `voiceInputLimitReached`
      提示，cap 后松手 no-op。
- [ ] 转写成功先按当前选区插入输入框，再满足「无生成中、附件全部 done、有 Key、
      会话可用、转写期间未手动输入」时复用发送流程；不满足只插入并按原因提示
      `voiceInsertedGenerating` / `voiceInsertedUploading` / `voiceInsertedNotSent` /
      `errorNoApiKey`；发送抛错保留文本并提示 `voiceSendFailedInserted`。
- [ ] 取消：上滑松手静默丢弃；来电 / 路由中断丢弃并提示 `voiceInputInterrupted`；
      录音中系统返回第一次只取消录音并停留页面；切会话、离开页面、进后台、
      页面销毁静默取消并丢弃。录音开始时停止朗读。
- [ ] 权限拒绝、无设备、启动失败、无 Key 分别提示既有文案；资源释放干净。
- [ ] 基础浮层覆盖输入卡与草稿行、约 60% 屏高、不盖顶部栏、不响应点击；
      录音显示「松手发送，上滑取消」，取消态「松开取消」，识别中「识别中」。
- [ ] 无障碍：麦克风语义 tap 切换开始 / 结束（无需按住），录音中提供「取消录音」
      自定义动作；浮层文案为 liveRegion，只播报开始、取消、识别、发送失败。
- [ ] 新增 ARB：`holdToTalk`、`voiceHoldToSend`、`voiceReleaseToCancel`、
      `voiceRecognizing`、`voiceMicGrantedRetry`、`voiceRecordSemantics`、
      `voiceCancelRecording`、`voiceCancelled`、`voiceRecognizingSemantics`、
      `voiceSendFailedInserted`、`voiceInsertedGenerating`、
      `voiceInsertedUploading`、`voiceInsertedNotSent`。
- [ ] 测试覆盖：转移表、连按单飞、首次授权、松手早于启动、阈值纯函数、cap、
      自动发送各闸门与 Toast、后台 / 切会话取消、语义 tap 与取消动作。
