# 输入区视觉对图原型（票 06）

一次性粗原型，回答「输入区改版长什么样」。全部为假数据与假状态：没有输入、
上传、录音或网络。视觉依据 `.scratch/composer-redesign/issues/` 中已关闭票
03、04、05 的决议；生产实现按票 07 汇总的规格另做。

## 运行

```sh
flutter run -t prototype/composer_redesign/main.dart -d <设备 id>
```

顶部悬浮控制条切换状态与深浅主题；它不属于被评估的视觉，截图模式不渲染。

可选启动参数：

```sh
flutter run -t prototype/composer_redesign/main.dart \
  --dart-define=PROTOTYPE_SCENARIO=panel \
  --dart-define=PROTOTYPE_DARK=true
```

## 状态

| `PROTOTYPE_SCENARIO` | 内容 |
| --- | --- |
| `empty` | 空态：问候语居中，`+` / 麦克风 / 发送禁用 |
| `typed` | 有文本：`+` / 发送，麦克风隐藏 |
| `panel` | 面板展开：`×` / 麦克风 / 发送，照片勾选与「管理」格 |
| `panelDenied` | 面板：照片权限拒绝，三宫格仍可用 |
| `panelEmpty` | 面板：没有最近照片 |
| `drafts` | 草稿附件行：图片、上传中、失败、文件卡 |
| `busy` | 生成中：`+` 禁用，发送槽为停止 |
| `transcribing` | 识别中：同一蓝色浮层 + 低幅波形 |
| `recording` | 按住说话：动态蓝色团块，波形随电平实时起伏 |
| `cancelling` | 上滑取消态：复用同一蓝色效果，仅改文案「松开取消」 |

蓝色区域不是水平渐变：由多枚缓慢漂移的椭圆团块构成不规则、动态的上边缘；
高光锚定在按住位置，随假电平脉动。录音、识别、取消三种状态共享同一效果，
只换文案、不变色。波形在原型里用假电平逐帧起伏；生产实现把高光换成真实
pointer 坐标，电平取 `SpeechState.level`（见票 05）。

## 依赖调研

pub.dev 上的现成方案都不贴合：

- `mesh_gradient`（MIT，281 likes）：支持自定义点与动画，但没有遮罩与单点亮度控制，
  需要把整个区域铺满再裁剪，且自带 `flutter_shaders` 依赖。
- `mesh`（MPL-2.0，181 likes）：shader + vertices 的全屏网格渐变，同样不是局部高光。
- `bokeh_lava_gradient`（MIT）：模糊色块漂移最接近，但无法控制单个色块位置，也不跟随指针。

结论：不引依赖，用 `CustomPainter` 画 6 枚径向渐变团块 + 高光即可（约 100 行），
并且能直接锚定真实 pointer 位置。

## 自动截图

```sh
flutter run -t prototype/composer_redesign/main.dart -d <设备 id> \
  --dart-define=PROTOTYPE_SHOTS=true
```

以 2× 像素比把 10 个状态 × 深浅两套写入应用文档目录的
`composer_redesign_shots/`，文件名形如 `iphone-panel-dark.png` /
`android-recording-light.png`。iPhone 与 Android 模拟器各跑一次，覆盖两种常见宽度。

## 明确不做

- 真实输入、上传、录音、转写、发送与动画编排。
- 无障碍、动态字体与减少动画（生产实现另做）。
- 接入 `lib/` 的任何界面代码；本目录整体可删。
