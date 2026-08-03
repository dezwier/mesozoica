import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/walk_distance_controller.dart';
import '../../models/profile.dart';
import 'profile_skill_detail_sheet.dart';
import 'profile_skill_icons.dart';
import '../../services/auth_service.dart';
import '../../theme/dino_card_theme.dart';
import '../common/app_card.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({
    super.key,
    required this.profile,
    this.headerActions,
  });

  final Profile profile;
  final Widget? headerActions;
  static const double _cardRadius = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderCard(context, scheme),
        const SizedBox(height: 5),
        _buildLevelsCard(context, scheme),
        const SizedBox(height: 5),
        _buildStatsGrid(context, scheme),
        const SizedBox(height: 5),
        _buildDistanceCard(context, scheme),
        const SizedBox(height: 5),
        _buildProfessionalCard(context, scheme),
      ],
    );
  }

  Widget _buildHeaderCard(BuildContext context, ColorScheme scheme) {
    final imageUrl = AuthService.imageUrl(profile.profileImage);
    return AppCard.profile(
      borderRadius: _cardRadius,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.1),
            scheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          children: [
            if (headerActions != null) ...[
              Align(alignment: Alignment.topRight, child: headerActions!),
              const SizedBox(height: 8),
            ],
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: scheme.surfaceContainerHighest,
                    backgroundImage: imageUrl.isNotEmpty
                        ? CachedNetworkImageProvider(imageUrl)
                        : null,
                    child: imageUrl.isEmpty
                        ? ClipOval(
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Lv.${profile.level}',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              profile.fullName?.trim().isNotEmpty == true
                  ? profile.fullName!.trim()
                  : profile.displayName,
              style: DinoCardTheme.of(context).titleStyle(fontSize: 24).copyWith(
                    color: scheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              profile.careerTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(profile.username ?? 'user'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(profile.currentLocation.isEmpty
                    ? 'Unknown location'
                    : profile.currentLocation),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelsCard(BuildContext context, ColorScheme scheme) {
    final career = profile.effectiveCareer;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LevelProgressRow(
              name: 'Palaeontology Career',
              level: career.level,
              maxLevel: 120,
              xp: career.xp,
              nextLevelXp: career.nextLevelXp,
              progress: career.progress,
              emphasized: true,
            ),
            if (profile.skills.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SkillGrid(
                skills: profile.skills,
                onSkillTap: (skill) => showProfileSkillDetailSheet(
                  context,
                  skill: skill,
                  breakdown: profile.skillBreakdown[skill.id],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, ColorScheme scheme) {
    const avatarSize = 36.0;
    final stats = [
      (
        'Sites',
        'assets/images/cards/site_card_front_placeholder.png',
        profile.actualSitesCount,
      ),
      (
        'Fossils',
        'assets/images/cards/fossil_card_front_placeholder.png',
        profile.actualFossilsCount,
      ),
      (
        'Dinosaurs',
        'assets/images/cards/dinosaur_card_front_placeholder.png',
        profile.actualDinosaursCount,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_cardRadius),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(_cardRadius),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  children: [
                    Text(
                      '${stats[i].$3}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: avatarSize / 2,
                        backgroundColor: scheme.surfaceContainerHighest,
                        backgroundImage: AssetImage(stats[i].$2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stats[i].$1,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDistanceCard(BuildContext context, ColorScheme scheme) {
    return Consumer<WalkDistanceController>(
      builder: (context, walk, _) {
        final weekLabel = _explorationDistanceLabel(walk.displayWeeklyMeters);
        final totalLabel = _explorationDistanceLabel(walk.displayTotalMeters);
        final isActive = walk.mode == ExploringDistanceMode.active;
        final weekStatLabel =
            isActive ? 'This week (active)' : 'This week';
        final allTimeStatLabel =
            isActive ? 'All time (active)' : 'All time';
        return AppCard.profile(
          borderRadius: _cardRadius,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(_cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_cardRadius),
              onTap: () {
                unawaited(
                  walk.setMode(
                    isActive
                        ? ExploringDistanceMode.total
                        : ExploringDistanceMode.active,
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(_cardRadius),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_walk,
                          color: scheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Exploration',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (walk.loading) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _distanceStat(
                            context,
                            scheme,
                            label: weekStatLabel,
                            value: weekLabel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _distanceStat(
                            context,
                            scheme,
                            label: allTimeStatLabel,
                            value: totalLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _distanceStat(
    BuildContext context,
    ColorScheme scheme, {
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  /// &lt;1 km → meters; &lt;10 km → one decimal; otherwise whole km.
  String _explorationDistanceLabel(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    final km = meters / 1000.0;
    if (km < 10) {
      return '${km.toStringAsFixed(1)} km';
    }
    return '${km.round()} km';
  }

  Widget _buildProfessionalCard(BuildContext context, ColorScheme scheme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.work, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Professional Details',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow(context, scheme, 'Experience',
                '${profile.yearsOfExperience} years'),
            _detailRow(context, scheme, 'Notable Discovery',
                profile.notableDiscovery.isEmpty
                    ? '—'
                    : profile.notableDiscovery),
            _detailRow(context, scheme, 'Favorite Era',
                profile.favoriteEra.isEmpty ? '—' : profile.favoriteEra),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    ColorScheme scheme,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    )),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _LevelProgressRow extends StatelessWidget {
  const _LevelProgressRow({
    required this.name,
    required this.level,
    required this.xp,
    required this.nextLevelXp,
    required this.progress,
    this.maxLevel = 99,
    this.emphasized = false,
  });

  final String name;
  final int level;
  final int maxLevel;
  final int xp;
  final int nextLevelXp;
  final double progress;
  final bool emphasized;

  static String _formatXp(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = emphasized
        ? Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            );
    final levelStyle = emphasized
        ? Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            );
    final muted = scheme.onSurfaceVariant.withValues(
      alpha: emphasized ? 0.9 : 0.7,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name, style: titleStyle),
            ),
            Text('$level/$maxLevel', style: levelStyle),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: emphasized ? 7 : 4,
            backgroundColor: scheme.onSurface.withValues(
              alpha: emphasized ? 0.08 : 0.05,
            ),
            color: scheme.primary.withValues(alpha: emphasized ? 0.8 : 0.35),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_formatXp(xp)} / ${_formatXp(nextLevelXp)} xp',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: 0.15,
                fontSize: emphasized ? null : 11,
              ),
        ),
      ],
    );
    return content;
  }
}

class _SkillGrid extends StatelessWidget {
  const _SkillGrid({
    required this.skills,
    required this.onSkillTap,
  });

  final List<SkillState> skills;
  final ValueChanged<SkillState> onSkillTap;

  static const _crossAxisCount = 3;
  static const _spacing = 6.0;
  static const _tileHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const avatarPad = 4.0;
    const avatarSize = _tileHeight - avatarPad * 2;
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: skills.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        crossAxisSpacing: _spacing,
        mainAxisSpacing: _spacing,
        mainAxisExtent: _tileHeight,
      ),
      itemBuilder: (context, index) {
        final skill = skills[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSkillTap(skill),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: scheme.onSurface.withValues(alpha: 0.04),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(avatarPad),
                    child: SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: SkillIcon(
                        skillId: skill.id,
                        circular: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SkillLevelBadge(
                        level: skill.level,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Level badge: current level top-left, 99 bottom-right, diagonal slash between.
class _SkillLevelBadge extends StatelessWidget {
  const _SkillLevelBadge({
    required this.level,
    required this.color,
  });

  final int level;
  final Color color;

  static const _size = Size(34, 34);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size.width,
      height: _size.height,
      child: Stack(
        children: [
          CustomPaint(
            size: _size,
            painter: _DiagonalSlashPainter(
              color: color.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            top: 1,
            left: 0,
            width: 18,
            child: Text(
              '$level',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 1,
            width: 16,
            child: Text(
              '99',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: color.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
                fontSize: 10.5,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalSlashPainter extends CustomPainter {
  _DiagonalSlashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Shorter diagonal leaves room for centered 2-digit levels.
    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.22),
      Offset(size.width * 0.22, size.height * 0.78),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DiagonalSlashPainter oldDelegate) =>
      oldDelegate.color != color;
}
