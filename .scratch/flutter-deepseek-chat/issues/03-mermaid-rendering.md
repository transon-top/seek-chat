# Mermaid 渲染方案调研

Type: research
Status: resolved

## Question

Flutter 端渲染 Mermaid 图，有哪些真实可用的方案？用户提供了一份网络清单，需逐一核实真伪与现状：

- `mermaid_flutter` + `mermaid_core`（声称纯 Dart + CustomPainter，28 种图）
- `flutter_mermaid`（声称纯 Dart）
- `flutter_mermaid_native` / `merman`（声称 Rust FFI）
- `flutter_smooth_markdown` / `markdown_forge`（声称 Markdown 包内置）

必须回答：

1. 每个包是否真实存在于 pub.dev：版本、发布者、源码仓库、最近更新、pub points / likes、许可证。
2. 若不存在或已废弃，明确写出，并给出真实替代方案。
3. 支持的图类型与语法覆盖：flowchart、sequence、class、state、ER、gantt、pie、timeline、mindmap 等，实际支持到什么程度。
4. 实现方式：纯 Dart / FFI / WebView / 远程渲染；对包体积、构建链、平台（iOS/Android）的影响。
5. 渲染质量：布局是否接近 mermaid.js；主题、字体、handDrawn 风格。
6. 集成方式：能否作为 Markdown fenced code 的自定义渲染器；尺寸测量、流式半截语法容错、错误提示。
7. 交互：缩放、平移、点击节点、复制源码。
8. 性能与稳定性：大图、多图、滚动列表中的开销。
9. 降级方案：WebView + 本地 mermaid.js 的成本与可行性。

结论需给出「主选 + 备选 + 不选及理由」，并注明每条事实的来源与核查日期。用户清单中不存在的包要直接指出，不得沿用。

## Answer

调研完成（2026-11-18）。完整结论见 `research/mermaid-rendering` 分支：
`docs/research/mermaid-rendering.md`（commit `b873e0bef099b116c1f41d56570d8c70de8aef2a`，未合并）。
https://github.com/transon-top/open-chat/blob/b873e0bef099b116c1f41d56570d8c70de8aef2a/docs/research/mermaid-rendering.md

**用户清单逐项核实：7 个名字全部真实存在（pub.dev 200），没有 404。** 问题在能力描述被夸大，不在包名。

| 包 | 结论 |
|---|---|
| `mermaid_flutter` 0.3.2 | 存在，纯 Dart + CustomPainter，28 种图，活跃；MIT |
| `mermaid_core` 0.3.2 | 存在，纯 Dart 解析/布局；MIT（包内 LICENSE；pub.dev 标签为 unknown） |
| `flutter_mermaid` 0.1.0 | 存在，仅 8 种图，class/state 是 TODO，2026-03 后停更 |
| `flutter_mermaid_native` 0.1.0 | 存在，Rust FFI，单日实验发布；PNG 光栅 + flutter_svg 限制 |
| `merman` 0.10.0 | 存在，Rust/Dart FFI，不是 Flutter widget；只输出 SVG |
| `flutter_smooth_markdown` 0.10.0 | 存在，Markdown 内置 Mermaid，11 种图 |
| `markdown_forge` 0.1.1 | 存在，Mermaid 仅 flowchart + sequence |

**主选：`mermaid_flutter` + `mermaid_core`**

- 唯一仍在维护、纯 Dart、28 种图、带流式 last-good scene 与节点/缩放交互的方案。
- 通过 `gpt_markdown` 的 `codeBuilder` 接入。

**备选**

- `flutter_smooth_markdown`：Markdown 内置、复制/全屏/缩放开箱即用，但图类型覆盖窄；且与已选 Markdown 库冲突。
- WebView + 本地 mermaid.js：保真度最高，约 1.6 MB gzip asset，每图一个平台视图；只做兜底。

**不选**：`flutter_mermaid`（停更）、`flutter_mermaid_native`（实验性 + Rust 构建链）、`merman`（无 Flutter widget，SVG/foreignObject 问题）、`markdown_forge`（2 种图）。

**限制**

- 未跑真机 PoC；`mermaid_flutter` 的 parity 是维护者自评。
- 仍为 0.3.x，API 可能变化；仓库 main 已是 0.4.0 未发布。
