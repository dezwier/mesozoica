import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'fossil_card_dialog.dart';
import 'fossil_record_thumb.dart';

/// Fossil thumbnails on the site card back, centered in rows of four.
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

  static const _columns = 4;
  static const _gap = 6.0;

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

        return LayoutBuilder(
          builder: (context, constraints) {
            final thumbSize =
                (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
            final rowCount = (fossils.length / _columns).ceil();

            return ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: rowCount,
              separatorBuilder: (context, index) => const SizedBox(height: _gap),
              itemBuilder: (context, rowIndex) {
                final rowStart = rowIndex * _columns;
                final rowEnd =
                    (rowStart + _columns).clamp(0, fossils.length);
                final rowFossils = fossils.sublist(rowStart, rowEnd);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < rowFossils.length; col++) ...[
                      if (col > 0) const SizedBox(width: _gap),
                      SizedBox(
                        width: thumbSize,
                        height: thumbSize,
                        child: FossilRecordThumb(
                          imageUrl: rowFossils[col].mainImageUrl,
                          label: rowFossils[col].displayLabel,
                          onTap: () => showFossilCardDialog(
                            context,
                            fossilId: rowFossils[col].id,
                          ),
                        ),
                      ),
                    ],
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
