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

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    final subtitleText = subtitle?.trim();
    final showSubtitle = subtitleText != null && subtitleText.isNotEmpty;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(image: image),
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            bottom: 8,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final top = constraints.maxHeight * 0.15;
                return Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MuseumTitle(
                        title: title,
                        subtitle: showSubtitle ? subtitleText : null,
                        trailing: trailing,
                        titleFontSize: titleFontSize,
                        subtitleFontSize: subtitleFontSize,
                        theme: theme,
                      ),
                      if (timeline != null) ...[
                        const SizedBox(height: 6),
                        MuseumInnerCard(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
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

/// Thin gold edge painted over a card face so the photo cannot cover it.
class MuseumCardHairline extends StatelessWidget {
  const MuseumCardHairline({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: DinoCardTheme.of(context).museumHairlineDecoration(),
      ),
    );
  }
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
    final lip = Color.lerp(gold, const Color(0xFFFFF1D0), 0.42)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lip.withValues(alpha: theme.isLight ? 0.62 : 0.88),
            gold.withValues(alpha: theme.isLight ? 0.24 : 0.34),
            gold.withValues(alpha: theme.isLight ? 0.10 : 0.14),
            gold.withValues(alpha: theme.isLight ? 0.20 : 0.30),
          ],
          stops: const [0.0, 0.14, 0.58, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: theme.isLight ? 0.08 : 0.14),
            blurRadius: 6,
            spreadRadius: -2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(
              0xFF000000,
            ).withValues(alpha: theme.isLight ? 0.05 : 0.22),
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isLight
                  ? const [Color(0xF7FFFFFF), Color(0xEBF4EADF)]
                  : const [Color(0xF21E1814), Color(0xF2100C0A)],
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

/// Left-inset section title tab with a diagonal cut on the right
/// (Attributes / Cladogram plaque labels).
class MuseumSectionTab extends StatelessWidget {
  const MuseumSectionTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = DinoCardTheme.of(context);
    final gold = theme.cardAccent;
    final fill = Color.alphaBlend(
      gold.withValues(alpha: theme.isLight ? 0.10 : 0.16),
      theme.isLight ? const Color(0xE6221C18) : const Color(0xF214100E),
    );

    return CustomPaint(
      painter: _MuseumSectionTabBorderPainter(color: gold),
      child: ClipPath(
        clipper: const _MuseumSectionTabClipper(),
        child: ColoredBox(
          color: fill,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 18, 5),
            child: Text(
              label.toUpperCase(),
              style: theme
                  .sectionLabelStyle(fontSize: 8)
                  .copyWith(
                    color: Color.lerp(gold, const Color(0xFFF5E6C8), 0.35),
                    letterSpacing: 1.6,
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

class _MuseumSectionTabClipper extends CustomClipper<Path> {
  const _MuseumSectionTabClipper();

  static const _cut = 12.0;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - _cut, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _MuseumSectionTabBorderPainter extends CustomPainter {
  const _MuseumSectionTabBorderPainter({required this.color});

  final Color color;

  static const _cut = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - _cut, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MuseumSectionTabBorderPainter oldDelegate) =>
      oldDelegate.color != color;
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
                .bodyStyle(fontSize: subtitleFontSize + 1)
                .copyWith(
                  color: theme.cardTextPrimary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
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
