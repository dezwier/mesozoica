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
