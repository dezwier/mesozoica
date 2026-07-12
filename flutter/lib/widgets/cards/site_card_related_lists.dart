import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Dino rows on the site card back: one dinosaur left, its fossils scrolling right.
class SiteCardDinoFossilGroups extends StatefulWidget {
  const SiteCardDinoFossilGroups({
    super.key,
    required this.siteId,
    this.siteService,
    this.thumbWidth = 56,
  });

  final int siteId;
  final SiteService? siteService;
  final double thumbWidth;

  @override
  State<SiteCardDinoFossilGroups> createState() =>
      _SiteCardDinoFossilGroupsState();
}

class _SiteCardDinoFossilGroupsState extends State<SiteCardDinoFossilGroups> {
  late final SiteService _service;
  late final bool _ownsService;
  late Future<List<SiteDinoFossilGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    _groupsFuture = _loadGroups();
  }

  @override
  void didUpdateWidget(covariant SiteCardDinoFossilGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _groupsFuture = _loadGroups();
    }
  }

  Future<List<SiteDinoFossilGroup>> _loadGroups() async {
    return _service.fetchDinoFossilGroupsForSite(widget.siteId);
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  double get _rowHeight => widget.thumbWidth / DinoCardTheme.cardAspectRatio;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return FutureBuilder<List<SiteDinoFossilGroup>>(
      future: _groupsFuture,
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

        final groups = snapshot.data ?? const <SiteDinoFossilGroup>[];
        if (groups.isEmpty) {
          return Center(
            child: Text(
              'No fossil occurrences',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          );
        }

        return ListView.separated(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: groups.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final group = groups[index];
            return _DinoFossilRow(
              group: group,
              thumbWidth: widget.thumbWidth,
              rowHeight: _rowHeight,
            );
          },
        );
      },
    );
  }
}

class _DinoFossilRow extends StatelessWidget {
  const _DinoFossilRow({
    required this.group,
    required this.thumbWidth,
    required this.rowHeight,
  });

  final SiteDinoFossilGroup group;
  final double thumbWidth;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: thumbWidth,
            child: _DinosaurThumbnail(
              imageUrl: group.dinosaur.mainImageUrl,
              onTap: () => showDinosaurCardDialog(
                context,
                dinosaurId: group.dinosaur.id,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: group.fossils.isEmpty
                ? const SizedBox.shrink()
                : group.fossils.length == 1
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: thumbWidth,
                          child: _FossilThumbnail(
                            imageUrl: group.fossils.first.mainImageUrl,
                            onTap: () => showFossilCardDialog(
                              context,
                              fossilId: group.fossils.first.id,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: group.fossils.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final fossil = group.fossils[index];
                      return SizedBox(
                        width: thumbWidth,
                        child: _FossilThumbnail(
                          imageUrl: fossil.mainImageUrl,
                          onTap: () => showFossilCardDialog(
                            context,
                            fossilId: fossil.id,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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

class _DinosaurThumbnail extends StatelessWidget {
  const _DinosaurThumbnail({
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
          child: DinosaurCardImage(imageUrl: imageUrl),
        ),
      ),
    );
  }
}
