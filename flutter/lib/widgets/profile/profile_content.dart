import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import '../../controllers/walk_distance_controller.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../services/health_distance_service.dart';
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
        _buildStatsGrid(context, scheme),
        const SizedBox(height: 5),
        _buildDistanceCard(context, scheme),
        const SizedBox(height: 5),
        _buildBioCard(context, scheme),
        const SizedBox(height: 5),
        _buildAchievementsCard(context, scheme),
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
              profile.specialization,
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

  Widget _buildStatsGrid(BuildContext context, ColorScheme scheme) {
    final stats = [
      ('Sites', Icons.explore, profile.actualSitesCount),
      ('Fossils', Icons.auto_awesome, profile.actualFossilsCount),
      ('Dinosaurs', Icons.pets, profile.actualDinosaursCount),
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
                    Icon(stats[i].$2, color: scheme.primary, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      '${stats[i].$3}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
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
        final weekKm = _kmLabel(walk.displayWeeklyMeters);
        final totalKm = _kmLabel(walk.displayTotalMeters);
        final caption = _distanceCaption(walk);
        return AppCard.profile(
          borderRadius: _cardRadius,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.directions_walk, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Distance walked',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (walk.loading)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<ExploringDistanceMode>(
                  segments: const [
                    ButtonSegment(
                      value: ExploringDistanceMode.active,
                      label: Text('Active'),
                      icon: Icon(Icons.phone_android, size: 16),
                    ),
                    ButtonSegment(
                      value: ExploringDistanceMode.total,
                      label: Text('Total'),
                      icon: Icon(Icons.public, size: 16),
                    ),
                  ],
                  selected: {walk.mode},
                  onSelectionChanged: (selected) {
                    unawaited(walk.setMode(selected.first));
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _distanceStat(
                        context,
                        scheme,
                        label: 'This week',
                        value: weekKm,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _distanceStat(
                        context,
                        scheme,
                        label: 'Total',
                        value: totalKm,
                      ),
                    ),
                  ],
                ),
                if (caption != null) ...[
                  const SizedBox(height: 10),
                  if (walk.mode == ExploringDistanceMode.total &&
                      (walk.permission == HealthDistancePermission.denied ||
                          walk.permission == HealthDistancePermission.unknown ||
                          walk.permission ==
                              HealthDistancePermission.unavailable))
                    TextButton(
                      onPressed: () {
                        context.read<WalkDistanceController>().refresh(
                              profile: profile,
                              requestPermissionIfNeeded: true,
                              force: true,
                            );
                      },
                      child: Text(caption),
                    )
                  else
                    Text(
                      caption,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  String _kmLabel(double meters) {
    final km = meters / 1000.0;
    if (km < 10) {
      return '${km.toStringAsFixed(1)} km';
    }
    return '${km.toStringAsFixed(0)} km';
  }

  String? _distanceCaption(WalkDistanceController walk) {
    if (walk.mode == ExploringDistanceMode.active) {
      return 'While Mesozoica is open';
    }
    switch (walk.permission) {
      case HealthDistancePermission.granted:
        if (kIsWeb) {
          return 'Includes walking while the app is closed';
        }
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          return 'Includes Apple Health when closed';
        }
        if (defaultTargetPlatform == TargetPlatform.android) {
          return 'Includes Health Connect when closed';
        }
        return 'Includes walking while the app is closed';
      case HealthDistancePermission.denied:
      case HealthDistancePermission.unknown:
        return 'Enable Health access';
      case HealthDistancePermission.unavailable:
        return 'Install Health Connect';
      case HealthDistancePermission.unsupported:
        return 'GPS while open only on this device';
    }
  }

  Widget _buildBioCard(BuildContext context, ColorScheme scheme) {
    return AppCard.profile(
      borderRadius: _cardRadius,
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
                Icon(Icons.person, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('About',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              profile.bio.isEmpty ? 'No bio yet.' : profile.bio,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementsCard(BuildContext context, ColorScheme scheme) {
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
                Icon(Icons.emoji_events, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Achievements',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${profile.achievements.length}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 12),
            if (profile.achievements.isEmpty)
              Text(
                'No achievements yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile.achievements.map((achievement) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(achievement,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w500,
                            )),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
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
