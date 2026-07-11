import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../widgets/cards/dinosaur_turnable_card.dart';

class DinoScreen extends StatefulWidget {
  const DinoScreen({super.key});

  @override
  State<DinoScreen> createState() => _DinoScreenState();
}

class _DinoScreenState extends State<DinoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DinosaurCatalogController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DinosaurCatalogController>(
      builder: (context, catalog, _) {
        if (catalog.loading && catalog.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (catalog.error != null && catalog.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    catalog.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => catalog.load(force: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (catalog.isEmpty) {
          return Center(
            child: Text(
              'No dinosaurs in the catalog yet.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => catalog.load(force: true),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: catalog.items.length,
            itemBuilder: (context, index) {
              final dinosaur = catalog.items[index];
              return DinosaurTurnableCard(dinosaur: dinosaur);
            },
          ),
        );
      },
    );
  }
}
