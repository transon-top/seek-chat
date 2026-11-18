import 'package:material_ui/material_ui.dart';

/// 最小应用壳；聊天界面、设置与路由由界面票补齐。
class OpenChatApp extends StatelessWidget {
  const OpenChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Open Chat',
      home: Scaffold(
        body: Center(child: Text('Open Chat')),
      ),
    );
  }
}
