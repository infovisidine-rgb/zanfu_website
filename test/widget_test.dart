import 'package:flutter_test/flutter_test.dart';
import 'package:ar_project/main.dart';

void main() {
  testWidgets('Check if product page displays', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the product name is displayed
    expect(find.text('Select Food Items'), findsOneWidget);
  });
}
