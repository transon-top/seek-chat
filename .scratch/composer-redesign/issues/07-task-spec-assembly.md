# 规格回写与验收清单

Type: task
Status: open
Blocked by: 01, 02, 03, 04, 05, 06

## Question

把本图所有决议落成实现会话可直接执行的规格：

1. 回写 `ui.md`：输入区结构、空态布局、按钮矩阵、附件面板、草稿附件行、录音浮层；尺寸/颜色/动画。
2. 回写 `speech.md`：按住说话状态迁移、自动发送、取消、转写与中断、无障碍。
3. 回写 `attachments.md`：推翻「不引入 image_picker、不实现拍照」，补拍照/最近照片/HEIC/权限降级。
4. 更新 `GLOSSARY.md` 的 Voice Input 定义与新增术语（如「按住说话」「设备照片横条」）；只写领域语言，不写实现。
5. l10n key 清单与中英文案。
6. 测试清单：现有 `test/features/chat/composer_test.dart`、`speech_controller_test.dart`、`speech_widgets_test.dart` 的改动；新增手势、面板、草稿行、权限降级测试。
7. 真机视觉验收清单（iOS + Android，深/浅色）与回滚点。
8. 输出本图 `spec.md` 供执行图使用。

## Deliverable

更新后的规格文件 + 本图 `spec.md`；票内 Answer 摘要。
