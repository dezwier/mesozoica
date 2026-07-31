import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
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
  bool? _loadedIncludeHidden;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
  }

  void _ensureLoaded(CatalogDataSource source, {required bool includeHidden}) {
    if (_loadedForSource == source &&
        _loadedForDinosaurId == widget.dinosaurId &&
        _loadedIncludeHidden == includeHidden &&
        _fossilsFuture != null) {
      return;
    }
    _loadedForSource = source;
    _loadedForDinosaurId = widget.dinosaurId;
    _loadedIncludeHidden = includeHidden;
    _fossilsFuture = _loadFossils(source, includeHidden: includeHidden);
  }

  @override
  void didUpdateWidget(covariant DinosaurCardFossilList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dinosaurId != widget.dinosaurId) {
      _loadedForDinosaurId = null;
    }
  }

  Future<List<FossilSummary>> _loadFossils(
    CatalogDataSource source, {
    required bool includeHidden,
  }) async {
    final response = await _service.fetchFossilsForDinosaur(
      widget.dinosaurId,
      dataSource: source,
      includeHidden: includeHidden,
    );
    return response.items;
  }

  Widget _buildThumb({
    required BuildContext context,
    required FossilSummary fossil,
    required double thumbSize,
  }) {
    final thumb = SizedBox(
      width: thumbSize,
      height: thumbSize,
      child: CardRecordThumb(
        image: FossilCardImage(imageUrl: fossil.mainImageUrl),
        label: fossil.displayTitle,
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
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = context.watch<CatalogModeController>().dataSource;
    final includeHidden = context.watch<AuthController>().showAdminUi;
    _ensureLoaded(source, includeHidden: includeHidden);
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
                    _buildThumb(
                      context: context,
                      fossil: fossils[leftIndex],
                      thumbSize: thumbSize,
                    ),
                    const SizedBox(width: gap),
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
