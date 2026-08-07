import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/geologic_timeline_constants.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../utils/curated_image_url.dart';
import '../../utils/display_text.dart';
import '../../utils/network_image_mem_cache.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../common/drawer_sheet_sizes.dart';
import 'card_detail_sheet.dart';
import 'site_card_image.dart';
import '../../features/notifications/notifications.dart';

/// Bottom sheet: period then rock-type identification quiz for a field site.
///
/// On a successful full identification, dismisses any underlying [CardDetailSheet]
/// site card, then shows the site-identified celebration.
Future<SiteSummary?> showSiteIdentifySheet(
  BuildContext context, {
  required SiteSummary site,
}) async {
  final rootNav = Navigator.of(context, rootNavigator: true);
  final completion = await showModalBottomSheet<_IdentifyCompletion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableSheetWrapper(
      initialChildSize: DrawerSheetSizes.initialChildSize,
      minChildSize: DrawerSheetSizes.minChildSize,
      maxChildSize: DrawerSheetSizes.maxChildSize,
      childBuilder: (scrollController) =>
          SiteIdentifySheet(site: site, scrollController: scrollController),
    ),
  );
  if (completion == null) return null;
  final updated = completion.site;

  // Close the site card under the quiz so celebration isn't stacked on it.
  if (context.mounted && CardDetailSheet.isOpen) {
    _syncIdentifiedSite(context, updated);
    CardDetailSheet.dismissMatching(CardDetailIdentity.site(updated.siteId));
    await SchedulerBinding.instance.endOfFrame;
  }

  if (rootNav.mounted) {
    await rootNav.context.read<CelebrationController>().enqueue(
      CelebrationEvent(
        kind: CelebrationKind.siteIdentified,
        siteId: updated.siteId,
        site: updated,
        notificationId: completion.notificationId,
      ),
    );
  } else if (context.mounted) {
    await context.read<CelebrationController>().enqueue(
      CelebrationEvent(
        kind: CelebrationKind.siteIdentified,
        siteId: updated.siteId,
        site: updated,
        notificationId: completion.notificationId,
      ),
    );
  }
  return updated;
}

void _syncIdentifiedSite(BuildContext context, SiteSummary updated) {
  try {
    context.read<map_data.MapController>().upsertSite(updated);
  } on ProviderNotFoundException {
    // Not under the map.
  }
  try {
    context.read<SiteCatalogController>().upsertSite(updated);
  } on ProviderNotFoundException {
    // Not under the catalog.
  }
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
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  /// Instant local correct flash (answer comes with options).
  String? _successGuess;

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
      _disabled.clear();
      _successGuess = null;
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
    if (options == null ||
        _submitting ||
        _successGuess != null ||
        _disabled.contains(guess) ||
        options.answer.isEmpty) {
      return;
    }

    final correct = guess == options.answer;

    if (!correct) {
      HapticFeedback.selectionClick();
      setState(() => _disabled.add(guess));
      await _recordGuess(options: options, guess: guess);
      return;
    }

    // Instant green feedback from local answer, then confirm with API.
    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = true;
      _successGuess = guess;
      _error = null;
    });

    final started = DateTime.now();
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

      if (result.identified) {
        await _holdSuccessAtLeast(started);
        if (!mounted) return;
        Navigator.of(context).pop(
          _IdentifyCompletion(result.site, result.celebration?.notificationId),
        );
        return;
      }

      // Prefetch next step while keeping period correct feedback visible.
      // No spinner between questions — swap when ready, after ≥1s.
      final next = await _service.fetchIdentifyOptions(widget.site.siteId);
      await _holdSuccessAtLeast(started);
      if (!mounted) return;

      if (next.identified) {
        Navigator.of(context).pop(_IdentifyCompletion(result.site, null));
        return;
      }

      setState(() {
        _options = next;
        _submitting = false;
        _successGuess = null;
        _disabled.clear();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _successGuess = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _holdSuccessAtLeast(DateTime started) async {
    const minHold = Duration(seconds: 1);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minHold) {
      await Future<void>.delayed(minHold - elapsed);
    }
  }

  Future<void> _recordGuess({
    required SiteIdentifyOptions options,
    required String guess,
  }) async {
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
    } catch (_) {
      // Local disable already applied; server sync is best-effort for wrongs.
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
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.zero,
              children: [
                // Image flush to the top; drawer handle overlays the photo.
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: SiteCardImage(imageUrl: widget.site.mainImageUrl),
                    ),
                    // Short fade into the question; soft edge, not a long wash.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 48,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.surface.withValues(alpha: 0),
                                scheme.surface.withValues(alpha: 0.45),
                                scheme.surface,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                      highlightPeriod: _successGuess,
                      onChanged: (_submitting || _successGuess != null)
                          ? null
                          : (v) {
                              final prev = _periodForSlider(_periodSlider);
                              final next = _periodForSlider(v);
                              setState(() {
                                _periodSlider = v;
                              });
                              if (prev != next) {
                                HapticFeedback.selectionClick();
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final period = _periodForSlider(_periodSlider);
                      final isWrong = _disabled.contains(period);
                      final isSuccess = _successGuess != null;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            toTitleCase(period),
                            textAlign: TextAlign.center,
                            style: textTheme.headlineSmall?.copyWith(
                              color: isSuccess
                                  ? const Color(0xFF2E7D32)
                                  : isWrong
                                  ? scheme.onSurface.withValues(alpha: 0.45)
                                  : scheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (isWrong && !isSuccess) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.close_rounded,
                              size: 22,
                              color: scheme.error.withValues(alpha: 0.55),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: FilledButton(
                      onPressed:
                          _successGuess != null ||
                              _submitting ||
                              _disabled.contains(
                                _periodForSlider(_periodSlider),
                              )
                          ? null
                          : () => _onGuess(_periodForSlider(_periodSlider)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _successGuess != null
                            ? const Color(0xFF2E7D32)
                            : null,
                        disabledBackgroundColor: _successGuess != null
                            ? const Color(0xFF2E7D32)
                            : null,
                        disabledForegroundColor: _successGuess != null
                            ? Colors.white
                            : null,
                        foregroundColor: _successGuess != null
                            ? Colors.white
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _successGuess != null ? 'Correct!' : 'Confirm period',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ] else if (options != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: options.choices.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.55,
                          ),
                      itemBuilder: (context, index) {
                        final choice = options.choices[index];
                        final isSuccess = _successGuess == choice;
                        return _IdentifyRockTile(
                          label: toTitleCase(choice),
                          imageUrl: options.choiceImages[choice],
                          disabled:
                              _disabled.contains(choice) ||
                              _submitting ||
                              (_successGuess != null && !isSuccess),
                          correct: isSuccess,
                          wrong: _disabled.contains(choice),
                          onPressed: () => _onGuess(choice),
                        );
                      },
                    ),
                  ),
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

class _IdentifyCompletion {
  const _IdentifyCompletion(this.site, this.notificationId);
  final SiteSummary site;
  final int? notificationId;
}

/// Maps slider 0→1 (left older → right younger) to a Mesozoic period key.
String _periodForSlider(double t) {
  // Left (t=0) = 252 Ma, right (t=1) = 66 Ma.
  final age =
      mesozoicOlderMa -
      t.clamp(0.0, 1.0) * (mesozoicOlderMa - mesozoicYoungerMa);
  if (age > 201) return 'triassic';
  if (age > 145) return 'jurassic';
  return 'cretaceous';
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({
    required this.label,
    required this.muted,
    required this.highlighted,
    required this.wrong,
  });

  final String label;
  final Color muted;
  final bool highlighted;
  final bool wrong;

  static const _successGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? _successGreen
        : wrong
        ? muted.withValues(alpha: 0.45)
        : muted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (wrong) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.close_rounded,
            size: 12,
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
  }
}

class _PeriodTimelineSlider extends StatelessWidget {
  const _PeriodTimelineSlider({
    required this.value,
    required this.disabledPeriods,
    required this.onChanged,
    this.highlightPeriod,
  });

  final double value;
  final Set<String> disabledPeriods;
  final ValueChanged<double>? onChanged;
  final String? highlightPeriod;

  static const _boundaries = [252.0, 201.0, 145.0, 66.0];
  static const _periods = [
    (key: 'triassic', label: 'Triassic', start: 252.0, end: 201.0),
    (key: 'jurassic', label: 'Jurassic', start: 201.0, end: 145.0),
    (key: 'cretaceous', label: 'Cretaceous', start: 145.0, end: 66.0),
  ];
  static const _successGreen = Color(0xFF2E7D32);

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
        const thumbSize = 36.0;
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
                  left:
                      sidePad +
                      _tForMa((period.start + period.end) / 2) * trackWidth -
                      44,
                  top: 2,
                  width: 88,
                  child: _PeriodLabel(
                    label: period.label,
                    muted: muted,
                    highlighted: highlightPeriod == period.key,
                    wrong: disabledPeriods.contains(period.key),
                  ),
                ),
              // Ma-proportional period track.
              for (var i = 0; i < _periods.length; i++)
                Positioned(
                  left: sidePad + _tForMa(_periods[i].start) * trackWidth,
                  top: barTop,
                  width:
                      (_tForMa(_periods[i].end) - _tForMa(_periods[i].start)) *
                      trackWidth,
                  height: barHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highlightPeriod == _periods[i].key
                          ? _successGreen
                          : disabledPeriods.contains(_periods[i].key)
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
                          final local = box.globalToLocal(
                            details.globalPosition,
                          );
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
              // Drag thumb (sized to avoid covering period / Ma labels).
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
                      border: Border.all(color: scheme.primary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.24),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
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

class _IdentifyRockTile extends StatelessWidget {
  const _IdentifyRockTile({
    required this.label,
    required this.disabled,
    required this.onPressed,
    this.imageUrl,
    this.correct = false,
    this.wrong = false,
  });

  final String label;
  final String? imageUrl;
  final bool disabled;
  final bool correct;
  final bool wrong;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Preserve the native aspect ratio while filling the tile; crop overflow
    // instead of stretching or letterboxing the image.
    final url = imageUrl?.trim();
    final hasImage =
        url != null && url.isNotEmpty && isCuratedSiteTypeImageUrl(url);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled || correct ? null : onPressed,
        child: Opacity(
          opacity: disabled && !correct ? 0.42 : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      memCacheWidth: networkImageMemCacheExtent(
                        constraints.maxWidth,
                        dpr,
                      ),
                      memCacheHeight: networkImageMemCacheExtent(
                        constraints.maxHeight,
                        dpr,
                      ),
                      httpHeaders: const {
                        'User-Agent':
                            'Mesozoica/1.0 (mobile app; site identify)',
                      },
                      placeholder: (context, _) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                      errorWidget: (context, _, error) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.landscape_outlined,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    );
                  },
                )
              else
                ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.landscape_outlined,
                    size: 36,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                ),
              // Bottom scrim so the name stays readable on any photo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x66000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.35, 0.7, 1],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  correct ? 'Correct!' : label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: correct ? const Color(0xFFB9F6CA) : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: correct ? 17 : 15,
                    height: 1.15,
                    letterSpacing: 0.15,
                    shadows: const [
                      Shadow(
                        color: Color(0xE6000000),
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              if (correct) ...[
                const ColoredBox(color: Color(0x552E7D32)),
                const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 48,
                    shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
                  ),
                ),
              ] else if (wrong) ...[
                ColoredBox(color: scheme.error.withValues(alpha: 0.16)),
                Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.82),
                    shadows: const [
                      Shadow(color: Color(0x99000000), blurRadius: 8),
                    ],
                  ),
                ),
              ] else if (disabled)
                ColoredBox(color: scheme.surface.withValues(alpha: 0.28)),
              if (correct)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF2E7D32),
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
              Icon(Icons.travel_explore, size: 15, color: Color(0xFF2A2620)),
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
