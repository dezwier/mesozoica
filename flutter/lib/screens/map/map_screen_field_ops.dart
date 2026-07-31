part of 'map_screen.dart';

/// Field-mode admin actions (scan/purge), site tap handling, filter sheet,
/// and transient banner messages for [MapScreen].
mixin _MapScreenFieldOpsMixin on State<MapScreen>, _MapScreenCameraMixin {
  String? _scanBannerMessage;
  Timer? _scanBannerTimer;

  void _disposeFieldOpsMixin() {
    _scanBannerTimer?.cancel();
  }

  void _showScanBanner(
    String message, {
    bool autoDismiss = true,
    Duration duration = const Duration(seconds: 4),
  }) {
    _scanBannerTimer?.cancel();
    setState(() => _scanBannerMessage = message);
    if (!autoDismiss) return;
    _scanBannerTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _scanBannerMessage = null);
    });
  }

  /// On-demand admin load of every field site currently in the viewport.
  Future<void> _loadSitesInViewport() async {
    if (!mounted) return;
    final mapData = context.read<map_data.MapController>();
    if (!mapData.showAllFieldSites) return;

    _showScanBanner('Loading sites in view…', autoDismiss: false);

    try {
      LatLngBounds? bounds;
      try {
        if (_mapboxReady) {
          bounds = await _mapboxCamera
              .visibleBounds()
              .timeout(const Duration(seconds: 2));
        }
      } catch (_) {
        // Fall through — null bounds → zoom-in prompt.
      }
      if (!mounted) return;
      if (!mapData.showAllFieldSites) {
        _clearScanBanner();
        return;
      }

      final fetchBounds = showAllFetchBounds(visibleBounds: bounds);
      if (fetchBounds == null) {
        mapData.setShowAllFieldSites(false);
        _showScanBanner('Zoom in to load sites in this view');
        return;
      }

      final result = await mapData
          .loadShowAllInBounds(fetchBounds)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      switch (result) {
        case map_data.ShowAllLoadResult.success:
          _showScanBanner(
            'Showing ${mapData.filteredGeoSites.length} field sites in view',
          );
        case map_data.ShowAllLoadResult.tooMany:
          final tooManyMessage = mapData.error ??
              'Too many sites in this view. Zoom in and try again.';
          mapData.setShowAllFieldSites(false);
          _showScanBanner(tooManyMessage);
        case map_data.ShowAllLoadResult.failed:
          final failMessage =
              mapData.error ?? 'Could not load sites in view (unknown error)';
          mapData.setShowAllFieldSites(false);
          _showScanBanner(
            failMessage,
            duration: const Duration(seconds: 10),
          );
        case map_data.ShowAllLoadResult.cancelled:
          if (!mapData.showAllFieldSites) {
            _clearScanBanner();
            return;
          }
          // Coalesced into a newer request — keep the loading banner only while
          // a fetch is still in flight. Otherwise the toggle looks wedged.
          if (!mapData.loading) {
            mapData.setShowAllFieldSites(false);
            _showScanBanner(
              mapData.error ??
                  'Could not load sites in view (request cancelled)',
              duration: const Duration(seconds: 8),
            );
          }
      }
    } on TimeoutException {
      if (!mounted) return;
      mapData.setShowAllFieldSites(false);
      _showScanBanner(
        'Timed out loading sites in view — try again.',
        duration: const Duration(seconds: 10),
      );
    } catch (error) {
      if (!mounted) return;
      mapData.setShowAllFieldSites(false);
      _showScanBanner(
        'Could not load sites in view: $error',
        duration: const Duration(seconds: 10),
      );
    }
  }

  void _clearScanBanner() {
    _scanBannerTimer?.cancel();
    if (!mounted) return;
    setState(() => _scanBannerMessage = null);
  }

  Future<void> _onScanFieldArea() async {
    if (!_mapboxReady) return;
    final center = await _mapboxCamera.currentCenter();
    if (center == null) {
      _showScanBanner('Could not read map center');
      return;
    }
    _showScanBanner('Field site scan queued…', autoDismiss: false);
    unawaited(_runAdminFieldScan(center));
  }

  Future<void> _runAdminFieldScan(LatLng center) async {
    final siteService = SiteService();
    try {
      final response = await context
          .read<FieldSessionCoordinator>()
          .scanAt(center);
      if (!mounted) return;
      if (response == null) {
        _showScanBanner('Could not queue field site scan');
        return;
      }

      final jobId = response.jobId;
      if (jobId == null) {
        _showScanBanner(
          response.accepted
              ? 'Field site scan queued'
              : 'Scan already running for this area',
        );
        return;
      }

      if (!response.accepted) {
        _showScanBanner(
          'Scan already running — waiting for result…',
          autoDismiss: false,
        );
      }

      final status = await siteService.waitForFieldEnsureJob(jobId);
      if (!mounted) return;

      if (status.isFailed) {
        _showScanBanner(
          status.errorMessage?.trim().isNotEmpty == true
              ? 'Scan failed: ${status.errorMessage}'
              : 'Field site scan failed',
        );
        return;
      }

      final written = status.generated ?? 0;
      final after = status.totalInRadius ?? 0;
      final found = (after - written).clamp(0, after);
      final radiusKm = status.radiusKm;
      final radiusLabel = radiusKm == radiusKm.roundToDouble()
          ? '${radiusKm.toInt()} km'
          : '${radiusKm.toStringAsFixed(1)} km';
      _showScanBanner('Found $found in $radiusLabel · wrote $written');
      context.read<map_data.MapController>().scheduleFieldPollAfterEnsure();
    } catch (_) {
      if (!mounted) return;
      _showScanBanner('Could not complete field site scan');
    } finally {
      siteService.dispose();
    }
  }

  Future<void> _onPurgeFieldData() async {
    final selection = await FieldDataPurgeDialog.confirm(context);
    if (selection == null || !mounted) return;

    _showScanBanner('Deleting field data…', autoDismiss: false);
    final service = SiteService();
    try {
      final result = await service.purgeAllFieldData(
        userSites: selection.userSites,
        userFossils: selection.userFossils,
        sites: selection.sites,
        fossils: selection.fossils,
        missionEvents: selection.missionEvents,
        missions: selection.missions,
      );
      if (!mounted) return;
      context.read<FieldDiscoveryCoordinator>().clearForUserChange();
      context.read<map_data.MapController>().load(force: true);
      context.read<SiteCatalogController>().load(force: true);
      context.read<FossilCatalogController>().load(force: true);
      unawaited(context.read<AerialMissionController>().refreshMissions());
      _showScanBanner(
        'Deleted ${result.userSitesDeleted} user sites · '
        '${result.userFossilsDeleted} user fossils · '
        '${result.sitesDeleted} sites · '
        '${result.fossilsDeleted} fossils · '
        '${result.missionEventsDeleted} mission events · '
        '${result.missionsDeleted} missions',
      );
    } on SiteServiceException catch (error) {
      if (!mounted) return;
      _showScanBanner(error.message);
    } catch (_) {
      if (!mounted) return;
      _showScanBanner('Could not delete field data');
    } finally {
      service.dispose();
    }
  }

  void _openFilterSheet(map_data.MapController mapData, bool isFieldMode) {
    SiteFilterSheet.show(
      context,
      initialFilters: mapData.filters.copyWith(filterByStatus: isFieldMode),
      showStatusSection: isFieldMode,
      showReconRoutesSection: isFieldMode,
      earliestDiscovery: earliestSiteDiscovery(mapData.geoSites),
      onApply: mapData.applyFilters,
    );
  }

  Future<void> _onSiteTap(SiteSummary site) async {
    final mapData = context.read<map_data.MapController>();
    // Keep selection after the card closes; only another tap replaces it.
    mapData.selectSite(site);
    final displayFuture = mapData.siteForDisplay(site);
    if (!_rotateMap) {
      unawaited(_panToSite(site));
    }
    final displaySite = await displayFuture;
    if (!mounted) return;
    await showSiteMapCardDialog(context, displaySite);
  }
}
