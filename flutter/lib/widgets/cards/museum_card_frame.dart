import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';
import 'card_back_backdrop.dart';
import 'card_back_corner_actions.dart';
import 'museum_card_icons.dart';

/// Shared museum plaque: sharp hero, serif title, optional age bar, panels.
class MuseumCardFrame extends StatelessWidget {
  const MuseumCardFrame({
    super.key,
    required this.image,
    required this.title,
    required this.panels,
    required this.onHistory,
    this.subtitle,
    this.emblem = MuseumGlyph.skull,
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
  final MuseumGlyph emblem;
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
                final top = constraints.maxHeight * 0.355;
                return Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MuseumTitle(
                        title: title,
                        subtitle: showSubtitle ? subtitleText : null,
                        emblem: emblem,
                        trailing: trailing,
                        titleFontSize: titleFontSize,
                        subtitleFontSize: subtitleFontSize,
                        theme: theme,
                      ),
                      if (timeline != null) ...[
                        const SizedBox(height: 6),
                        SizedBox(height: 50, child: timeline),
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
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(decoration: theme.museumHairlineDecoration()),
            ),
          ),
        ],
      ),
    );
  }
}

class MuseumPanelRow extends StatelessWidget {
  const MuseumPanelRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }
}

class _MuseumTitle extends StatelessWidget {
  const _MuseumTitle({
    required this.title,
    required this.subtitle,
    required this.emblem,
    required this.trailing,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.theme,
  });

  final String title;
  final String? subtitle;
  final MuseumGlyph emblem;
  final Widget? trailing;
  final double titleFontSize;
  final double subtitleFontSize;
  final DinoCardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MuseumGlyphIcon(glyph: emblem, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardAdaptiveTitleText(
                text: title,
                textAlign: TextAlign.start,
                style: theme.titleStyle(
                  fontSize: titleFontSize,
                  color: theme.museumTitleColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .titleStyle(
                        fontSize: subtitleFontSize,
                        color: theme.cardAccent,
                      )
                      .copyWith(
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.2,
                        height: 1.2,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}
