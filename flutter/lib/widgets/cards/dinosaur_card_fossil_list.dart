import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../models/fossil.dart';
import '../../services/fossil_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_record_thumb.dart';
import 'fossil_card_dialog.dart';
import 'fossil_card_image.dart';

/// Scrollable fossil thumbnails for the dinosaur card back face.
class DinosaurCardFossilList extends StatefulWidget {
  const DinosaurCardFossilList({
    super.key,
    required this.dinosaurId,
    this.fossilService,
  });

  final int dinosaurId;
  final FossilService? fossilService;

  @override
  State<DinosaurCardFossilList> createState() => _DinosaurCardFossilListState();
}

class _DinosaurCardFossilListState extends State<DinosaurCardFossilList> {
  late final FossilService _service;
  late final bool _ownsService;
  Future<List<FossilSummary>>? _fossilsFuture;
  CatalogDataSource? _loadedForSource;
  int? _loadedForDinosaurId;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
  }

  void _ensureLoaded(CatalogDataSource source) {
    if (_loadedForSource == source &&
        _loadedForDinosaurId == widget.dinosaurId &&
        _fossilsFuture != null) {
      return;
    }
    _loadedForSource = source;
    _loadedForDinosaurId = widget.dinosaurId;
    _fossilsFuture = _loadFossils(source);
  }

  @override
  void didUpdateWidget(covariant DinosaurCardFossilList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dinosaurId != widget.dinosaurId) {
      _loadedForDinosaurId = null;
    }
  }

  Future<List<FossilSummary>> _loadFossils(CatalogDataSource source) async {
    final response = await _service.fetchFossilsForDinosaur(
      widget.dinosaurId,
      dataSource: source,
    );
    return response.items;
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
    final source = context.watch<CatalogModeController>().dataSource;
    _ensureLoaded(source);
    final cardTheme = DinoCardTheme.of(context);

    return FutureBuilder<List<FossilSummary>>(
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

        final fossils = snapshot.data ?? const <FossilSummary>[];
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
                  SizedBox(
                    width: thumbSize,
                    height: thumbSize,
                    child: CardRecordThumb(
                      image: FossilCardImage(
                        imageUrl: fossils.first.mainImageUrl,
                      ),
                      label: fossils.first.displayTitle,
                      onTap: () => showFossilCardDialog(
                        context,
                        fossilId: fossils.first.id,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }

        final rowCount = (fossils.length / 2).ceil();
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            final thumbSize = (constraints.maxWidth - gap) / 2;
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
                    SizedBox(
                      width: thumbSize,
                      height: thumbSize,
                      child: CardRecordThumb(
                        image: FossilCardImage(
                          imageUrl: fossils[leftIndex].mainImageUrl,
                        ),
                        label: fossils[leftIndex].displayTitle,
                        onTap: () => showFossilCardDialog(
                          context,
                          fossilId: fossils[leftIndex].id,
                        ),
                      ),
                    ),
                    const SizedBox(width: gap),
                    if (rightIndex < fossils.length)
                      SizedBox(
                        width: thumbSize,
                        height: thumbSize,
                        child: CardRecordThumb(
                          image: FossilCardImage(
                            imageUrl: fossils[rightIndex].mainImageUrl,
                          ),
                          label: fossils[rightIndex].displayTitle,
                          onTap: () => showFossilCardDialog(
                            context,
                            fossilId: fossils[rightIndex].id,
                          ),
                        ),
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
