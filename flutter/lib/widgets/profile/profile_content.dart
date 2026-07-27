import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/walk_distance_controller.dart';
import '../../models/profile.dart';
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
        _buildSkillGrid(context, scheme),
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
    final careerLabel =
        '${profile.careerTitle} - ${profile.level}';
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
              careerLabel,
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

  Widget _buildSkillGrid(BuildContext context, ColorScheme scheme) {
    final skills = [
      (
        'Exploration',
        profile.explorationLevel,
        profile.explorationXp,
        profile.explorationProgress,
        true,
      ),
      (
        'Excavation',
        profile.excavationLevel,
        profile.excavationXp,
        profile.excavationProgress,
        false,
      ),
      (
        'Research',
        profile.researchLevel,
        profile.researchXp,
        profile.researchProgress,
        false,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < skills.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: _SkillCard(
              borderRadius: _cardRadius,
              name: skills[i].$1,
              level: skills[i].$2,
              xp: skills[i].$3,
              progress: skills[i].$4,
              onLongPress: () => _showSkillBreakdown(
                context,
                skillName: skills[i].$1,
                hasBreakdown: skills[i].$5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showSkillBreakdown(
    BuildContext context, {
    required String skillName,
    required bool hasBreakdown,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        if (!hasBreakdown) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text(
              'No XP sources yet for $skillName.',
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
          );
        }
        final rows = [
          ('Sites discovered', profile.xpFromSites),
          ('Fossils discovered', profile.xpFromFossils),
          ('Active distance', profile.xpFromActiveDistance),
          ('Passive distance', profile.xpFromPassiveDistance),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$skillName XP',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              for (final row in rows) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${row.$2} XP',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
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

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.borderRadius,
    required this.name,
    required this.level,
    required this.xp,
    required this.progress,
    required this.onLongPress,
  });

  final double borderRadius;
  final String name;
  final int level;
  final int xp;
  final double progress;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            children: [
              Text(
                'Lv.$level',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '$xp XP',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
