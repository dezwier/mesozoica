import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../services/fossil_service.dart';
import '../../theme/dino_card_theme.dart';
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
  late Future<List<FossilSummary>> _fossilsFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
    _fossilsFuture = _loadFossils();
  }

  @override
  void didUpdateWidget(covariant DinosaurCardFossilList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dinosaurId != widget.dinosaurId) {
      _fossilsFuture = _loadFossils();
    }
  }

  Future<List<FossilSummary>> _loadFossils() async {
    final response = await _service.fetchFossilsForDinosaur(widget.dinosaurId);
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

        return ListView.separated(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: fossils.length,
          separatorBuilder: (context, index) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final fossil = fossils[index];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showFossilCardDialog(
                  context,
                  fossilId: fossil.id,
                ),
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: DinoCardTheme.cardAspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FossilCardImage(imageUrl: fossil.mainImageUrl),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
