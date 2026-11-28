import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';
import 'card_back_backdrop.dart';
import 'card_back_corner_actions.dart';

/// Shared museum plaque: sharp hero, serif title, optional age bar, panels.
class MuseumCardFrame extends StatelessWidget {
  const MuseumCardFrame({
    super.key,
    required this.image,
    required this.title,
    required this.panels,
    required this.onHistory,
    this.subtitle,
    this.timeline,
    this.bottom,
    this.wiki,
    this.trailing,
    this.titleFontSize = 28,
    this.subtitleFontSize = 12,
    this.fillBody = true,
    this.heroFraction = CardBackBackdrop.defaultHeroFraction,
  });

  final Widget image;
  final String title;
  final String? subtitle;
  final Widget? timeline;
  final Widget panels;
  final Widget? bottom;
  final Widget? trailing;
  final VoidCallback? wiki;
  final VoidCallback onHistory;
  final double titleFontSize;
  final double subtitleFontSize;

  /// When true, [panels] receives a bounded height and should stretch.
  /// When false, panels keep their intrinsic height and scale down to fit.
  final bool fillBody;

  /// Fraction of card height used by the top hero image.
  final double heroFraction;

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    final subtitleText = subtitle?.trim();
    final showSubtitle = subtitleText != null && subtitleText.isNotEmpty;
    final hero = heroFraction.clamp(0.08, 0.4);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(image: image, heroFraction: hero),
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            bottom: 8,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Title sits in the lower hero band; shrink with heroFraction.
                final top = constraints.maxHeight * (hero * 0.58).clamp(0.08, 0.16);
                return Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MuseumTitle(
                        title: title,
                        // Period/subtitle becomes the timeline section tab.
                        subtitle: timeline != null
                            ? null
                            : (showSubtitle ? subtitleText : null),
                        trailing: trailing,
                        titleFontSize: titleFontSize,
                        subtitleFontSize: subtitleFontSize,
                        theme: theme,
                      ),
                      if (timeline != null) ...[
                        const SizedBox(height: 6),
                        _TimelineSection(
                          title: showSubtitle ? subtitleText : null,
                          child: SizedBox(height: 46, child: timeline),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                        child: fillBody
                            ? panels
                            : LayoutBuilder(
                                builder: (context, panelConstraints) {
                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: panelConstraints.maxWidth,
                                        child: panels,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (bottom != null) ...[
                        const SizedBox(height: 6),
                        bottom!,
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          CardBackCornerActions(wiki: wiki, onHistory: onHistory),
          const Positioned.fill(child: MuseumCardHairline()),
        ],
      ),
    );
  }
}

/// Timeline plaque with the same diagonal tab as Attributes / Cladogram.
class _TimelineSection extends StatelessWidget {
  const _TimelineSection({required this.child, this.title});

  final String? title;
  final Widget child;

  static const _tabOverlap = 9.0;

  @override
  Widget build(BuildContext context) {
    final label = title?.trim();
    final hasTab = label != null && label.isNotEmpty;
    final panel = MuseumInnerCard(
      padding: EdgeInsets.fromLTRB(8, hasTab ? 10 : 6, 8, 5),
      child: child,
    );
    if (!hasTab) return panel;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _tabOverlap),
          child: panel,
        ),
        Positioned(left: 0, top: 0, child: MuseumSectionTab(label: label)),
      ],
    );
  }
}

/// Shared top-lit gold rim: bright lip, soft sides, barely-there bottom.
/// Always the dark-plaque intensity (museum cards ignore app light theme).
List<Color> _museumGoldRimColors({required Color gold}) {
  final lip = Color.lerp(gold, const Color(0xFFFFF1D0), 0.42)!;
  return [
    lip.withValues(alpha: 0.88),
    gold.withValues(alpha: 0.32),
    gold.withValues(alpha: 0.10),
    gold.withValues(alpha: 0.045),
  ];
}

const _museumGoldRimStops = [0.0, 0.14, 0.55, 1.0];

LinearGradient _museumGoldRimGradient({required Color gold}) {
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: _museumGoldRimColors(gold: gold),
    stops: _museumGoldRimStops,
  );
}

/// Thin gold edge painted over a card face so the photo cannot cover it.
/// Same top-lit fade as [MuseumInnerCard] (bottom barely visible).
class MuseumCardHairline extends StatelessWidget {
  const MuseumCardHairline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    return IgnorePointer(
      child: CustomPaint(
        painter: _MuseumGoldRimStrokePainter(
          gold: theme.cardAccent,
          radius: DinoCardTheme.borderRadius,
          strokeWidth: 0.85,
        ),
      ),
    );
  }
}

class _MuseumGoldRimStrokePainter extends CustomPainter {
  const _MuseumGoldRimStrokePainter({
    required this.gold,
    required this.radius,
    required this.strokeWidth,
  });

  final Color gold;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular((radius - inset).clamp(0.0, radius)),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = _museumGoldRimGradient(gold: gold).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _MuseumGoldRimStrokePainter oldDelegate) =>
      oldDelegate.gold != gold ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Inner plaque: a thin gold rim that catches light along the top edge.
class MuseumInnerCard extends StatelessWidget {
  const MuseumInnerCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    final gold = theme.cardAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: _museumGoldRimGradient(gold: gold),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: 0.14),
            blurRadius: 6,
            spreadRadius: -2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(0.9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15.4),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF21E1814), Color(0xF2100C0A)],
            ),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

/// Which card edge the tab sits on — incline faces the inner side.
enum MuseumSectionTabEdge { left, right }

/// Section / corner title tab — wider on top, tapering toward the card interior
/// (Attributes / Cladogram / front corner badges).
class MuseumSectionTab extends StatelessWidget {
  const MuseumSectionTab({
    super.key,
    required this.label,
    this.edge = MuseumSectionTabEdge.left,
    this.fontSize = 8,
    /// Softer fill / border — used for front corner badges over imagery.
    this.soft = false,
  });

  final String label;
  final MuseumSectionTabEdge edge;
  final double fontSize;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    final gold = theme.cardAccent;
    final fill = soft
        ? Color.alphaBlend(
            gold.withValues(alpha: 0.08),
            const Color(0x9914100E),
          )
        : Color.alphaBlend(
            gold.withValues(alpha: 0.16),
            const Color(0xF214100E),
          );
    final inclineOnRight = edge == MuseumSectionTabEdge.left;
    final padding = inclineOnRight
        ? const EdgeInsets.fromLTRB(10, 5, 18, 5)
        : const EdgeInsets.fromLTRB(18, 5, 10, 5);
    final labelColor = soft
        ? Color.lerp(gold, const Color(0xFFF5E6C8), 0.55)!.withValues(alpha: 0.88)
        : Color.lerp(gold, const Color(0xFFF5E6C8), 0.35);

    return CustomPaint(
      painter: _MuseumSectionTabBorderPainter(
        gold: gold,
        inclineOnRight: inclineOnRight,
        soft: soft,
      ),
      child: ClipPath(
        clipper: _MuseumSectionTabClipper(inclineOnRight: inclineOnRight),
        child: ColoredBox(
          color: fill,
          child: Padding(
            padding: padding,
            child: Text(
              label.toUpperCase(),
              style: theme
                  .sectionLabelStyle(fontSize: fontSize)
                  .copyWith(
                    color: labelColor,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

Path _museumSectionTabPath(Size size, {required bool inclineOnRight}) {
  const cut = 12.0;
  // Match museum card corner radius (16) so corner tabs sit flush visually.
  const radius = 11.0;
  // Wider top; bottom tapers on the inner (inclined) side.
  final corners = inclineOnRight
      ? <Offset>[
          Offset.zero,
          Offset(size.width, 0),
          Offset(size.width - cut, size.height),
          Offset(0, size.height),
        ]
      : <Offset>[
          Offset.zero,
          Offset(size.width, 0),
          Offset(size.width, size.height),
          Offset(cut, size.height),
        ];
  return _roundedPolygon(corners, radius);
}

Path _roundedPolygon(List<Offset> corners, double radius) {
  final path = Path();
  final n = corners.length;
  for (var i = 0; i < n; i++) {
    final prev = corners[(i - 1 + n) % n];
    final curr = corners[i];
    final next = corners[(i + 1) % n];
    final toPrev = prev - curr;
    final toNext = next - curr;
    final dPrev = toPrev.distance;
    final dNext = toNext.distance;
    if (dPrev == 0 || dNext == 0) continue;
    final r = radius.clamp(0.0, math.min(dPrev, dNext) / 2.0);
    final p1 = curr + toPrev * (r / dPrev);
    final p2 = curr + toNext * (r / dNext);
    if (i == 0) {
      path.moveTo(p1.dx, p1.dy);
    } else {
      path.lineTo(p1.dx, p1.dy);
    }
    path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
  }
  path.close();
  return path;
}

class _MuseumSectionTabClipper extends CustomClipper<Path> {
  const _MuseumSectionTabClipper({required this.inclineOnRight});

  final bool inclineOnRight;

  @override
  Path getClip(Size size) =>
      _museumSectionTabPath(size, inclineOnRight: inclineOnRight);

  @override
  bool shouldReclip(covariant _MuseumSectionTabClipper oldClipper) =>
      oldClipper.inclineOnRight != inclineOnRight;
}

class _MuseumSectionTabBorderPainter extends CustomPainter {
  const _MuseumSectionTabBorderPainter({
    required this.gold,
    required this.inclineOnRight,
    this.soft = false,
  });

  final Color gold;
  final bool inclineOnRight;
  final bool soft;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = soft
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(gold, const Color(0xFFFFF1D0), 0.5)!
                  .withValues(alpha: 0.42),
              gold.withValues(alpha: 0.18),
              gold.withValues(alpha: 0.06),
              gold.withValues(alpha: 0.03),
            ],
            stops: _museumGoldRimStops,
          ).createShader(Offset.zero & size)
        : _museumGoldRimGradient(gold: gold).createShader(Offset.zero & size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = soft ? 0.8 : 1.0
      ..shader = shader;
    canvas.drawPath(
      _museumSectionTabPath(size, inclineOnRight: inclineOnRight),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MuseumSectionTabBorderPainter oldDelegate) =>
      oldDelegate.gold != gold ||
      oldDelegate.inclineOnRight != inclineOnRight ||
      oldDelegate.soft != soft;
}

class MuseumPanelRow extends StatelessWidget {
  const MuseumPanelRow({
    super.key,
    required this.left,
    required this.right,
    this.matchHeight = false,
  });

  final Widget left;
  final Widget right;

  /// Give both panels the height of the taller one.
  final bool matchHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: matchHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

class _MuseumTitle extends StatelessWidget {
  const _MuseumTitle({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.theme,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double titleFontSize;
  final double subtitleFontSize;
  final DinoCardTheme theme;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: CardAdaptiveTitleText(
            text: title,
            textAlign: TextAlign.center,
            style: theme.titleStyle(
              fontSize: titleFontSize,
              color: theme.museumTitleColor,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme
                .titleStyle(fontSize: subtitleFontSize + 1)
                .copyWith(
                  // Soft parchment-gold — less white than the title.
                  color: const Color(0xFFD8C4A0),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  height: 1.25,
                ),
          ),
        ],
      ],
    );

    if (trailing == null) return titleBlock;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 8),
        trailing!,
      ],
    );
  }
}
