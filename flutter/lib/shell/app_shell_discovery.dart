part of 'app_shell.dart';

/// Discovery celebration / site-discovered side effects for [AppShell].
mixin _AppShellDiscoveryMixin on State<AppShell> {
  int _lastToolSessionsFetchGeneration = 0;
  final Set<int> _knownAerialDiscoveredSiteIds = {};
  Timer? _discoveryRefreshTimer;
  bool _celebrationShowing = false;
  bool _appInForeground = true;

  /// Serializes per-discovery profile refreshes so each site's XP is stashed
  /// separately (avoids one merged discover_site award for N background finds).
  Future<void> _discoveryXpChain = Future<void>.value();

  /// Tracks celebration queue length so we only side-effect on newly enqueued
  /// discoveries (not when one is consumed).
  int _lastDiscoveryQueueSeen = 0;
  final Set<int> _handledDocumentationCelebrationSiteIds = {};

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
    // XP is announced per discovery via [_enqueueDiscoveryXpAnnounce]; keep
    // this path for catalog/inbox only.
    final auth = context.read<AuthController>();
    unawaited(auth.refreshProfile(announceXp: false));
    final userId = auth.currentUser?.id;
    if (userId != null) {
      context.read<NotificationController>().refreshInBackground(
        authenticatedUserId: userId,
      );
    }
  }

  /// Stash this discovery's XP before another discover can merge the delta.
  void _enqueueDiscoveryXpAnnounce() {
    _discoveryXpChain = _discoveryXpChain.then((_) async {
      if (!mounted) return;
      await context.read<AuthController>().refreshProfile(announceXp: true);
    });
  }

  void _onDiscoveryChanged() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final queue = discovery.celebrationQueue;
    final grew = queue.length > _lastDiscoveryQueueSeen;
    if (grew) {
      for (var i = _lastDiscoveryQueueSeen; i < queue.length; i++) {
        final newest = queue[i];
        // Apply discover response immediately so timeline / first-discovery
        // flags show on the card back without waiting for the debounced refetch.
        context.read<MapController>().upsertSite(newest.site);
        context.read<SiteCatalogController>().upsertSite(newest.site);

        // Announce XP for this discovery now (serialized) so multiple
        // background finds each stash their own celebration awards.
        _enqueueDiscoveryXpAnnounce();
        _scheduleDiscoveryRefresh(siteId: newest.site.siteId);
      }
    }
    _lastDiscoveryQueueSeen = queue.length;

    // Only start UI when the queue grew (not when a celebration was consumed).
    if (!grew || !_appInForeground) return;
    _showPendingCelebrationIfAny();
  }

  void _onExplorationChanged() {
    if (!mounted) return;
    final exploration = context.read<SiteExplorationController>();
    final queue = exploration.documentationCelebrationQueue;
    for (final site in queue) {
      context.read<MapController>().upsertSite(site);
      context.read<SiteCatalogController>().upsertSite(site);
      _scheduleDiscoveryRefresh(siteId: site.siteId);
    }
    if (!_appInForeground || queue.isEmpty) return;
    _showPendingCelebrationIfAny();
  }

  void _showPendingCelebrationIfAny() {
    if (!mounted || _celebrationShowing) return;
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
    if (!mounted || _celebrationShowing) return;
    final exploration = context.read<SiteExplorationController>();
    var pending = exploration.pendingDocumentationCelebration;
    while (pending != null &&
        _handledDocumentationCelebrationSiteIds.contains(pending.siteId)) {
      exploration.consumeDocumentationCelebration();
      pending = exploration.pendingDocumentationCelebration;
    }
    if (pending != null) {
      exploration.consumeDocumentationCelebration();
      unawaited(_showDocumentationCelebration(site: pending));
      return;
    }
  }

  Future<void> _showCelebration({
    FieldDiscoverResponse? discover,
    SiteSummary? site,
    int? siteId,
    int? notificationId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    final resolvedSite = discover?.site ?? site;
    if (resolvedSite == null && siteId == null) return;
    _celebrationShowing = true;
    try {
      // Wait for surface fossils when a survey job is pending so locate-in-situ
      // XP is awarded before the site discovery plaque claims it.
      await _resolveSurfaceFossils(discover);
      if (!mounted) return;
      // Await any in-flight per-discovery XP announce, then pick up locate XP.
      await _discoveryXpChain;
      if (!mounted) return;
      await context.read<AuthController>().refreshProfile(announceXp: true);
      if (!mounted) return;
      await showSiteDiscoveryCelebration(
        context,
        site: resolvedSite,
        siteId: siteId,
        notificationId: notificationId ?? discover?.celebration?.notificationId,
        discovery: discover,
      );
    } finally {
      _celebrationShowing = false;
      // Chain the next discovery or documentation celebration.
      if (mounted && _appInForeground) {
        _showPendingCelebrationIfAny();
      }
    }
  }

  Future<void> _showDocumentationCelebration({
    SiteSummary? site,
    int? siteId,
    int? notificationId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    if (site == null && siteId == null) return;
    final resolvedSiteId = site?.siteId ?? siteId!;
    if (!_handledDocumentationCelebrationSiteIds.add(resolvedSiteId)) return;
    _celebrationShowing = true;
    try {
      if (CardDetailSheet.isOpen) {
        CardDetailSheet.dismissMatching(
          CardDetailIdentity.site(resolvedSiteId),
        );
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await context.read<AuthController>().refreshProfile(announceXp: true);
      if (!mounted) return;
      await showSiteDocumentationCelebration(
        context,
        site: site,
        siteId: siteId,
        notificationId:
            notificationId ??
            context
                .read<SiteExplorationController>()
                .takeDocumentationNotificationId(resolvedSiteId),
      );
    } finally {
      _celebrationShowing = false;
      if (mounted && _appInForeground) {
        _showPendingCelebrationIfAny();
      }
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
