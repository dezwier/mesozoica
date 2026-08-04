part of 'app_shell.dart';

/// Discovery celebration / site-discovered side effects for [AppShell].
mixin _AppShellDiscoveryMixin on State<AppShell> {
  int _lastToolSessionsFetchGeneration = 0;
  final Set<int> _knownAerialDiscoveredSiteIds = {};
  Timer? _discoveryRefreshTimer;
  bool _celebrationShowing = false;
  bool _appInForeground = true;

  void _ingestAerialDiscoveredSites(Iterable<int> siteIds) {
    final newIds = <int>[];
    for (final id in siteIds) {
      if (_knownAerialDiscoveredSiteIds.add(id)) {
        newIds.add(id);
      }
    }
    if (newIds.isEmpty) return;
    for (final id in newIds) {
      unawaited(_upsertDiscoveredSite(id));
    }
    _scheduleDiscoverySideEffects(reloadSiteCatalogs: false);
  }

  /// Coalesce rapid discovery signals (many aerial finds / polls) into one reload.
  void _scheduleDiscoveryRefresh({int? siteId}) {
    if (siteId != null) {
      _knownAerialDiscoveredSiteIds.add(siteId);
      unawaited(_upsertDiscoveredSite(siteId));
    }
    _scheduleDiscoverySideEffects(reloadSiteCatalogs: true);
  }

  Future<void> _upsertDiscoveredSite(int siteId) async {
    if (!mounted) return;
    final service = SiteService();
    try {
      final site = await service.fetchSiteById(
        siteId,
        dataSource: CatalogDataSource.field,
      );
      if (!mounted) return;
      context.read<MapController>().upsertSite(site);
      context.read<SiteCatalogController>().upsertSite(site);
    } catch (_) {
      // Debounced catalog reload (when scheduled) may still pick it up.
    } finally {
      service.dispose();
    }
  }

  void _scheduleDiscoverySideEffects({required bool reloadSiteCatalogs}) {
    _discoveryRefreshTimer?.cancel();
    _discoveryRefreshTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _refreshAfterSiteDiscovered(reloadSiteCatalogs: reloadSiteCatalogs);
    });
  }

  void _refreshAfterSiteDiscovered({bool reloadSiteCatalogs = true}) {
    if (!mounted) return;
    if (reloadSiteCatalogs) {
      context.read<MapController>().load(force: true);
      context.read<SiteCatalogController>().load(force: true);
    }
    unawaited(context.read<FossilCatalogController>().load(force: true));
    final auth = context.read<AuthController>();
    unawaited(auth.refreshProfile(announceXp: true));
    final userId = auth.currentUser?.id;
    if (userId != null) {
      context
          .read<NotificationController>()
          .refreshInBackground(authenticatedUserId: userId);
    }
  }

  void _onDiscoveryChanged() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final pending = discovery.pendingCelebration;
    if (pending == null) return;

    // Apply discover response immediately so timeline / first-discovery flags
    // show on the card back without waiting for the debounced refetch.
    context.read<MapController>().upsertSite(pending.site);
    context.read<SiteCatalogController>().upsertSite(pending.site);
    unawaited(context.read<AuthController>().refreshProfile(announceXp: true));

    // Always refresh map/catalog/inbox; push already covers background UX.
    _scheduleDiscoveryRefresh(siteId: pending.site.siteId);

    // Defer the in-app celebration dialog until the app is foregrounded.
    if (!_appInForeground) return;
    _showPendingCelebrationIfAny();
  }

  void _onExplorationChanged() {
    if (!mounted) return;
    final exploration = context.read<SiteExplorationController>();
    final pending = exploration.pendingDocumentationCelebration;
    if (pending == null) return;

    // Apply sync payload immediately so XP / timeline / status badge update
    // before the celebration (and without waiting on the debounced refetch).
    context.read<MapController>().upsertSite(pending);
    context.read<SiteCatalogController>().upsertSite(pending);
    unawaited(context.read<AuthController>().refreshProfile(announceXp: true));
    _scheduleDiscoveryRefresh(siteId: pending.siteId);

    if (!_appInForeground) return;
    _showPendingDocumentationCelebrationIfAny();
  }

  void _showPendingCelebrationIfAny() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final pending = discovery.pendingCelebration;
    if (pending != null) {
      discovery.consumeCelebration();
      unawaited(_showCelebration(discover: pending));
      return;
    }
    _showPendingDocumentationCelebrationIfAny();
  }

  void _showPendingDocumentationCelebrationIfAny() {
    if (!mounted) return;
    final exploration = context.read<SiteExplorationController>();
    final pending = exploration.pendingDocumentationCelebration;
    if (pending == null) return;
    exploration.consumeDocumentationCelebration();
    unawaited(_showDocumentationCelebration(site: pending));
  }

  Future<void> _showCelebration({
    FieldDiscoverResponse? discover,
    SiteSummary? site,
    int? siteId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    final resolvedSite = discover?.site ?? site;
    if (resolvedSite == null && siteId == null) return;
    _celebrationShowing = true;
    try {
      await showSiteDiscoveryCelebration(
        context,
        site: resolvedSite,
        siteId: siteId,
      );
      if (!mounted) return;
      final fossils = await _resolveSurfaceFossils(discover);
      if (!mounted || fossils.isEmpty) return;
      await showFossilDiscoveryCelebrations(context, fossils: fossils);
      if (!mounted) return;
      unawaited(context.read<FossilCatalogController>().load(force: true));
    } finally {
      _celebrationShowing = false;
      // Chain documentation celebration if it arrived while discovery was up.
      if (mounted && _appInForeground) {
        _showPendingDocumentationCelebrationIfAny();
      }
    }
  }

  Future<void> _showDocumentationCelebration({
    SiteSummary? site,
    int? siteId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    if (site == null && siteId == null) return;
    _celebrationShowing = true;
    try {
      // Close any open site card so celebration isn't stacked on it
      // (same pattern as identification).
      if (CardDetailSheet.isOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await showSiteDocumentationCelebration(
        context,
        site: site,
        siteId: siteId,
      );
    } finally {
      _celebrationShowing = false;
    }
  }

  Future<List<FossilSummary>> _resolveSurfaceFossils(
    FieldDiscoverResponse? discover,
  ) async {
    if (discover == null) return const [];
    if (discover.fossilsReady) {
      return discover.surfaceFossils;
    }
    final jobId = discover.jobId;
    if (jobId == null) return discover.surfaceFossils;
    final location = context.read<LocationService>().currentLocation;
    if (location == null) return const [];
    final service = SiteService();
    try {
      final job = await service.waitForFieldSurveyJob(jobId);
      if (!job.isDone || !mounted) return const [];
      final refreshed = await service.discoverSite(
        siteId: discover.site.siteId,
        lat: location.latitude,
        lon: location.longitude,
      );
      return refreshed.surfaceFossils;
    } catch (_) {
      return const [];
    } finally {
      service.dispose();
    }
  }
}
