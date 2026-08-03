import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';

/// Pick one of the user's discovered field sites for a disguise cover.
Future<int?> showDisguiseSitePicker(BuildContext context) async {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _DisguiseSitePickerSheet(),
  );
}

class _DisguiseSitePickerSheet extends StatefulWidget {
  const _DisguiseSitePickerSheet();

  @override
  State<_DisguiseSitePickerSheet> createState() =>
      _DisguiseSitePickerSheetState();
}

class _DisguiseSitePickerSheetState extends State<_DisguiseSitePickerSheet> {
  final SiteService _service = SiteService();
  bool _loading = true;
  String? _error;
  List<SiteSummary> _sites = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _service.fetchSites(
        limit: 100,
        sort: 'discovered_at_desc',
        dataSource: CatalogDataSource.field,
      );
      if (!mounted) return;
      setState(() {
        _sites = response.items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Cover a discovered site',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_sites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Discover a field site first, then you can disguise it.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _sites.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final site = _sites[index];
        final subtitle = [
          if (site.status != null) site.status!,
          if (site.siteTypePeriod != null) site.siteTypePeriod!,
        ].join(' · ');
        return ListTile(
          title: Text(site.displayTitle),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          onTap: () => Navigator.of(context).pop(site.siteId),
        );
      },
    );
  }
}
