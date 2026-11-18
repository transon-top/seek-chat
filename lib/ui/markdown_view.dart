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
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: GptMarkdown(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
        useDollarSignsForLatex: false,
        onLinkTap: _openLink,
        // shortcut: 流式无显式节流，图片仅 Flutter 内存缓存；票 08 定性能预算与图片缓存要求后升级。
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

/// 只打开 http(s)，避免模型输出触发任意 URI scheme。
Future<void> _openLink(String url, String title) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
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
