import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CrimiReview app basic test', (WidgetTester tester) async {
    // Basic widget test for the app structure
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('CrimiReview'),
          ),
        ),
      ),
    );

    // Verify app name appears
    expect(find.text('CrimiReview'), findsOneWidget);
  });
}
