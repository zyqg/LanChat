import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_chat/main.dart';

void main() {
  testWidgets('renders LAN chat home', (tester) async {
    await tester.pumpWidget(const LanChatApp());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
