import 'package:flutter/material.dart';

/// Material icons for palaeontology skill tiles / detail sheets.
const skillIcons = <String, IconData>{
  'site_discovery': Icons.travel_explore_rounded,
  'site_protection': Icons.shield_rounded,
  'site_clearing': Icons.landscape_rounded,
  'fossil_detection': Icons.radar_rounded,
  'fossil_excavation': Icons.hardware_rounded,
  'fossil_transport': Icons.local_shipping_rounded,
  'fossil_curation': Icons.warehouse_rounded,
  'fossil_analysis': Icons.biotech_rounded,
  'dinosaur_reconstruction': Icons.pets_rounded,
};

IconData skillIconFor(String skillId) =>
    skillIcons[skillId] ?? Icons.circle_outlined;
