import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/curated_image_url.dart';

void main() {
  group('albumImageUrlFromCurated', () {
    test('maps versioned full URL to album WebP', () {
      expect(
        albumImageUrlFromCurated(
          'https://mesozoica-production.up.railway.app/media/dinosaurs/Original/Tyrannosaurus.png?v=abc123',
        ),
        'https://mesozoica-production.up.railway.app/media/dinosaurs/Original/album/Tyrannosaurus.webp?v=abc123',
      );
    });

    test('preserves encoded version folder spaces', () {
      final result = albumImageUrlFromCurated(
        'https://example.com/media/tools/Summer%2026/Orbit%20Survey.png',
      );
      expect(result, isNotNull);
      expect(result!, contains('/Summer%2026/album/'));
      expect(result, endsWith('Orbit%20Survey.webp'));
    });

    test('returns null for flat legacy media paths', () {
      expect(
        albumImageUrlFromCurated(
          'https://example.com/media/dinosaurs/Tyrannosaurus.png',
        ),
        isNull,
      );
    });

    test('returns null for null/empty', () {
      expect(albumImageUrlFromCurated(null), isNull);
      expect(albumImageUrlFromCurated(''), isNull);
      expect(albumImageUrlFromCurated('   '), isNull);
    });

    test('passes through existing album URLs', () {
      const url =
          'https://example.com/media/fossils/Original/album/100001.webp?v=1';
      expect(albumImageUrlFromCurated(url), url);
    });
  });
}
