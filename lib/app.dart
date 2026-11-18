import 'package:material_ui/material_ui.dart';

import 'api/client.dart';
import 'data/attachment_store.dart';
import 'data/chat_repository.dart';
import 'settings/api_key_store.dart';
import 'ui/home_page.dart';

/// 应用壳与依赖接线；路由、主题与双语由界面票补齐。
class OpenChatApp extends StatelessWidget {
  const OpenChatApp({
    super.key,
    required this.repository,
    required this.client,
    required this.apiKeyStore,
    required this.attachmentStore,
  });

  final ChatRepository repository;
  final DeepSeekApiClient client;
  final ApiKeyStore apiKeyStore;
  final AttachmentStore attachmentStore;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4D6BFE);
    return MaterialApp(
      title: 'Open Chat',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: HomePage(
        repository: repository,
        client: client,
        apiKeyStore: apiKeyStore,
        attachmentStore: attachmentStore,
      ),
    );
  }
}
