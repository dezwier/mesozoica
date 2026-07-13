import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_record_thumb.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Fossil thumbnails on the site card back — one large square, or two per row.
class SiteCardFossils extends StatefulWidget {
  const SiteCardFossils({
    super.key,
    required this.siteId,
    this.siteService,
  });

  final int siteId;
  final SiteService? siteService;

  @override
  State<SiteCardFossils> createState() => _SiteCardFossilsState();
}

class _SiteCardFossilsState extends State<SiteCardFossils> {
  late final SiteService _service;
  late final bool _ownsService;
  late Future<List<SiteFossilThumb>> _fossilsFuture;

  static const _gap = 6.0;

  Widget _buildThumb({
    required BuildContext context,
    required SiteFossilThumb fossil,
    required double thumbSize,
  }) {
    return SizedBox(
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
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    _fossilsFuture = _loadFossils();
  }

  @override
  void didUpdateWidget(covariant SiteCardFossils oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _fossilsFuture = _loadFossils();
    }
  }

  Future<List<SiteFossilThumb>> _loadFossils() async {
    return _service.fetchFossilsForSite(widget.siteId);
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

        if (fossils.length == 1) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final thumbSize = constraints.maxWidth;
              return ListView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  _buildThumb(
                    context: context,
                    fossil: fossils.first,
                    thumbSize: thumbSize,
                  ),
                ],
              );
            },
          );
        }

        final rowCount = (fossils.length / 2).ceil();
        return LayoutBuilder(
          builder: (context, constraints) {
            final thumbSize = (constraints.maxWidth - _gap) / 2;
            return ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: rowCount,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: _gap),
              itemBuilder: (context, rowIndex) {
                final leftIndex = rowIndex * 2;
                final rightIndex = leftIndex + 1;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildThumb(
                      context: context,
                      fossil: fossils[leftIndex],
                      thumbSize: thumbSize,
                    ),
                    const SizedBox(width: _gap),
                    if (rightIndex < fossils.length)
                      _buildThumb(
                        context: context,
                        fossil: fossils[rightIndex],
                        thumbSize: thumbSize,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
