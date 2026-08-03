import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_record_thumb.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Horizontal scroll of small square fossil thumbs on the site card back.
class SiteCardFossils extends StatefulWidget {
  const SiteCardFossils({
    super.key,
    required this.siteId,
    this.siteService,
    this.thumbSize = 56,
  });

  final int siteId;
  final SiteService? siteService;
  final double thumbSize;

  @override
  State<SiteCardFossils> createState() => _SiteCardFossilsState();
}

class _SiteCardFossilsState extends State<SiteCardFossils> {
  late final SiteService _service;
  late final bool _ownsService;
  Future<List<SiteFossilThumb>>? _fossilsFuture;
  int? _loadedForSiteId;
  bool? _loadedIncludeHidden;

  static const _gap = 6.0;

  Widget _buildThumb({
    required BuildContext context,
    required SiteFossilThumb fossil,
    required double thumbSize,
  }) {
    final thumb = SizedBox(
      width: thumbSize,
      height: thumbSize,
      child: CardRecordThumb(
        image: FossilCardImage(imageUrl: fossil.mainImageUrl),
        label: fossil.displayLabel,
        onTap: () => showFossilCardDialog(
          context,
          fossilId: fossil.id,
        ),
      ),
    );
    if (!fossil.isHidden) return thumb;
    return Opacity(opacity: 0.5, child: thumb);
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
  }

  void _ensureLoaded({required bool includeHidden}) {
    if (_loadedForSiteId == widget.siteId &&
        _loadedIncludeHidden == includeHidden &&
        _fossilsFuture != null) {
      return;
    }
    _loadedForSiteId = widget.siteId;
    _loadedIncludeHidden = includeHidden;
    _fossilsFuture = _loadFossils(includeHidden: includeHidden);
  }

  @override
  void didUpdateWidget(covariant SiteCardFossils oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _loadedForSiteId = null;
    }
  }

  Future<List<SiteFossilThumb>> _loadFossils({
    required bool includeHidden,
  }) async {
    return _service.fetchFossilsForSite(
      widget.siteId,
      includeHidden: includeHidden,
    );
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    var includeHidden = false;
    try {
      includeHidden = context.watch<AuthController>().showAdminUi;
    } on ProviderNotFoundException {
      // Widget tests / previews without AuthController.
    }
    _ensureLoaded(includeHidden: includeHidden);

    return FutureBuilder<List<SiteFossilThumb>>(
      future: _fossilsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load site record',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          );
        }

        final fossils = snapshot.data ?? const <SiteFossilThumb>[];
        if (fossils.isEmpty) {
          return Center(
            child: Text(
              'No fossil occurrences',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          );
        }

        final thumbSize = widget.thumbSize;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: fossils.length,
          separatorBuilder: (context, index) => const SizedBox(width: _gap),
          itemBuilder: (context, index) {
            return _buildThumb(
              context: context,
              fossil: fossils[index],
              thumbSize: thumbSize,
            );
          },
        );
      },
    );
  }
}
