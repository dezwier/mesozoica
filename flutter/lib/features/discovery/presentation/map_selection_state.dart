import '../../../models/site.dart';

/// Selection and deferred camera-focus state, independent of map loading.
class MapSelectionState {
  SiteSummary? selectedSite;
  SiteSummary? pendingFocusSite;

  bool select(SiteSummary site, {bool requestFocus = false}) {
    final changed =
        selectedSite != site || (requestFocus && pendingFocusSite != site);
    selectedSite = site;
    if (requestFocus) pendingFocusSite = site;
    return changed;
  }

  bool clear() {
    if (selectedSite == null) return false;
    selectedSite = null;
    return true;
  }

  SiteSummary? takePendingFocusSite() {
    final site = pendingFocusSite;
    pendingFocusSite = null;
    return site;
  }

  void replaceIfSelected(SiteSummary site) {
    if (selectedSite?.siteId == site.siteId) selectedSite = site;
    if (pendingFocusSite?.siteId == site.siteId) pendingFocusSite = site;
  }
}
