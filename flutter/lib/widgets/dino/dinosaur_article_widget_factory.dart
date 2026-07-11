import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// HtmlWidget factory tuned for Wikipedia article images.
class DinosaurArticleWidgetFactory extends WidgetFactory {
  static const _maxDisplayDimension = 1200.0;

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final url = _normalizeImageUrl(src.url);
    if (url == null) {
      return null;
    }

    final width = _clampDimension(src.width);
    final height = _clampDimension(src.height);

    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      httpHeaders: const {
        'User-Agent': 'Mesozoica/1.0 (mobile app; dinosaur catalog)',
      },
      errorWidget: (context, _, error) =>
          onErrorBuilder(context, meta, error, src) ?? widget0,
      progressIndicatorBuilder: (context, _, progress) {
        final total = progress.totalSize;
        final value = total != null && total > 0
            ? progress.downloaded / total
            : null;
        return onLoadingBuilder(context, meta, value, src) ?? widget0;
      },
    );

    if (width != null && height != null && width > 0 && height > 0) {
      image = AspectRatio(aspectRatio: width / height, child: image);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxDisplayDimension),
      child: image,
    );
  }

  static String? _normalizeImageUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  static double? _clampDimension(double? value) {
    if (value == null || value <= 0 || value > _maxDisplayDimension) {
      return null;
    }
    return value;
  }
}
