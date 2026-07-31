import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/services/wikipedia_revision_service.dart';
import 'package:mesozoica/widgets/dino/dinosaur_article_drawer.dart';
import 'package:mesozoica/widgets/dino/dinosaur_wikipedia_view.dart';

void main() {
  test('wikipediaArticleUri encodes title spaces as underscores', () {
    expect(
      wikipediaArticleUri('Tyrannosaurus rex').toString(),
      'https://en.wikipedia.org/wiki/Tyrannosaurus_rex',
    );
  });

  test('wikipediaMobileArticleUri uses mobile host', () {
    expect(
      wikipediaMobileArticleUri('Velociraptor').toString(),
      'https://en.m.wikipedia.org/wiki/Velociraptor',
    );
  });

  test('wikipedia URIs include oldid permalink query', () {
    expect(
      wikipediaArticleUri('Tyrannosaurus', oldId: 12345).toString(),
      'https://en.wikipedia.org/w/index.php?title=Tyrannosaurus&oldid=12345',
    );
    expect(
      wikipediaMobileArticleUri('Tyrannosaurus', oldId: 12345).toString(),
      'https://en.m.wikipedia.org/w/index.php?title=Tyrannosaurus&oldid=12345',
    );
  });

  test('wikipediaAsOfLabel formats insert date', () {
    final label = DinosaurArticleDrawer.wikipediaAsOfLabel(
      DateTime.utc(2024, 6, 15),
    );
    expect(label, isNotNull);
    expect(label, contains('Wikipedia as of'));
    expect(label, contains('2024'));
  });

  test('wikipediaAsOfLabel is null without date', () {
    expect(DinosaurArticleDrawer.wikipediaAsOfLabel(null), isNull);
  });

  test('WikipediaRevisionService parses revid from action API', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/w/api.php');
      expect(request.url.queryParameters['rvdir'], 'older');
      expect(request.url.queryParameters['titles'], 'Tyrannosaurus');
      expect(request.headers['User-Agent'], contains('Mesozoica'));
      return http.Response(
        '''
{
  "query": {
    "pages": {
      "30467": {
        "pageid": 30467,
        "title": "Tyrannosaurus",
        "revisions": [{"revid": 987654, "timestamp": "2024-06-01T12:00:00Z"}]
      }
    }
  }
}
''',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = WikipediaRevisionService(httpClient: client);
    final revid = await service.revisionAsOf(
      title: 'Tyrannosaurus',
      asOf: DateTime.utc(2024, 7, 1),
    );
    expect(revid, 987654);
  });

  test('WikipediaRevisionService returns null for missing page', () async {
    final client = MockClient((request) async {
      return http.Response(
        '{"query":{"pages":{"-1":{"missing":true,"title":"NoSuchDino"}}}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = WikipediaRevisionService(httpClient: client);
    final revid = await service.revisionAsOf(
      title: 'NoSuchDino',
      asOf: DateTime.utc(2024, 7, 1),
    );
    expect(revid, isNull);
  });
}
