import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dinosaur_article_widget_factory.dart';

class DinosaurArticleHtmlView extends StatelessWidget {
  const DinosaurArticleHtmlView({
    super.key,
    required this.html,
    this.scrollController,
  });

  final String html;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.55,
      color: colorScheme.onSurface,
    );

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: HtmlWidget(
            html,
            baseUrl: Uri.parse('https://en.wikipedia.org/'),
            textStyle: bodyStyle,
            renderMode: RenderMode.sliverList,
            factoryBuilder: DinosaurArticleWidgetFactory.new,
            onTapUrl: _launchUrl,
            customStylesBuilder: (element) =>
                _styleForElement(element.localName, element.classes, colorScheme),
          ),
        ),
      ],
    );
  }

  static Map<String, String>? _styleForElement(
    String? tagName,
    Iterable<String> classes,
    ColorScheme colorScheme,
  ) {
    switch (tagName) {
      case 'h2':
        return {
          'font-size': '20px',
          'font-weight': '700',
          'margin-top': '20px',
          'margin-bottom': '8px',
          'color': _colorToCss(colorScheme.onSurface),
        };
      case 'h3':
        return {
          'font-size': '17px',
          'font-weight': '600',
          'margin-top': '16px',
          'margin-bottom': '6px',
          'color': _colorToCss(colorScheme.onSurface),
        };
      case 'table':
        if (classes.contains('infobox')) {
          return {
            'width': '100%',
            'font-size': '13px',
            'border-collapse': 'collapse',
            'margin-bottom': '16px',
            'background-color': _colorToCss(
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ),
          };
        }
        return {
          'width': '100%',
          'font-size': '13px',
          'border-collapse': 'collapse',
          'margin-bottom': '12px',
        };
      case 'th':
        return {
          'text-align': 'left',
          'padding': '4px 8px',
          'vertical-align': 'top',
          'font-weight': '600',
        };
      case 'td':
        return {
          'padding': '4px 8px',
          'vertical-align': 'top',
        };
      case 'a':
        return {
          'color': _colorToCss(colorScheme.primary),
          'text-decoration': 'none',
        };
      case 'img':
        return {
          'max-width': '100%',
          'height': 'auto',
          'border-radius': '8px',
          'margin-top': '8px',
          'margin-bottom': '8px',
        };
      case 'figure':
        return {
          'margin-top': '12px',
          'margin-bottom': '12px',
        };
      case 'figcaption':
        return {
          'font-size': '12px',
          'color': _colorToCss(colorScheme.onSurfaceVariant),
          'margin-top': '4px',
        };
      default:
        return null;
    }
  }

  static String _colorToCss(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  static Future<bool> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
