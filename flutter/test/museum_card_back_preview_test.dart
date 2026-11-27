import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/fossil.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/theme/mesozoica_theme.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_back.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_front.dart';
import 'package:mesozoica/widgets/cards/fossil_card_back.dart';
import 'package:mesozoica/widgets/cards/site_card_back.dart';
import 'package:mesozoica/widgets/cards/tool_card_back.dart';

const _dinosaur = DinosaurSummary(
  id: 15,
  name: 'Carcharodontosaurus',
  wikipediaTitle: 'Carcharodontosaurus',
  birth: 100,
  death: 94,
  period: 'Late Cretaceous',
  dietType: 'carnivore',
  length: '12 – 12.5 m',
  mass: '5 – 7 t',
  cladogram: {
    'clade': 'Dinosauria',
    'clade_2': 'Saurischia',
    'clade_3': 'Theropoda',
    'family': 'Carcharodontosauridae',
    'subfamily': 'Carcharodontosaurinae',
    'genus': 'Carcharodontosaurus',
  },
);

const _fossil = FossilSummary(
  id: 100001,
  dinosaurId: 1,
  dinosaurName: 'Tyrannosaurus',
  identifiedName: 'Tyrannosaurus rex',
  geologicalFormation: 'Hell Creek Formation',
  minAgeMa: 66,
  maxAgeMa: 68,
  earlyInterval: 'Maastrichtian',
  lithdescript: 'sandstone',
  llmImpCategory: 'body',
  llmImpSubcategory: 'teeth',
  llmImpPreservationQuality: 'good',
  llmImpCompleteness: 'isolated_element',
  siteId: 50001,
);

const _site = SiteSummary(
  siteId: 50001,
  latitude: 46.88,
  longitude: -110.36,
  rockType: 'sandstone',
  formation: 'Hell Creek',
  minAgeMa: 66,
  maxAgeMa: 68,
  siteTypePeriod: 'cretaceous',
  siteTypeRockType: 'sandstone',
);

const _tool = ToolSummary(
  id: 1,
  name: 'Aerial Recon',
  category: '1 site_discovery',
  scientificTool: 'helicopter',
  description: 'Scout loop',
  rarity: 3,
  action: 'Deploy',
  level: 1,
  baseParams: {
    'flight_speed_kmh': 80,
    'altitude_m': 120,
    'duration_minutes': 15,
    'detect_chance': 0.4,
  },
  remainingDurationS: 900,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('museum card backs paint in the dark theme', (tester) async {
    await tester.runAsync(_loadMuseumFonts);
    await _paint(
      tester,
      const DinosaurCardFront(dinosaur: _dinosaur, titleFontSize: 28),
      'museum-dinosaur-front',
    );
    await _paint(
      tester,
      const DinosaurCardBack(dinosaur: _dinosaur),
      'museum-dinosaur-back',
    );
    expect(find.text('Carcharodontosaurus'), findsWidgets);
    expect(find.text('ATTRIBUTES'), findsOneWidget);
    expect(find.text('CLADOGRAM'), findsOneWidget);

    await _paint(
      tester,
      const FossilCardBack(fossil: _fossil),
      'museum-fossil-back',
    );
    expect(find.text('ATTRIBUTES'), findsOneWidget);
    expect(find.text('LINKED CARDS'), findsOneWidget);

    await _paint(
      tester,
      const SiteCardBack(site: _site, mapTileLayerBuilder: _emptyTiles),
      'museum-site-back',
    );
    expect(find.text('SITE DIMENSIONS'), findsOneWidget);
    expect(find.text('FOSSILS'), findsOneWidget);

    await _paint(
      tester,
      ToolCardBack(tool: _tool, onAction: () {}),
      'museum-tool-back',
    );
    expect(find.text('PARAMETERS'), findsOneWidget);
    expect(find.text('Deploy'), findsOneWidget);
  });
}

Widget _emptyTiles() => const SizedBox.shrink();

Future<void> _paint(WidgetTester tester, Widget card, String name) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MesozoicaTheme.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A120C),
        body: Center(
          child: RepaintBoundary(
            key: const Key('museum-preview'),
            child: SizedBox(width: 390, child: card),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump();

  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('museum-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
  });
}

Future<void> _loadMuseumFonts() async {
  final ramillas = FontLoader('tt_ramilas');
  for (final asset in const [
    'assets/fonts/tt_ramillas/TT Ramillas Trial Regular.ttf',
    'assets/fonts/tt_ramillas/TT Ramillas Trial Medium.ttf',
    'assets/fonts/tt_ramillas/TT Ramillas Trial Bold.ttf',
    'assets/fonts/tt_ramillas/TT Ramillas Trial Italic.ttf',
  ]) {
    ramillas.addFont(rootBundle.load(asset));
  }
  await ramillas.load();

  final icons = File(
    '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icons.existsSync()) return;
  final bytes = await icons.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}
