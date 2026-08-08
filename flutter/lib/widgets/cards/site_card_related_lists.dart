import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_record_thumb.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Horizontal scroll of fossil thumbs on the site card back, centralized and with custom ratio.
class SiteCardFossils extends StatefulWidget {
  const SiteCardFossils({
    super.key,
    required this.siteId,
    this.siteService,
    this.thumbSize = 56,
    this.tappable = true,
    this.isOpen = true,
    this.use2Rows = false,
  });

  final int siteId;
  final SiteService? siteService;
  final double thumbSize;
  final bool tappable;
  final bool isOpen;
  final bool use2Rows;

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
    required double aspectRatio,
  }) {
    final thumb = SizedBox(
      width: thumbSize * aspectRatio,
      height: thumbSize,
      child: CardRecordThumb(
        image: FossilCardImage(imageUrl: fossil.mainImageUrl),
        label: fossil.displayLabel,
        onTap: widget.tappable ? () => showFossilCardDialog(context, fossilId: fossil.id) : null,
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_searching,
                    size: 18,
                    color: cardTheme.cardTextMuted.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'No fossils located yet',
                      textAlign: TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cardTheme
                          .bodyStyle(fontSize: 13.5)
                          .copyWith(
                            color: cardTheme.cardTextMuted,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!widget.use2Rows) {
          // Render original horizontal scrollable list of square thumbs
          final thumbSize = widget.thumbSize;
          final aspectRatio = 1.0;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: fossils.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: EdgeInsets.only(right: i < fossils.length - 1 ? _gap : 0),
                child: _buildThumb(
                  context: context,
                  fossil: fossils[i],
                  thumbSize: thumbSize,
                  aspectRatio: aspectRatio,
                ),
              );
            },
          );
        }

        if (!widget.isOpen) {
          // Closed state when there are fossils
          final count = fossils.length;
          final word = count == 1 ? 'Fossil' : 'Fossils';
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.explore,
                    size: 18,
                    color: cardTheme.cardAccent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$count $word Discovered',
                      textAlign: TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cardTheme
                          .bodyStyle(fontSize: 13.5)
                          .copyWith(
                            color: cardTheme.cardTextPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Open state: do 2 rows with cards (Grid / Column of Rows)
        final thumbSize = widget.thumbSize;
        final aspectRatio = 3 / 4;

        final firstRow = <Widget>[];
        final secondRow = <Widget>[];

        for (var i = 0; i < fossils.length; i++) {
          final thumb = _buildThumb(
            context: context,
            fossil: fossils[i],
            thumbSize: thumbSize,
            aspectRatio: aspectRatio,
          );
          if (i % 2 == 0) {
            firstRow.add(thumb);
          } else {
            secondRow.add(thumb);
          }
        }

        Widget rowContent(List<Widget> rowItems) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) const SizedBox(width: _gap),
                rowItems[j],
              ],
            ],
          );
        }

        final content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            rowContent(firstRow),
            if (secondRow.isNotEmpty) ...[
              const SizedBox(height: _gap),
              rowContent(secondRow),
            ],
          ],
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Center(child: content),
        );
      },
    );
  }
}
