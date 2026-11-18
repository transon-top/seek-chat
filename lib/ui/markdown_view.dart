import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:gpt_markdown/custom_widgets/code_field.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid_core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// 渲染回复中的 Markdown 文本。
///
/// 数学默认只认 `\(...\)` / `\[...\]`；单 `$` 会误伤价格文本（票 02）。
/// `mermaid` 围栏交给 `mermaid_flutter`，其余围栏走代码高亮与复制。
///
/// 流式期间按上次渲染耗时的两倍节流，把连续 token 合并成一次更新；
/// 区间限制在 50ms 到 2s（票 08）。
class MarkdownView extends StatefulWidget {
  const MarkdownView({super.key, required this.text, this.streaming = false});

  final String text;

  /// 回复仍在流式生成时为 true；流结束后立即显示全文。
  final bool streaming;

  /// 单块超过此长度时不再解析 Markdown，按纯文本展示（票 08 的降级上限）。
  static const int plainTextLimit = 200000;

  static const Duration minInterval = Duration(milliseconds: 50);
  static const Duration maxInterval = Duration(milliseconds: 2000);

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  String _shown = '';
  Timer? _windowTimer;
  DateTime? _renderStartedAt;
  Duration _lastCost = Duration.zero;

  @override
  void initState() {
    super.initState();
    _shown = widget.text;
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _shown) {
      if (!widget.streaming) _windowTimer?.cancel();
      return;
    }
    // 新回复、切换版本或流结束：不做节流等待，直接显示最新全文。
    if (!widget.streaming || !widget.text.startsWith(_shown)) {
      _showLatest();
      return;
    }
    if (_windowTimer?.isActive ?? false) return; // 窗口内的输出合并到窗口结束
    _showLatest();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    super.dispose();
  }

  /// 立即显示最新文本；节流窗口在该帧结束后才开始计时（票 08）。
  void _showLatest({bool rebuild = false}) {
    _windowTimer?.cancel();
    _shown = widget.text;
    _renderStartedAt = DateTime.now();
    if (rebuild && mounted) setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) => _afterRender());
  }

  /// 记录本帧耗时并开启下一个更新窗口；窗口结束时有积压才再渲染。
  void _afterRender() {
    final started = _renderStartedAt;
    if (!mounted || started == null) return;
    _renderStartedAt = null;
    _lastCost = DateTime.now().difference(started);
    _windowTimer = Timer(_interval(), () {
      if (!mounted) return;
      if (widget.streaming && widget.text != _shown) {
        _showLatest(rebuild: true);
      }
    });
  }

  Duration _interval() {
    final doubled = _lastCost * 2;
    if (doubled < MarkdownView.minInterval) return MarkdownView.minInterval;
    if (doubled > MarkdownView.maxInterval) return MarkdownView.maxInterval;
    return doubled;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return SelectionArea(
      child: _shown.length > MarkdownView.plainTextLimit
          ? Text(_shown, style: style)
          : GptMarkdown(
              _shown,
              style: style,
              useDollarSignsForLatex: false,
              onLinkTap: _openLink,
              // 与 chat-demo 一致：图片不加载，只显示可点击的地址（票 08）。
              imageBuilder: _imageAsLink,
              codeBuilder: (context, name, code, closed) {
                if (name.trim().toLowerCase() == 'mermaid') {
                  return _MermaidBlock(source: code);
                }
                return CodeField(name: name, codes: code);
              },
            ),
    );
  }
}

Widget _imageAsLink(
  BuildContext context,
  String url,
  double? width,
  double? height,
) {
  final colors = Theme.of(context).colorScheme;
  final uri = _webUri(url);
  return GestureDetector(
    onTap: uri == null ? null : () => _openLink(uri.toString(), ''),
    child: Text(
      uri?.toString() ?? url,
      style: TextStyle(
        color: colors.primary,
        decoration: TextDecoration.underline,
      ),
    ),
  );
}

/// 无协议地址补 `https://`（对齐 chat-demo）；只放行 http(s)。
Uri? _webUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('mailto:')) return null;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
  final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// 只打开 http(s)，避免模型输出触发任意 URI scheme。
Future<void> _openLink(String url, String title) async {
  final uri = _webUri(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // 链接打不开时保持内容可读，不中断渲染。
  }
}

class _MermaidBlock extends StatelessWidget {
  const _MermaidBlock({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 320,
        child: MermaidView(
          source: source,
          theme: dark
              ? mermaid_core.MermaidTheme.darkTheme
              : mermaid_core.MermaidTheme.defaultTheme,
          keepLastGoodSceneOnError: true,
          // 无可用图时降级为源码；此处宽度不受限，不能用 CodeField。
          errorBuilder: (context, error) => Text(
            source,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
