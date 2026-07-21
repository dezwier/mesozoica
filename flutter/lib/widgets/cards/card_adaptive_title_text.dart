import 'package:flutter/material.dart';

/// Card title at [style.fontSize] that scales down to fit the available width.
class CardAdaptiveTitleText extends StatelessWidget {
  const CardAdaptiveTitleText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int maxLines;

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
        final title = Text(
          text,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          softWrap: maxLines > 1,
          overflow: TextOverflow.ellipsis,
        );

        if (!maxWidth.isFinite || maxWidth <= 0) {
          return title;
        }

        return SizedBox(
          width: maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _fitAlignment,
            child: title,
          ),
        );
      },
    );
  }
}
