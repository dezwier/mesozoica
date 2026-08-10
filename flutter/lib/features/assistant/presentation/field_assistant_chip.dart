import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/features/assistant/data/assistant_repository.dart';
import 'package:mesozoica/features/assistant/domain/assistant_answer.dart';
import 'package:mesozoica/widgets/map/vintage_guidance_compass.dart';

/// Compact map chrome: tap to expand an AI question field under the profile HUD.
class FieldAssistantChip extends StatefulWidget {
  const FieldAssistantChip({super.key, AssistantRepository? repository})
    : _repository = repository;

  final AssistantRepository? _repository;

  @override
  State<FieldAssistantChip> createState() => _FieldAssistantChipState();
}

class _FieldAssistantChipState extends State<FieldAssistantChip> {
  late final AssistantRepository _repository =
      widget._repository ?? AssistantRepository();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _expanded = false;
  bool _loading = false;
  String? _error;
  AssistantAnswer? _answer;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _collapse() {
    _focusNode.unfocus();
    setState(() {
      _expanded = false;
      _error = null;
    });
  }

  void _expand() {
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
    });

    try {
      final result = await _repository.ask(question);
      if (!mounted) return;
      setState(() {
        _answer = result;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the field assistant.';
        _loading = false;
      });
    }
  }

  Future<void> _openSource(SourceLink source) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: _expanded ? _buildExpanded() : _buildCollapsed(),
      ),
    );
  }

  Widget _buildCollapsed() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _expand,
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: _chipDecoration,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: VintageInstrumentStyle.gold,
                ),
                SizedBox(width: 6),
                Text(
                  'Ask AI',
                  style: TextStyle(
                    color: VintageInstrumentStyle.brassText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: _chipDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: VintageInstrumentStyle.gold,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Field assistant',
                      style: TextStyle(
                        color: VintageInstrumentStyle.brassText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: _loading ? null : _collapse,
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: VintageInstrumentStyle.brassMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !_loading,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 500,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      style: const TextStyle(
                        color: Color(0xFFF8F4EC),
                        fontSize: 13,
                        height: 1.3,
                      ),
                      cursorColor: VintageInstrumentStyle.gold,
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        hintText: 'Ask about dinosaurs…',
                        hintStyle: TextStyle(
                          color: VintageInstrumentStyle.brassMuted.withValues(
                            alpha: 0.85,
                          ),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: VintageInstrumentStyle.dialFace,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: VintageInstrumentStyle.brassRim,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: VintageInstrumentStyle.brassRim.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: VintageInstrumentStyle.gold,
                            width: 1.2,
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _loading ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: VintageInstrumentStyle.brassMid,
                      foregroundColor: VintageInstrumentStyle.gold,
                      disabledForegroundColor: VintageInstrumentStyle.brassMuted,
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: VintageInstrumentStyle.gold,
                            ),
                          )
                        : const Icon(Icons.send, size: 16),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: VintageInstrumentStyle.stop,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
              if (_answer != null) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      _answer!.answer,
                      style: const TextStyle(
                        color: Color(0xFFF8F4EC),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (_answer!.sources.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Sources',
                    style: TextStyle(
                      color: VintageInstrumentStyle.brassMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final source in _answer!.sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: InkWell(
                        onTap: () => _openSource(source),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  source.isWikipedia
                                      ? Icons.menu_book_outlined
                                      : Icons.article_outlined,
                                  size: 12,
                                  color: VintageInstrumentStyle.gold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  source.title,
                                  style: const TextStyle(
                                    color: VintageInstrumentStyle.gold,
                                    fontSize: 12,
                                    height: 1.3,
                                    decoration: TextDecoration.underline,
                                    decorationColor: VintageInstrumentStyle.gold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final BoxDecoration _chipDecoration = BoxDecoration(
    color: VintageInstrumentStyle.dialFace.withValues(alpha: 0.78),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: VintageInstrumentStyle.brassRim, width: 1.2),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
