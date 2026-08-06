import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../services/auth_service.dart';
import '../theme/map_chrome_decorations.dart';
import '../theme/map_chrome_theme.dart';

/// Top-left map profile chip: avatar, level, name, title, XP bar.
class MapUserHud extends StatelessWidget {
  const MapUserHud({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Target for the XP-earned magic-string animation.
  static final GlobalKey xpBarKey = GlobalKey(debugLabel: 'mapUserHudXpBar');

  static final _xpFormat = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final profile = auth.currentUser;
        final imageUrl = profile != null
            ? AuthService.imageUrl(profile.profileImage)
            : '';
        final name = _displayName(profile?.username, profile?.displayName);
        final career = profile?.effectiveCareer;
        final level = career?.level ?? profile?.level ?? 1;
        final title = career?.title ?? profile?.careerTitle ?? 'Explorer';
        final xp = career?.xp ?? 0;
        final nextXp = career?.nextLevelXp ?? 0;
        final progress = (career?.progress ?? 0).clamp(0.0, 1.0);

        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarWithLevel(imageUrl: imageUrl, level: level),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF8F4EC),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: MapChromeTheme.serifFont,
                        height: 1.15,
                        shadows: [
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        fontFamily: MapChromeTheme.serifFont,
                        height: 1.15,
                        shadows: const [
                          Shadow(
                            color: Color(0xAA000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          key: xpBarKey,
                          width: 72,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: MapChromeTheme.brassDark,
                                width: 0.75,
                              ),
                              color: MapChromeTheme.dialFace,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: SizedBox(
                                height: 4,
                                child: LinearProgressIndicator(
                                  value: nextXp > 0 ? progress : 1,
                                  backgroundColor: Colors.transparent,
                                  color: MapChromeTheme.gold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              letterSpacing: 0.15,
                              shadows: const [
                                Shadow(
                                  color: Color(0xAA000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            children: [
                              TextSpan(
                                text: nextXp > 0
                                    ? '${_xpFormat.format(xp)} / ${_xpFormat.format(nextXp)}'
                                    : _xpFormat.format(xp),
                              ),
                              const TextSpan(
                                text: ' XP',
                                style: TextStyle(color: MapChromeTheme.gold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _displayName(String? username, String? displayName) {
    final name = (username != null && username.trim().isNotEmpty)
        ? username.trim()
        : (displayName ?? '').trim();
    if (name.isEmpty) return 'Guest';
    return name
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }
}

class _AvatarWithLevel extends StatelessWidget {
  const _AvatarWithLevel({required this.imageUrl, required this.level});

  final String imageUrl;
  final int level;

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 4,
      height: _size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 2,
            top: 0,
            child: SizedBox(
              width: _size,
              height: _size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MapChromeTheme.parchment,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                  const Positioned.fill(
                    child: CustomPaint(
                      painter: BrassRimPainter(rimFraction: 0.08),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ClipOval(
                      child: imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, _, _) => _fallback(),
                            )
                          : _fallback(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.35),
                  colors: [
                    MapChromeTheme.brassLight,
                    MapChromeTheme.brassMid,
                    MapChromeTheme.brassDark,
                  ],
                ),
                border: Border.all(color: MapChromeTheme.brassRim, width: 1.25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '$level',
                style: const TextStyle(
                  color: MapChromeTheme.cream,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  shadows: [Shadow(color: Color(0x88000000), blurRadius: 2)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Image.asset('assets/images/logo.png', fit: BoxFit.cover);
  }
}
