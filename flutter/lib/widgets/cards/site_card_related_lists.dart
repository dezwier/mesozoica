import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Dino rows on the site card back: one dinosaur left, its fossils on the right.
class SiteCardDinoFossilGroups extends StatefulWidget {
  const SiteCardDinoFossilGroups({
    super.key,
    required this.siteId,
    this.siteService,
  });

  final int siteId;
  final SiteService? siteService;

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
            return _DinoFossilRow(group: groups[index]);
          },
        );
      },
    );
  }
}

class _DinoFossilRow extends StatelessWidget {
  const _DinoFossilRow({required this.group});

  final SiteDinoFossilGroup group;

  static const _largeThumbWidth = 112.0;
  static const _smallThumbWidth = 56.0;
  static const _fossilRowGap = 6.0;

  double _thumbHeight(double width) => width / DinoCardTheme.cardAspectRatio;

  @override
  Widget build(BuildContext context) {
    final fossils = group.fossils;
    final compactFossils = fossils.length >= 3;
    final fossilThumbWidth =
        compactFossils ? _smallThumbWidth : _largeThumbWidth;

    final dinoHeight = _thumbHeight(_largeThumbWidth);
    final fossilHeight = _thumbHeight(fossilThumbWidth);
    final rowHeight = compactFossils
        ? (fossilHeight * 2 + _fossilRowGap).clamp(dinoHeight, double.infinity)
        : dinoHeight;

    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _largeThumbWidth,
            height: dinoHeight,
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
            child: _buildFossilArea(
              context,
              fossils: fossils,
              compactFossils: compactFossils,
              fossilThumbWidth: fossilThumbWidth,
              fossilHeight: fossilHeight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFossilArea(
    BuildContext context, {
    required List<SiteFossilThumb> fossils,
    required bool compactFossils,
    required double fossilThumbWidth,
    required double fossilHeight,
  }) {
    if (fossils.isEmpty) {
      return const SizedBox.shrink();
    }

    if (compactFossils) {
      final split = (fossils.length / 2).ceil();
      final topRow = fossils.sublist(0, split);
      final bottomRow = fossils.sublist(split);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FossilThumbStrip(
            fossils: topRow,
            thumbWidth: fossilThumbWidth,
            thumbHeight: fossilHeight,
          ),
          const SizedBox(height: _fossilRowGap),
          _FossilThumbStrip(
            fossils: bottomRow,
            thumbWidth: fossilThumbWidth,
            thumbHeight: fossilHeight,
          ),
        ],
      );
    }

    if (fossils.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: fossilThumbWidth,
          height: fossilHeight,
          child: _FossilThumbnail(
            imageUrl: fossils.first.mainImageUrl,
            onTap: () => showFossilCardDialog(
              context,
              fossilId: fossils.first.id,
            ),
          ),
        ),
      );
    }

    return _FossilThumbStrip(
      fossils: fossils,
      thumbWidth: fossilThumbWidth,
      thumbHeight: fossilHeight,
    );
  }
}

class _FossilThumbStrip extends StatelessWidget {
  const _FossilThumbStrip({
    required this.fossils,
    required this.thumbWidth,
    required this.thumbHeight,
  });

  final List<SiteFossilThumb> fossils;
  final double thumbWidth;
  final double thumbHeight;

  @override
  Widget build(BuildContext context) {
    if (fossils.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: thumbWidth,
          height: thumbHeight,
          child: _FossilThumbnail(
            imageUrl: fossils.first.mainImageUrl,
            onTap: () => showFossilCardDialog(
              context,
              fossilId: fossils.first.id,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: thumbHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: fossils.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final fossil = fossils[index];
          return SizedBox(
            width: thumbWidth,
            height: thumbHeight,
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
