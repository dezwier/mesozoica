import 'package:flutter_test/flutter_test.dart';

import 'package:mesozoica/main.dart';

void main() {
  testWidgets('Mesozoica app builds with four navigation tabs', (tester) async {
    await tester.pumpWidget(const MesozoicaApp());
    await tester.pump();

    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Dino'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Dinosaur Catalog'), findsOneWidget);
  });
}
