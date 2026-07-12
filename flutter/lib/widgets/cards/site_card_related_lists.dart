import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

class SiteCardFossilList extends StatefulWidget {
  const SiteCardFossilList({
    super.key,
    required this.siteId,
    this.siteService,
  });

  final int siteId;
  final SiteService? siteService;

  @override
  State<SiteCardFossilList> createState() => _SiteCardFossilListState();
}

class _SiteCardFossilListState extends State<SiteCardFossilList> {
  late final SiteService _service;
  late final bool _ownsService;
  late Future<List<SiteFossilThumb>> _fossilsFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    _fossilsFuture = _loadFossils();
  }

  @override
  void didUpdateWidget(covariant SiteCardFossilList oldWidget) {
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
              'Could not load fossils',
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

        return CardThumbnailGrid(
          itemCount: fossils.length,
          itemBuilder: (index) => _FossilThumbnail(
            imageUrl: fossils[index].mainImageUrl,
            onTap: () => showFossilCardDialog(
              context,
              fossilId: fossils[index].id,
            ),
          ),
        );
      },
    );
  }
}

class SiteCardDinosaurList extends StatefulWidget {
  const SiteCardDinosaurList({
    super.key,
    required this.siteId,
    this.siteService,
  });

  final int siteId;
  final SiteService? siteService;

  @override
  State<SiteCardDinosaurList> createState() => _SiteCardDinosaurListState();
}

class _SiteCardDinosaurListState extends State<SiteCardDinosaurList> {
  late final SiteService _service;
  late final bool _ownsService;
  late Future<List<SiteDinosaurThumb>> _dinosaursFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    _dinosaursFuture = _loadDinosaurs();
  }

  @override
  void didUpdateWidget(covariant SiteCardDinosaurList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _dinosaursFuture = _loadDinosaurs();
    }
  }

  Future<List<SiteDinosaurThumb>> _loadDinosaurs() async {
    return _service.fetchDinosaursForSite(widget.siteId);
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

    return FutureBuilder<List<SiteDinosaurThumb>>(
      future: _dinosaursFuture,
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
              'Could not load dinosaurs',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          );
        }

        final dinosaurs = snapshot.data ?? const <SiteDinosaurThumb>[];
        if (dinosaurs.isEmpty) {
          return Center(
            child: Text(
              'No dinosaurs',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          );
        }

        return CardThumbnailGrid(
          itemCount: dinosaurs.length,
          itemBuilder: (index) => _DinosaurThumbnail(
            imageUrl: dinosaurs[index].mainImageUrl,
            onTap: () => showDinosaurCardDialog(
              context,
              dinosaurId: dinosaurs[index].id,
            ),
          ),
        );
      },
    );
  }
}

class CardThumbnailGrid extends StatelessWidget {
  const CardThumbnailGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 1) {
      return ListView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [itemBuilder(0)],
      );
    }

    final rowCount = (itemCount / 2).ceil();
    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: rowCount,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, rowIndex) {
        final leftIndex = rowIndex * 2;
        final rightIndex = leftIndex + 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: itemBuilder(leftIndex)),
            const SizedBox(width: 6),
            Expanded(
              child: rightIndex < itemCount
                  ? itemBuilder(rightIndex)
                  : const SizedBox.shrink(),
            ),
          ],
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
        child: AspectRatio(
          aspectRatio: DinoCardTheme.cardAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FossilCardImage(imageUrl: imageUrl),
          ),
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
        child: AspectRatio(
          aspectRatio: DinoCardTheme.cardAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DinosaurCardImage(imageUrl: imageUrl),
          ),
        ),
      ),
    );
  }
}
