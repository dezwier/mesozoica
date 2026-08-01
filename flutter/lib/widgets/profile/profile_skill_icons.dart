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
///
/// When [size] is null, expands to fill the parent (use inside a bounded box).
/// When [circular] is true, renders as a round avatar with a subtle ring.
class SkillIcon extends StatelessWidget {
  const SkillIcon({
    super.key,
    required this.skillId,
    this.size,
    this.color,
    this.circular = false,
  });

  final String skillId;
  final double? size;
  final Color? color;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = skillIconAssetFor(skillId);
    final Widget image;
    if (asset == null) {
      image = Icon(
        Icons.circle_outlined,
        size: size != null ? size! * 0.55 : 22,
        color: color ?? scheme.onSurfaceVariant,
      );
    } else {
      image = Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    if (!circular) {
      if (size == null) return image;
      return SizedBox(width: size, height: size, child: image);
    }

    final avatar = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.onSurface.withValues(alpha: 0.08),
            scheme.onSurface.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.14),
            blurRadius: 5,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: image,
      ),
    );

    if (size == null) {
      return AspectRatio(aspectRatio: 1, child: avatar);
    }
    return SizedBox(width: size, height: size, child: avatar);
  }
}
