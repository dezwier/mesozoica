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

  @override
  Widget build(BuildContext context) {
    final lineage = dinosaur.cladogramLineage();
    final titleColor = DinoCardTheme.titleColor(context);
    final labelColor = DinoCardTheme.labelColor(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dinosaur.name.toUpperCase(),
            style: TextStyle(
              color: titleColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          if (dinosaur.shortDescription != null &&
              dinosaur.shortDescription!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dinosaur.shortDescription!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    DinoFactRow(
                      icon: Icons.place_outlined,
                      label: 'Location',
                      value: _orDash(dinosaur.location),
                    ),
                    DinoFactRow(
                      icon: Icons.schedule_outlined,
                      label: 'Period',
                      value: dinosaur.displayPeriod,
                    ),
                    DinoFactRow(
                      icon: Icons.restaurant_outlined,
                      label: 'Diet',
                      value: _orDash(dinosaur.dietType),
                    ),
                    DinoFactRow(
                      icon: Icons.straighten_outlined,
                      label: 'Length',
                      value: _orDash(dinosaur.length),
                    ),
                    DinoFactRow(
                      icon: Icons.fitness_center_outlined,
                      label: 'Mass',
                      value: _orDash(dinosaur.mass),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GeologicTimeline(
                birth: dinosaur.birth,
                death: dinosaur.death,
              ),
            ],
          ),
          const SizedBox(height: 8),
          CladogramStrip(lineage: lineage),
        ],
      ),
    );
  }
}
