import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/features/legal/legal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('privacy policy screen renders heading from asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentScreen(
          title: 'Privacy policy',
          assetPath: kPrivacyPolicyAsset,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.textContaining('Mesozoica Privacy Policy'), findsWidgets);
    expect(find.textContaining('contact@mesozoica.app'), findsWidgets);
  });
}
