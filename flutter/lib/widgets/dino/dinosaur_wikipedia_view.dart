import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../services/wikipedia_revision_service.dart';

/// Builds the canonical en.wikipedia.org article URL for a Wikipedia title.
Uri wikipediaArticleUri(String title, {int? oldId}) {
  final slug = title.trim().replaceAll(' ', '_');
  if (oldId == null) {
    return Uri.https('en.wikipedia.org', '/wiki/$slug');
  }
  return Uri.https('en.wikipedia.org', '/w/index.php', {
    'title': slug,
    'oldid': '$oldId',
  });
}

/// Mobile Wikipedia URL — better fit for an in-app drawer.
Uri wikipediaMobileArticleUri(String title, {int? oldId}) {
  final slug = title.trim().replaceAll(' ', '_');
  if (oldId == null) {
    return Uri.https('en.m.wikipedia.org', '/wiki/$slug');
  }
  return Uri.https('en.m.wikipedia.org', '/w/index.php', {
    'title': slug,
    'oldid': '$oldId',
  });
}

/// Label for a historical Wikipedia snapshot date.
String? wikipediaAsOfLabel(DateTime? insertDate) {
  if (insertDate == null) return null;
  final local = insertDate.toLocal();
  final formatted = DateFormat.yMMMMd().format(local);
  return 'Wikipedia as of $formatted';
}

/// Shown when historical revision lookup fails.
const wikipediaLiveFallbackWarning =
    'Historical version unavailable — showing current page';

/// Embeds a Wikipedia mobile article (optionally a historical revision).
class DinosaurWikipediaView extends StatefulWidget {
  const DinosaurWikipediaView({
    super.key,
    required this.wikipediaTitle,
    this.asOf,
    this.preferDark = false,
    this.revisionService,
  });

  final String wikipediaTitle;

  /// When set, load the page revision current as of this timestamp.
  final DateTime? asOf;

  final bool preferDark;

  /// Injectable for tests; defaults to a live Wikipedia lookup.
  final WikipediaRevisionService? revisionService;

  @override
  State<DinosaurWikipediaView> createState() => _DinosaurWikipediaViewState();
}

class _DinosaurWikipediaViewState extends State<DinosaurWikipediaView> {
  late final WebViewController _controller;
  late final WikipediaRevisionService _revisionService;
  var _loading = true;
  var _hasError = false;
  var _chromeTrimmed = false;
  int? _oldId;
  var _usedLiveFallback = false;
  var _injectStatusOnNextFinish = false;

  Uri get _pageUri =>
      wikipediaMobileArticleUri(widget.wikipediaTitle, oldId: _oldId);

  Uri get _desktopUri =>
      wikipediaArticleUri(widget.wikipediaTitle, oldId: _oldId);

  String? get _statusBannerText {
    if (widget.asOf == null && !_usedLiveFallback) return null;
    if (_usedLiveFallback) return wikipediaLiveFallbackWarning;
    return wikipediaAsOfLabel(widget.asOf);
  }

  @override
  void initState() {
    super.initState();
    _revisionService = widget.revisionService ?? WikipediaRevisionService();

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
            if (_injectStatusOnNextFinish) {
              await _injectStatusBanner();
              _injectStatusOnNextFinish = false;
            }
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
      );

    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      // Native iOS edge-swipe back/forward through WebView history.
      platform.setAllowsBackForwardNavigationGestures(true);
    }

    _loadArticle();
  }

  Future<void> _loadArticle() async {
    final asOf = widget.asOf;
    _usedLiveFallback = false;
    _injectStatusOnNextFinish = false;
    if (asOf != null) {
      try {
        _oldId = await _revisionService.revisionAsOf(
          title: widget.wikipediaTitle,
          asOf: asOf,
        );
      } catch (_) {
        _oldId = null;
      }
      _usedLiveFallback = _oldId == null;
      _injectStatusOnNextFinish = true;
    } else {
      _oldId = null;
    }
    if (!mounted) return;
    await _controller.loadRequest(_pageUri);
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
    #mesozoica-wiki-status {
      display: block !important;
      font-size: 14px !important;
      line-height: 1.4 !important;
      font-weight: 500 !important;
      margin: 4px 0 14px 0 !important;
      padding: 0 !important;
      color: #5c6670 !important;
    }
    #mesozoica-wiki-status.is-warning {
      color: #c62828 !important;
    }
    .skin-theme-clientpref-night #mesozoica-wiki-status {
      color: #b0b8c0 !important;
    }
    .skin-theme-clientpref-night #mesozoica-wiki-status.is-warning {
      color: #ef9a9a !important;
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

  Future<void> _injectStatusBanner() async {
    final text = _statusBannerText;
    if (text == null) return;
    final warning = _usedLiveFallback;
    final literal = jsonEncode(text);
    try {
      // Retry: Minerva often hydrates content after the first page-finished.
      for (var attempt = 0; attempt < 6; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
        }
        if (!mounted) return;
        final result = await _controller.runJavaScriptReturningResult('''
(function () {
  var text = $literal;
  var warning = ${warning ? 'true' : 'false'};
  var existing = document.getElementById('mesozoica-wiki-status');
  if (existing) existing.remove();

  var banner = document.createElement('p');
  banner.id = 'mesozoica-wiki-status';
  if (warning) banner.className = 'is-warning';
  banner.textContent = text;

  var hosts = [
    document.querySelector('.mw-parser-output'),
    document.querySelector('.mw-body-content'),
    document.querySelector('#bodyContent'),
    document.querySelector('#content'),
    document.querySelector('.mw-body'),
    document.querySelector('.content'),
    document.querySelector('main'),
    document.body
  ];
  var host = null;
  for (var i = 0; i < hosts.length; i++) {
    if (hosts[i]) { host = hosts[i]; break; }
  }
  if (!host) return 'no-host';

  // Prefer inserting above the article title when present.
  var title = host.querySelector('h1, .page-heading, .mw-first-heading');
  if (title && title.parentElement) {
    title.parentElement.insertBefore(banner, title);
  } else {
    host.insertBefore(banner, host.firstChild);
  }
  return document.getElementById('mesozoica-wiki-status') ? 'ok' : 'missing';
})();
''');
        final ok = result.toString().contains('ok');
        if (ok) return;
      }
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
    _loadArticle();
  }

  Future<void> _openInBrowser() async {
    await launchUrl(_desktopUri, mode: LaunchMode.externalApplication);
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
