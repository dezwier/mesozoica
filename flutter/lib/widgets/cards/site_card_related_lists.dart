import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Fossil thumbnails on the site card back, centered in rows of three.
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

  static const _columns = 3;
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
            final thumbWidth =
                (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
            final thumbHeight = thumbWidth / DinoCardTheme.cardAspectRatio;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final fossil in fossils)
                    SizedBox(
                      width: thumbWidth,
                      height: thumbHeight,
                      child: _FossilThumbnail(
                        imageUrl: fossil.mainImageUrl,
                        onTap: () => showFossilCardDialog(
                          context,
                          fossilId: fossil.id,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FossilThumbnail extends StatelessWidget {
  const _FossilThumbnail({
    required this.imageUrl,
    required this.onTap,
  });

  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FossilCardImage(imageUrl: imageUrl),
        ),
      ),
    );
  }
}
