import 'package:flutter/material.dart';

/// Large card title that stays on one line when possible by scaling down,
/// and only wraps when it would need to shrink too far.
class CardAdaptiveTitleText extends StatelessWidget {
  const CardAdaptiveTitleText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.minScale = 0.72,
    this.maxLinesWhenWrapped = 2,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final double minScale;
  final int maxLinesWhenWrapped;

  Alignment get _fitAlignment {
    return switch (textAlign) {
      TextAlign.end => Alignment.centerRight,
      TextAlign.start => Alignment.centerLeft,
      _ => Alignment.center,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLinesWhenWrapped,
            overflow: TextOverflow.ellipsis,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout(maxWidth: maxWidth);

        if (painter.width <= maxWidth) {
          return Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: 1,
          );
        }

        final scale = maxWidth / painter.width;
        if (scale >= minScale) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _fitAlignment,
            child: Text(
              text,
              style: style,
              textAlign: textAlign,
              maxLines: 1,
              softWrap: false,
            ),
          );
        }

        return Text(
          text,
          style: style,
          textAlign: textAlign,
          maxLines: maxLinesWhenWrapped,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
