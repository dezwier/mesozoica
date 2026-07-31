bool isCuratedDinosaurImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return false;
  }
  return url.contains('/media/dinosaurs/');
}

bool isCuratedFossilImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return false;
  }
  return url.contains('/media/fossils/');
}

bool isCuratedToolImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return false;
  }
  return url.contains('/media/tools/');
}

bool isCuratedSiteTypeImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return false;
  }
  return url.contains('/media/site-types/');
}

/// Derive the album-grid WebP URL from a full curated card URL.
///
/// `.../Original/Name.png?v=…` → `.../Original/album/Name.webp?v=…`
///
/// Returns null when [url] is missing or not a versioned curated path.
String? albumImageUrlFromCurated(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;

  final segments = uri.pathSegments;
  // Expect …/media/<kind>/<version>/<file>
  if (segments.length < 4) return null;
  final fileName = segments.last;
  final versionOrAlbum = segments[segments.length - 2];
  if (versionOrAlbum == 'album') {
    // Already an album thumb URL.
    return trimmed;
  }
  if (!fileName.contains('.')) return null;

  final stem = fileName.substring(0, fileName.lastIndexOf('.'));
  if (stem.isEmpty) return null;

  final albumSegments = <String>[
    ...segments.sublist(0, segments.length - 1),
    'album',
    '$stem.webp',
  ];
  return uri.replace(pathSegments: albumSegments).toString();
}
