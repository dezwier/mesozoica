import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_back_body.dart';
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
    this.tappable = true,
    this.isOpen = true,
    this.use2Rows = false,
    this.sectionTitle,
    this.hideWhenEmpty = false,
    this.sectionBodyHeight = 88,
  });

  final int siteId;
  final SiteService? siteService;
  final double thumbSize;
  final bool tappable;
  final bool isOpen;
  final bool use2Rows;

  /// When set, wraps thumbs in a [CardBackSection] with this tab title.
  final String? sectionTitle;

  /// When true, renders nothing while loading or if the site has no fossils.
  final bool hideWhenEmpty;

  final double sectionBodyHeight;

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
        onTap: widget.tappable
            ? () => showFossilCardDialog(context, fossilId: fossil.id)
            : null,
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
          if (widget.hideWhenEmpty) return const SizedBox.shrink();
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          if (widget.hideWhenEmpty) return const SizedBox.shrink();
          return Center(
            child: Text(
              'Could not load site record',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10).copyWith(
                fontFamily: DinoCardTheme.titleFontFamily,
              ),
            ),
          );
        }

        final fossils = snapshot.data ?? const <SiteFossilThumb>[];
        if (fossils.isEmpty) {
          if (widget.hideWhenEmpty) return const SizedBox.shrink();
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
                            fontFamily: DinoCardTheme.titleFontFamily,
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

        late final Widget body;
        if (!widget.use2Rows) {
          final thumbSize = widget.thumbSize;
          body = ListView.separated(
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
                aspectRatio: 1.0,
              );
            },
          );
        } else if (!widget.isOpen) {
          final count = fossils.length;
          final word = count == 1 ? 'Fossil' : 'Fossils';
          body = Center(
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
                            fontFamily: DinoCardTheme.titleFontFamily,
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
        } else {
          final thumbSize = widget.thumbSize;
          const aspectRatio = 3 / 4;
          final count = fossils.length;
          final use2RowsGrid = count > 6;

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

          late final Widget content;
          if (!use2RowsGrid) {
            content = rowContent([
              for (final f in fossils)
                _buildThumb(
                  context: context,
                  fossil: f,
                  thumbSize: thumbSize,
                  aspectRatio: aspectRatio,
                ),
            ]);
          } else {
            final firstRow = <Widget>[];
            final secondRow = <Widget>[];
            for (var i = 0; i < count; i++) {
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
            content = Column(
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
          }

          body = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Center(child: content),
          );
        }

        final sectionTitle = widget.sectionTitle?.trim();
        if (sectionTitle != null && sectionTitle.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CardBackSection(
              title: sectionTitle,
              child: SizedBox(
                height: widget.sectionBodyHeight,
                child: body,
              ),
            ),
          );
        }
        return body;
      },
    );
  }
}
