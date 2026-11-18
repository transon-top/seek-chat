import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/app.dart';

void main() {
  testWidgets('renders the app shell', (tester) async {
    await tester.pumpWidget(const OpenChatApp());

    expect(find.text('Open Chat'), findsOneWidget);
  });
}
