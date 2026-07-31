import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/owned_occurrence_thumb.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/theme/dino_card_theme.dart';
import 'package:mesozoica/utils/curated_image_url.dart';
import 'package:mesozoica/widgets/common/catalog_album_tile.dart';

void main() {
  test('DinosaurSummary parses owned_occurrences', () {
    final dino = DinosaurSummary.fromJson({
      'id': 1,
      'name': 'Tyrannosaurus',
      'wikipedia_title': 'Tyrannosaurus',
      'cladogram': {},
      'status': 'modelled',
      'owned_occurrences': [
        {
          'id': 10,
          'version': 'Original',
          'main_image_url':
              'https://example.com/media/dinosaurs/Tyrannosaurus.webp',
          'created_at': '2026-07-01T00:00:00Z',
        },
        {
          'id': 11,
          'version': 'Summer 26',
          'main_image_url':
              'https://example.com/media/dinosaurs/Tyrannosaurus.webp',
        },
      ],
    });

    expect(dino.isCatalogOwned, isTrue);
    expect(dino.ownedOccurrences, hasLength(2));
    final occurrence = dino.occurrenceFromThumb(dino.ownedOccurrences[1]);
    expect(occurrence.id, 11);
    expect(occurrence.version, 'Summer 26');
    expect(occurrence.dinosaurTypeId, 1);
    expect(occurrence.isInventoryOccurrence, isTrue);
  });

  test('ToolSummary parses owned_occurrences', () {
    final tool = ToolSummary.fromJson({
      'id': 2,
      'name': 'Orbit Survey',
      'category': '1 site_discovery',
      'scientific_tool': 'satellite',
      'description': 'x',
      'rarity': 1,
      'level': 1,
      'owned_occurrences': [
        {
          'id': 20,
          'version': 'Original',
          'main_image_url': 'https://example.com/media/tools/Orbit%20Survey.png',
          'spawn_date': '2026-07-01T00:00:00Z',
        },
      ],
    });

    expect(tool.isCatalogOwned, isTrue);
    expect(tool.ownedOccurrences.single.id, 20);
    final occurrence = tool.occurrenceFromThumb(tool.ownedOccurrences.single);
    expect(occurrence.id, 20);
    expect(occurrence.spawnDate, isNotNull);
    expect(occurrence.isToolInstance, isTrue);
  });

  testWidgets('unowned catalog tile is not tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: CatalogAlbumTile(
                imageUrl: null,
                owned: false,
                ownedOccurrences: const [],
                placeholderAsset: DinoCardTheme.frontPlaceholderAsset,
                isCuratedUrl: isCuratedDinosaurImageUrl,
                onOwnedTap: (_) => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CatalogAlbumTile));
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('owned catalog tile tap uses visible occurrence', (tester) async {
    OwnedOccurrenceThumb? tapped;
    const first = OwnedOccurrenceThumb(id: 1, version: 'Original');
    const second = OwnedOccurrenceThumb(id: 2, version: 'Summer 26');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: CatalogAlbumTile(
                imageUrl: null,
                owned: true,
                ownedOccurrences: const [first, second],
                placeholderAsset: DinoCardTheme.frontPlaceholderAsset,
                isCuratedUrl: isCuratedDinosaurImageUrl,
                onOwnedTap: (thumb) => tapped = thumb,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CatalogAlbumTile));
    await tester.pump();
    expect(tapped?.id, 1);

    await tester.drag(find.byType(PageView), const Offset(-80, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CatalogAlbumTile));
    await tester.pump();
    expect(tapped?.id, 2);
  });
}
