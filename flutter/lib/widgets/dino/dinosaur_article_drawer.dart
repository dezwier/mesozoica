import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../models/dinosaur_article.dart';
import '../../services/dinosaur_service.dart';
import 'dinosaur_article_html_view.dart';

class DinosaurArticleDrawer extends StatefulWidget {
  const DinosaurArticleDrawer({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

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
  final DinosaurService _service = DinosaurService();
  late Future<DinosaurArticle> _articleFuture;

  @override
  void initState() {
    super.initState();
    _articleFuture = _service.fetchDinosaurArticle(widget.dinosaur.id);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _articleFuture = _service.fetchDinosaurArticle(widget.dinosaur.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.dinosaur.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Wikipedia · ${widget.dinosaur.wikipediaTitle}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<DinosaurArticle>(
                future: _articleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _MessagePane(
                      icon: Icons.cloud_off_outlined,
                      message: snapshot.error is DinosaurServiceException
                          ? (snapshot.error! as DinosaurServiceException).message
                          : 'Could not load the article.',
                      actionLabel: 'Retry',
                      onAction: _retry,
                    );
                  }

                  final article = snapshot.data?.article;
                  if (article == null || article.trim().isEmpty) {
                    return _MessagePane(
                      icon: Icons.article_outlined,
                      message:
                          'No Wikipedia article is available for this dinosaur yet.',
                      actionLabel: 'Retry',
                      onAction: _retry,
                    );
                  }

                  return DinosaurArticleHtmlView(
                    html: article,
                    scrollController: scrollController,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
