import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';
import '../common/drawer_sheet_sizes.dart';
import 'dinosaur_wikipedia_view.dart';

class DinosaurArticleDrawer extends StatefulWidget {
  const DinosaurArticleDrawer({
    super.key,
    required this.dinosaur,
    this.dinosaurService,
  });

  final DinosaurSummary dinosaur;
  final DinosaurService? dinosaurService;

  static Future<void> show(
    BuildContext context, {
    required DinosaurSummary dinosaur,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DinosaurArticleDrawer(dinosaur: dinosaur),
    );
  }

  @override
  State<DinosaurArticleDrawer> createState() => _DinosaurArticleDrawerState();
}

class _DinosaurArticleDrawerState extends State<DinosaurArticleDrawer> {
  late final DinosaurService _service;
  DateTime? _asOf;
  var _resolvingAsOf = false;

  int get _typeId => widget.dinosaur.dinosaurTypeId ?? widget.dinosaur.id;

  @override
  void initState() {
    super.initState();
    _service = widget.dinosaurService ?? DinosaurService();
    // Prefer the content revision's Wikipedia timestamp (pinned for inventory
    // occurrences). insertDate is type-level and shared across all cards of a
    // genus, so it must not be the primary as-of for inventory.
    _asOf = widget.dinosaur.articleDate ?? widget.dinosaur.insertDate;
    if (_asOf == null) {
      _resolveAsOf();
    }
  }

  Future<void> _resolveAsOf() async {
    setState(() => _resolvingAsOf = true);
    try {
      final article = await _service.fetchDinosaurArticle(_typeId);
      if (!mounted) return;
      setState(() {
        _asOf = article.articleDate ?? widget.dinosaur.insertDate;
        _resolvingAsOf = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _asOf = widget.dinosaur.insertDate;
        _resolvingAsOf = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.dinosaur.wikipediaTitle.trim();

    // Fixed height (not DraggableScrollableSheet) so the WebView owns
    // vertical scroll gestures instead of competing with sheet dragging.
    return SizedBox(
      height:
          MediaQuery.sizeOf(context).height * DrawerSheetSizes.initialChildSize,
      child: title.isEmpty
          ? const _MessagePane(
              icon: Icons.article_outlined,
              message: 'No Wikipedia article is linked for this dinosaur yet.',
            )
          : _resolvingAsOf && _asOf == null
          ? const Center(child: CircularProgressIndicator())
          : DinosaurWikipediaView(
              key: ValueKey(_asOf?.toIso8601String() ?? 'live'),
              wikipediaTitle: title,
              asOf: _asOf,
              preferDark: theme.brightness == Brightness.dark,
            ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
