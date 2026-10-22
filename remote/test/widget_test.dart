import 'package:flutter_test/flutter_test.dart';
import 'package:noctra_remote/main.dart';

void main() {
  testWidgets('NoctraRemoteApp mounts cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const NoctraRemoteApp());
    expect(find.text('Noctra Remote'), findsNothing); // Title is in MaterialApp
  });
}
