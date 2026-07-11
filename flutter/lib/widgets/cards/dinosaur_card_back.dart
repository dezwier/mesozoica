import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'cladogram_strip.dart';
import 'dino_fact_row.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  String? _subtitle() {
    final title = dinosaur.wikipediaTitle.trim();
    if (title.isEmpty || title.toLowerCase() == dinosaur.name.toLowerCase()) {
      return null;
    }
    return title.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final lineage = dinosaur.cladogramLineage();
    final subtitle = _subtitle();

    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ColoredBox(
        color: DinoCardTheme.cardBackground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                name: dinosaur.name,
                subtitle: subtitle,
              ),
              const SizedBox(height: 14),
              DinoFactRow(
                iconAsset: 'assets/images/cards/icons/location.svg',
                label: 'Location',
                value: _orDash(dinosaur.location),
              ),
              DinoFactRow(
                iconAsset: 'assets/images/cards/icons/period.svg',
                label: 'Time Period',
                value: dinosaur.displayPeriod,
              ),
              DinoFactRow(
                iconAsset: 'assets/images/cards/icons/diet.svg',
                label: 'Diet',
                value: _orDash(dinosaur.dietType),
              ),
              DinoFactRow(
                iconAsset: 'assets/images/cards/icons/length.svg',
                label: 'Length',
                value: _orDash(dinosaur.length),
              ),
              DinoFactRow(
                iconAsset: 'assets/images/cards/icons/mass.svg',
                label: 'Mass',
                value: _orDash(dinosaur.mass),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CladogramStrip(lineage: lineage),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: GeologicTimeline(
                        birth: dinosaur.birth,
                        death: dinosaur.death,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                dinosaur.shortDescription != null &&
                        dinosaur.shortDescription!.trim().isNotEmpty
                    ? dinosaur.shortDescription!.trim()
                    : '—',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: DinoCardTheme.bodyStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, this.subtitle});

  final String name;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.toUpperCase(),
          style: DinoCardTheme.titleStyle(fontSize: 18),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: DinoCardTheme.subtitleStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
