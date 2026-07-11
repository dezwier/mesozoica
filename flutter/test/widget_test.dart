import 'package:flutter_test/flutter_test.dart';

import 'package:mesozoica/main.dart';

void main() {
  testWidgets('Mesozoica app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MesozoicaApp());
    expect(find.text('Mesozoica — scaffold'), findsOneWidget);
  });
}
