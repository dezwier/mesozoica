import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/geologic_timeline_constants.dart';
import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../utils/curated_image_url.dart';
import '../../utils/display_text.dart';
import '../../utils/network_image_mem_cache.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../common/drawer_sheet_sizes.dart';
import 'site_card_image.dart';
import 'site_discovery_celebration.dart';

/// Bottom sheet: period then rock-type identification quiz for a field site.
///
/// On a successful full identification, shows the "Site identified!" celebration
/// before returning the updated site.
Future<SiteSummary?> showSiteIdentifySheet(
  BuildContext context, {
  required SiteSummary site,
}) async {
  final updated = await showModalBottomSheet<SiteSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableSheetWrapper(
      initialChildSize: DrawerSheetSizes.initialChildSize,
      minChildSize: DrawerSheetSizes.minChildSize,
      maxChildSize: DrawerSheetSizes.maxChildSize,
      childBuilder: (scrollController) => SiteIdentifySheet(
        site: site,
        scrollController: scrollController,
      ),
    ),
  );
  if (updated != null && context.mounted) {
    await showSiteIdentifiedCelebration(context, site: updated);
  }
  return updated;
}

class SiteIdentifySheet extends StatefulWidget {
  const SiteIdentifySheet({
    super.key,
    required this.site,
    required this.scrollController,
  });

  final SiteSummary site;
  final ScrollController scrollController;

  @override
  State<SiteIdentifySheet> createState() => _SiteIdentifySheetState();
}

class _SiteIdentifySheetState extends State<SiteIdentifySheet> {
  final _service = SiteService();
  SiteIdentifyOptions? _options;
  final Set<String> _disabled = {};
  String? _message;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  /// 0 = oldest (252 Ma / Triassic left), 1 = youngest (66 Ma / Cretaceous right).
  double _periodSlider = 0.5;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _disabled.clear();
    });
    try {
      final options = await _service.fetchIdentifyOptions(widget.site.siteId);
      if (!mounted) return;
      if (options.identified) {
        // Nothing left to do; do not trigger the post-quiz celebration.
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _options = options;
        _loading = false;
        if (options.step == 'period') {
          _periodSlider = 0.5;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onGuess(String guess) async {
    final options = _options;
    if (options == null || _submitting || _disabled.contains(guess)) return;
    setState(() {
      _submitting = true;
      _message = null;
      _error = null;
    });
    try {
      final result = await _service.submitIdentifyGuess(
        siteId: widget.site.siteId,
        step: options.step,
        guess: guess,
      );
      if (!mounted) return;

      try {
        context.read<AuthController>().applyUser(result.profile);
      } on ProviderNotFoundException {
        // Tests / previews without AuthController.
      }

      if (!result.correct) {
        setState(() {
          _submitting = false;
          _disabled.addAll(result.disabledGuesses);
          _message = result.message ?? "That doesn't look quite right";
        });
        return;
      }

      if (result.identified) {
        if (!mounted) return;
        Navigator.of(context).pop(result.site);
        return;
      }

      setState(() {
        _submitting = false;
        _disabled.clear();
        _message = null;
      });
      await _loadOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  String get _question {
    final step = _options?.step;
    if (step == 'rock_type') {
      return 'Which rock type do you see?';
    }
    return 'From which period would you say this site is?';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final options = _options;
    final isPeriod = options?.step == 'period';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 10),
                AspectRatio(
                  aspectRatio: 1,
                  child: SiteCardImage(imageUrl: widget.site.mainImageUrl),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    _question,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: CircularProgressIndicator(color: scheme.primary),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  )
                else if (options != null && isPeriod) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _PeriodTimelineSlider(
                      value: _periodSlider,
                      disabledPeriods: _disabled,
                      onChanged: _submitting
                          ? null
                          : (v) {
                              final prev = _periodForSlider(_periodSlider);
                              final next = _periodForSlider(v);
                              setState(() {
                                _periodSlider = v;
                                _message = null;
                              });
                              if (prev != next) {
                                HapticFeedback.selectionClick();
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    toTitleCase(_periodForSlider(_periodSlider)),
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      color: _disabled.contains(_periodForSlider(_periodSlider))
                          ? scheme.onSurface.withValues(alpha: 0.38)
                          : scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: FilledButton(
                      onPressed: _submitting ||
                              _disabled.contains(_periodForSlider(_periodSlider))
                          ? null
                          : () => _onGuess(_periodForSlider(_periodSlider)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _submitting ? 'Checking…' : 'Confirm period',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ] else if (options != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(
                      children: [
                        for (final choice in options.choices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _IdentifyChoiceButton(
                              label: toTitleCase(choice),
                              imageUrl: options.choiceImages[choice],
                              disabled:
                                  _disabled.contains(choice) || _submitting,
                              onPressed: () => _onGuess(choice),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps slider 0→1 (left older → right younger) to a Mesozoic period key.
String _periodForSlider(double t) {
  // Left (t=0) = 252 Ma, right (t=1) = 66 Ma.
  final age = mesozoicOlderMa -
      t.clamp(0.0, 1.0) * (mesozoicOlderMa - mesozoicYoungerMa);
  if (age > 201) return 'triassic';
  if (age > 145) return 'jurassic';
  return 'cretaceous';
}

class _PeriodTimelineSlider extends StatelessWidget {
  const _PeriodTimelineSlider({
    required this.value,
    required this.disabledPeriods,
    required this.onChanged,
  });

  final double value;
  final Set<String> disabledPeriods;
  final ValueChanged<double>? onChanged;

  static const _boundaries = [252.0, 201.0, 145.0, 66.0];
  static const _periods = [
    (key: 'triassic', label: 'Triassic', start: 252.0, end: 201.0),
    (key: 'jurassic', label: 'Jurassic', start: 201.0, end: 145.0),
    (key: 'cretaceous', label: 'Cretaceous', start: 145.0, end: 66.0),
  ];

  /// Slider t: 0 = oldest (252 Ma, left), 1 = youngest (66 Ma, right).
  double _tForMa(double ma) =>
      (mesozoicOlderMa - ma) / (mesozoicOlderMa - mesozoicYoungerMa);

  void _setFromLocalDx(double dx, double sidePad, double trackWidth) {
    if (onChanged == null || trackWidth <= 0) return;
    onChanged!(((dx - sidePad) / trackWidth).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        const sidePad = 16.0;
        const thumbSize = 56.0;
        const barHeight = 10.0;
        const barTop = 36.0;
        final trackWidth = constraints.maxWidth - sidePad * 2;
        final t = value.clamp(0.0, 1.0);
        final thumbLeft = sidePad + t * trackWidth - thumbSize / 2;

        return SizedBox(
          height: 118,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Period labels above the bar (timeline style).
              for (final period in _periods)
                Positioned(
                  left: sidePad +
                      _tForMa((period.start + period.end) / 2) * trackWidth -
                      40,
                  top: 4,
                  width: 80,
                  child: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: disabledPeriods.contains(period.key)
                          ? muted.withValues(alpha: 0.35)
                          : muted,
                    ),
                  ),
                ),
              // Ma-proportional period track.
              for (var i = 0; i < _periods.length; i++)
                Positioned(
                  left: sidePad + _tForMa(_periods[i].start) * trackWidth,
                  top: barTop,
                  width: (_tForMa(_periods[i].end) - _tForMa(_periods[i].start)) *
                      trackWidth,
                  height: barHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: disabledPeriods.contains(_periods[i].key)
                          ? scheme.outlineVariant.withValues(alpha: 0.35)
                          : scheme.primary.withValues(alpha: 0.22 + i * 0.14),
                      borderRadius: BorderRadius.horizontal(
                        left: i == 0 ? const Radius.circular(5) : Radius.zero,
                        right: i == _periods.length - 1
                            ? const Radius.circular(5)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              // Boundary markers (ticks between periods + ends).
              for (final ma in _boundaries)
                Positioned(
                  left: sidePad + _tForMa(ma) * trackWidth - 1,
                  top: barTop - 5,
                  child: Container(
                    width: 2,
                    height: barHeight + 10,
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              // Ma labels under the bar.
              for (final ma in _boundaries)
                Positioned(
                  left: ma == mesozoicOlderMa
                      ? sidePad - 2
                      : ma == mesozoicYoungerMa
                          ? null
                          : sidePad + _tForMa(ma) * trackWidth - 22,
                  right: ma == mesozoicYoungerMa ? sidePad - 2 : null,
                  top: barTop + barHeight + 10,
                  width: ma == mesozoicOlderMa || ma == mesozoicYoungerMa
                      ? null
                      : 44,
                  child: Text(
                    '${ma.round()} Ma',
                    textAlign: ma == mesozoicYoungerMa
                        ? TextAlign.right
                        : ma == mesozoicOlderMa
                            ? TextAlign.left
                            : TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      color: muted.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              // Full-area drag hit target.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: onChanged == null
                      ? null
                      : (details) {
                          final box = context.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local =
                              box.globalToLocal(details.globalPosition);
                          _setFromLocalDx(local.dx, sidePad, trackWidth);
                        },
                  onTapDown: onChanged == null
                      ? null
                      : (details) {
                          _setFromLocalDx(
                            details.localPosition.dx,
                            sidePad,
                            trackWidth,
                          );
                          HapticFeedback.selectionClick();
                        },
                  child: const SizedBox.expand(),
                ),
              ),
              // Big comfy thumb.
              Positioned(
                left: thumbLeft,
                top: barTop + barHeight / 2 - thumbSize / 2,
                child: IgnorePointer(
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surface,
                      border: Border.all(color: scheme.primary, width: 3.5),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 28,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IdentifyChoiceButton extends StatelessWidget {
  const _IdentifyChoiceButton({
    required this.label,
    required this.disabled,
    required this.onPressed,
    this.imageUrl,
  });

  final String label;
  final String? imageUrl;
  final bool disabled;
  final VoidCallback onPressed;

  static const _avatarSize = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final albumUrl = albumImageUrlFromCurated(imageUrl) ?? imageUrl;
    return OutlinedButton(
      onPressed: disabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        disabledBackgroundColor:
            scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        side: BorderSide(
          color: disabled
              ? scheme.outlineVariant
              : scheme.outline.withValues(alpha: 0.7),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: disabled ? 0.4 : 1,
            child: _RockChoiceAvatar(
              imageUrl: albumUrl,
              size: _avatarSize,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RockChoiceAvatar extends StatelessWidget {
  const _RockChoiceAvatar({
    required this.imageUrl,
    required this.size,
  });

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.landscape_outlined,
        size: size * 0.42,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );

    Widget child;
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty || !isCuratedSiteTypeImageUrl(url)) {
      child = placeholder;
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        memCacheWidth: networkImageMemCacheExtent(size, dpr),
        memCacheHeight: networkImageMemCacheExtent(size, dpr),
        httpHeaders: const {
          'User-Agent': 'Mesozoica/1.0 (mobile app; site identify)',
        },
        placeholder: (context, _) => placeholder,
        errorWidget: (context, _, error) => placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// Compact cream chip used next to the card title on front and back.
class SiteIdentifyTitleButton extends StatelessWidget {
  const SiteIdentifyTitleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE6F5F0E8),
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore,
                size: 15,
                color: Color(0xFF2A2620),
              ),
              SizedBox(width: 5),
              Text(
                'Identify',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A2620),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
