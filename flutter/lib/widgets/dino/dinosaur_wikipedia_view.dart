import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Builds the canonical en.wikipedia.org article URL for a Wikipedia title.
Uri wikipediaArticleUri(String title) {
  final slug = title.trim().replaceAll(' ', '_');
  return Uri.https('en.wikipedia.org', '/wiki/$slug');
}

/// Mobile Wikipedia URL — better fit for an in-app drawer.
Uri wikipediaMobileArticleUri(String title) {
  final slug = title.trim().replaceAll(' ', '_');
  return Uri.https('en.m.wikipedia.org', '/wiki/$slug');
}

/// Embeds the live Wikipedia mobile article, with chrome stripped for reading.
class DinosaurWikipediaView extends StatefulWidget {
  const DinosaurWikipediaView({
    super.key,
    required this.wikipediaTitle,
    this.preferDark = false,
  });

  final String wikipediaTitle;
  final bool preferDark;

  @override
  State<DinosaurWikipediaView> createState() => _DinosaurWikipediaViewState();
}

class _DinosaurWikipediaViewState extends State<DinosaurWikipediaView> {
  late final WebViewController _controller;
  var _loading = true;
  var _hasError = false;
  var _chromeTrimmed = false;

  Uri get _pageUri => wikipediaMobileArticleUri(widget.wikipediaTitle);

  @override
  void initState() {
    super.initState();

    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
        widget.preferDark ? const Color(0xFF101418) : const Color(0xFFFFFFFF),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _hasError = false;
              _chromeTrimmed = false;
            });
          },
          onPageFinished: (_) async {
            await _trimWikipediaChrome();
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Ignore subframe / image failures; only surface main-frame errors.
            if (error.isForMainFrame != true) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _hasError = true;
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (_isWikipediaHost(uri.host)) {
              return NavigationDecision.navigate;
            }
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(_pageUri);

    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      // Native iOS edge-swipe back/forward through WebView history.
      platform.setAllowsBackForwardNavigationGestures(true);
    }
  }

  Future<void> _goBackIfPossible() async {
    if (!await _controller.canGoBack()) return;
    await _controller.goBack();
  }

  static bool _isWikipediaHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'wikipedia.org' ||
        lower.endsWith('.wikipedia.org') ||
        lower == 'wikimedia.org' ||
        lower.endsWith('.wikimedia.org') ||
        lower == 'wikidata.org' ||
        lower.endsWith('.wikidata.org');
  }

  Future<void> _trimWikipediaChrome() async {
    if (_chromeTrimmed) return;
    _chromeTrimmed = true;
    final darkJs = widget.preferDark
        ? '''
  document.documentElement.classList.add('skin-theme-clientpref-night');
  document.body.classList.add('skin-theme-clientpref-night');
'''
        : '';
    try {
      await _controller.runJavaScript('''
(function () {
$darkJs
  var css = `
    .header-container,
    .minerva-header,
    .heading-holder .page-actions-menu,
    #mw-mf-page-left,
    .mw-footer,
    .banner-container,
    .noprint,
    .mw-editsection,
    .page-actions-menu,
    .last-modified-bar,
    .post-content > .mw-cite-backlink {
      display: none !important;
    }
    .mw-body, .content, #content, .mw-parser-output {
      margin-top: 0 !important;
      padding-top: 8px !important;
    }
    body {
      padding-top: 0 !important;
    }
  `;
  var style = document.getElementById('mesozoica-wiki-embed');
  if (!style) {
    style = document.createElement('style');
    style.id = 'mesozoica-wiki-embed';
    document.head.appendChild(style);
  }
  style.textContent = css;
})();
''');
    } catch (_) {
      // Page may have navigated away; ignore injection failures.
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _hasError = false;
      _chromeTrimmed = false;
    });
    _controller.loadRequest(_pageUri);
  }

  Future<void> _openInBrowser() async {
    await launchUrl(
      wikipediaArticleUri(widget.wikipediaTitle),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _WikipediaMessagePane(
        icon: Icons.cloud_off_outlined,
        message: 'Could not load the Wikipedia page.',
        actionLabel: 'Retry',
        onAction: _retry,
        secondaryLabel: 'Open in browser',
        onSecondary: _openInBrowser,
      );
    }

    // iOS uses WKWebView's native back/forward swipe. Elsewhere, a left-edge
    // drag goes back in history.
    final useEdgeSwipeBack =
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS;

    return Stack(
      children: [
        WebViewWidget(
          controller: _controller,
          // Claim vertical drags so parent sheets/scrollables don't steal them.
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<VerticalDragGestureRecognizer>(
              VerticalDragGestureRecognizer.new,
            ),
          },
        ),
        if (useEdgeSwipeBack)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 250) {
                  _goBackIfPossible();
                }
              },
            ),
          ),
        if (_loading)
          const ColoredBox(
            color: Colors.transparent,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _WikipediaMessagePane extends StatelessWidget {
  const _WikipediaMessagePane({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
