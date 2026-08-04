import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../models/site_field.dart';
import '../../services/site_service.dart';
import '../../utils/display_text.dart';

/// Bottom sheet: period then rock-type identification quiz for a field site.
Future<SiteSummary?> showSiteIdentifySheet(
  BuildContext context, {
  required SiteSummary site,
}) {
  return showModalBottomSheet<SiteSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF2A2620),
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
  int _totalXp = 0;

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

      _totalXp += result.xpAwarded;
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
        _message = result.xpAwarded > 0
            ? 'Correct! +${result.xpAwarded} XP'
            : 'Correct!';
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final options = _options;
    final stepLabel = options?.step == 'rock_type'
        ? 'What rock type is this site?'
        : 'Which period is this site from?';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x66F5F0E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Identify site',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFF5F0E8),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            stepLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xCCF5F0E8),
                ),
          ),
          if (_totalXp > 0) ...[
            const SizedBox(height: 4),
            Text(
              'XP earned: $_totalXp',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFB8D4A8),
                  ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFF5F0E8)),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE8A0A0)),
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
              style: TextStyle(
                color: _message!.startsWith('Correct')
                    ? const Color(0xFFB8D4A8)
                    : const Color(0xFFE8C49A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
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
    return OutlinedButton(
      onPressed: disabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF5F0E8),
        disabledForegroundColor: const Color(0x66F5F0E8),
        side: BorderSide(
          color: disabled
              ? const Color(0x33F5F0E8)
              : const Color(0x99F5F0E8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }
}
