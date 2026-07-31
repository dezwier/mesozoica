import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up the Wikipedia revision id current as of [asOf].
class WikipediaRevisionService {
  WikipediaRevisionService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _userAgent =
      'Mesozoica/1.0 (mobile app; dinosaur catalog; contact@mesozoica.app)';

  /// Returns the latest `revid` at or before [asOf], or `null` if none.
  Future<int?> revisionAsOf({
    required String title,
    required DateTime asOf,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    final utc = asOf.toUtc();
    final stamp =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}Z';

    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'titles': trimmed,
      'redirects': '1',
      'prop': 'revisions',
      'rvprop': 'ids|timestamp',
      'rvlimit': '1',
      'rvstart': stamp,
      'rvdir': 'older',
      'origin': '*',
    });

    final response = await _http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final query = decoded['query'];
    if (query is! Map<String, dynamic>) return null;
    final pages = query['pages'];
    if (pages is! Map) return null;
    if (pages.isEmpty) return null;

    final page = pages.values.first;
    if (page is! Map) return null;
    if (page.containsKey('missing')) return null;
    final revisions = page['revisions'];
    if (revisions is! List || revisions.isEmpty) return null;
    final first = revisions.first;
    if (first is! Map) return null;
    final revid = first['revid'];
    if (revid is int) return revid;
    if (revid is num) return revid.toInt();
    return null;
  }
}
