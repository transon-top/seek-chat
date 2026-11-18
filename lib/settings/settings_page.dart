import 'package:material_ui/material_ui.dart';

import '../api/client.dart';
import '../api/errors.dart';
import '../models/types.dart';
import 'api_key_store.dart';

/// 最小设置页：填写并校验 DeepSeek API Key。界面规格见票 10 / 20。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.client,
    required this.apiKeyStore,
  });

  final DeepSeekApiClient client;
  final ApiKeyStore apiKeyStore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final saved = await widget.apiKeyStore.read();
    if (!mounted || saved == null) return;
    _controller.text = saved;
  }

  Future<void> _save() async {
    final apiKey = _controller.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _error = '请输入 API Key');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.client.validateApiKey(apiKey);
      await widget.apiKeyStore.write(apiKey);
      if (!mounted) return;
      Navigator.maybePop(context);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    await widget.apiKeyStore.clear();
    if (!mounted) return;
    _controller.clear();
    setState(() => _error = null);
  }

  String _errorText(ApiException error) {
    switch (error.condition) {
      case ApiErrorCondition.unauthorized:
        return 'API Key 无效';
      case ApiErrorCondition.network:
        return '网络错误，请检查连接';
      default:
        return error.message;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DeepSeek API Key', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'sk-...',
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存并校验'),
          ),
          TextButton(
            onPressed: _loading ? null : _clear,
            child: const Text('清除已保存的 Key'),
          ),
        ],
      ),
    );
  }
}
