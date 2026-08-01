import 'package:flutter/material.dart';

/// Asset paths for palaeontology skill tile / detail-sheet logos.
const skillIconAssets = <String, String>{
  'site_discovery': 'assets/images/chrome/skills/site_discovery.png',
  'site_survey': 'assets/images/chrome/skills/site_survey.png',
  'site_clearing': 'assets/images/chrome/skills/site_clearing.png',
  'fossil_detection': 'assets/images/chrome/skills/fossil_detection.png',
  'fossil_excavation': 'assets/images/chrome/skills/fossil_excavation.png',
  'fossil_transport': 'assets/images/chrome/skills/fossil_transport.png',
  'fossil_curation': 'assets/images/chrome/skills/fossil_curation.png',
  'fossil_analysis': 'assets/images/chrome/skills/fossil_analysis.png',
  'dinosaur_modelling': 'assets/images/chrome/skills/dinosaur_modelling.png',
  'dinosaur_mounting': 'assets/images/chrome/skills/dinosaur_mounting.png',
};

String? skillIconAssetFor(String skillId) => skillIconAssets[skillId];

/// Skill logo image; falls back to a generic icon when no asset exists.
class SkillIcon extends StatelessWidget {
  const SkillIcon({
    super.key,
    required this.skillId,
    this.size = 22,
    this.color,
  });

  final String skillId;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = skillIconAssetFor(skillId);
    if (asset == null) {
      return Icon(
        Icons.circle_outlined,
        size: size,
        color: color,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
