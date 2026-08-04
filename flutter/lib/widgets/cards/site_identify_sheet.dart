import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../models/site_field.dart';
import '../../services/site_service.dart';
import '../../utils/display_text.dart';
import 'site_card_image.dart';

/// Bottom sheet: period then rock-type identification quiz for a field site.
Future<SiteSummary?> showSiteIdentifySheet(
  BuildContext context, {
  required SiteSummary site,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<SiteSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SiteIdentifySheet(site: site),
  );
}

class SiteIdentifySheet extends StatefulWidget {
  const SiteIdentifySheet({super.key, required this.site});

  final SiteSummary site;

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
  SiteSummary? _latestSite;

  @override
  void initState() {
    super.initState();
    _latestSite = widget.site;
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
        Navigator.of(context).pop(_latestSite);
        return;
      }
      setState(() {
        _options = options;
        _loading = false;
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

      _latestSite = result.site;

      if (result.identified) {
        if (!mounted) return;
        Navigator.of(context).pop(result.site);
        return;
      }

      // Advance to rock-type step.
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final options = _options;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: SiteCardImage(imageUrl: widget.site.mainImageUrl),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _question,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: scheme.primary),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                )
              else if (options != null)
                for (final choice in options.choices) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _IdentifyChoiceButton(
                      label: toTitleCase(choice),
                      disabled: _disabled.contains(choice) || _submitting,
                      onPressed: () => _onGuess(choice),
                    ),
                  ),
                ],
              if (_message != null) ...[
                const SizedBox(height: 4),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: _message!.startsWith('Correct')
                        ? scheme.primary
                        : scheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentifyChoiceButton extends StatelessWidget {
  const _IdentifyChoiceButton({
    required this.label,
    required this.disabled,
    required this.onPressed,
  });

  final String label;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
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
