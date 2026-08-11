import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/features/assistant/data/assistant_repository.dart';
import 'package:mesozoica/features/assistant/domain/assistant_answer.dart';
import 'package:mesozoica/features/assistant/domain/knowledge_catalog.dart';
import 'package:mesozoica/theme/map_chrome_decorations.dart';
import 'package:mesozoica/theme/map_chrome_theme.dart';

part 'field_assistant_panel_catalog.dart';

/// Lifecycle for the field-assistant panel (map freeze + chrome via [AppShell]).
abstract final class FieldAssistantOverlay {
  FieldAssistantOverlay._();

  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static bool get isOpen => openCount.value > 0;

  static void open() {
    if (openCount.value == 0) openCount.value = 1;
  }

  static void close() {
    if (openCount.value > 0) openCount.value = 0;
  }

  static void toggle() {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }
}

/// Subtle map-chrome icon that opens the field assistant.
class FieldAssistantChip extends StatelessWidget {
  const FieldAssistantChip({super.key});

  static const _textShadows = <Shadow>[
    Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: FieldAssistantOverlay.toggle,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.auto_awesome,
            size: 22,
            // Same amber as the clear-day sun in [WeatherDisplay.weatherIconColor].
            color: Color(0xFFFFC107),
            shadows: _textShadows,
          ),
        ),
      ),
    );
  }
}

/// Centered Q&A panel over the frozen map (full width minus padding).
class FieldAssistantPanel extends StatefulWidget {
  const FieldAssistantPanel({
    super.key,
    required this.topClearance,
    AssistantRepository? repository,
  }) : _repository = repository;

  /// Bottom of the profile HUD — panel centers in the space below it.
  final double topClearance;

  final AssistantRepository? _repository;

  @override
  State<FieldAssistantPanel> createState() => _FieldAssistantPanelState();
}

class _FieldAssistantPanelState extends State<FieldAssistantPanel> {
  late final AssistantRepository _repository =
      widget._repository ?? AssistantRepository();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _subjectQuery = TextEditingController();

  bool _loading = false;
  String? _error;
  AssistantAnswer? _answer;

  List<KnowledgeSubject> _subjects = const [];
  bool _subjectsLoading = true;
  String? _subjectsError;
  KnowledgeSubject? _selectedSubject;
  KnowledgeSources? _selectedSources;
  bool _sourcesLoading = false;
  String? _sourcesError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    unawaited(_loadSubjects());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _subjectQuery.dispose();
    super.dispose();
  }

  void _close() {
    _focusNode.unfocus();
    FieldAssistantOverlay.close();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _subjectsLoading = true;
      _subjectsError = null;
    });
    try {
      final subjects = await _repository.listSubjects();
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _subjectsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _subjectsError = e.message;
        _subjectsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subjectsError = 'Could not load dinosaurs.';
        _subjectsLoading = false;
      });
    }
  }

  Future<void> _selectSubject(KnowledgeSubject subject) async {
    if (_sourcesLoading && _selectedSubject?.id == subject.id) return;
    setState(() {
      _selectedSubject = subject;
      _subjectQuery.text = subject.name;
      _sourcesLoading = true;
      _sourcesError = null;
      _selectedSources = null;
    });
    try {
      final sources = await _repository.listSources(subject.id);
      if (!mounted) return;
      if (_selectedSubject?.id != subject.id) return;
      setState(() {
        _selectedSources = sources;
        _sourcesLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_selectedSubject?.id != subject.id) return;
      setState(() {
        _sourcesError = e.message;
        _sourcesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_selectedSubject?.id != subject.id) return;
      setState(() {
        _sourcesError = 'Could not load sources.';
        _sourcesLoading = false;
      });
    }
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _mutatePanelState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        media.size.height - widget.topClearance - keyboardInset - 32;
    final hasAnswer = _answer != null;
    final hasCatalogBrowse =
        _selectedSubject != null || _subjects.isNotEmpty || _subjectsLoading;
    // Compact when asking; grow once answering or browsing sources.
    final panelMaxHeight =
        availableHeight * ((hasAnswer || hasCatalogBrowse) ? 0.78 : 0.42);

    return Positioned.fill(
      child: Stack(
        children: [
          // Full-screen dim (including under the profile HUD) so removing
          // MapTopFade does not leave a bright/white band at the top.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _close,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Padding(
            // Sit below the profile HUD; shrink above the keyboard when open.
            padding: EdgeInsets.only(
              top: widget.topClearance + 16,
              bottom: keyboardInset + 16,
              left: 16,
              right: 16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelMaxHeight),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: _panelDecoration,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
                        child: Column(
                          mainAxisSize:
                              (hasAnswer ||
                                  _selectedSources != null ||
                                  _sourcesLoading)
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: MapChromeTheme.hudGold,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Field assistant',
                                    style: TextStyle(
                                      color: MapChromeTheme.cream,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: _loading ? null : _close,
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: MapChromeTheme.mutedGold.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    enabled: !_loading,
                                    minLines: 1,
                                    maxLines: 4,
                                    maxLength: 500,
                                    maxLengthEnforcement:
                                        MaxLengthEnforcement.enforced,
                                    style: const TextStyle(
                                      color: MapChromeTheme.cream,
                                      fontSize: 14,
                                      height: 1.3,
                                    ),
                                    cursorColor: MapChromeTheme.mutedGold,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      hintText: 'Ask about dinosaurs…',
                                      hintStyle: TextStyle(
                                        color: MapChromeTheme.mutedGold
                                            .withValues(alpha: 0.7),
                                        fontSize: 14,
                                      ),
                                      filled: true,
                                      fillColor: MapChromeTheme.leatherSoft,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: MapChromeTheme.chromeBorder,
                                          width:
                                              MapChromeTheme.chromeBorderWidth,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: MapChromeTheme.brassRim
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: MapChromeTheme.brassMid
                                              .withValues(alpha: 0.7),
                                          width: 1.1,
                                        ),
                                      ),
                                    ),
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Material(
                                    color: MapChromeTheme.leatherSoftMid,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: MapChromeTheme.chromeBorder,
                                      ),
                                    ),
                                    child: InkWell(
                                      onTap: _loading ? null : _send,
                                      customBorder: const CircleBorder(),
                                      child: Center(
                                        child: _loading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color:
                                                          MapChromeTheme.cream,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.send,
                                                size: 18,
                                                color: MapChromeTheme.cream,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildSubjectPicker(),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFE07060),
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (_sourcesError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _sourcesError!,
                                style: const TextStyle(
                                  color: Color(0xFFE07060),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (hasAnswer ||
                                _selectedSources != null ||
                                _sourcesLoading) ...[
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_sourcesLoading)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: MapChromeTheme.cream,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_selectedSources != null)
                                        _buildSourceGroups(_selectedSources!),
                                      if (hasAnswer) ...[
                                        if (_selectedSources != null)
                                          const SizedBox(height: 14),
                                        Text(
                                          _answer!.answer,
                                          style: const TextStyle(
                                            color: MapChromeTheme.cream,
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                        ),
                                        if (_answer!.sources.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Answer sources',
                                            style: TextStyle(
                                              color: MapChromeTheme.mutedGold,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          for (final source
                                              in _answer!.sources)
                                            _sourceLinkRow(
                                              title: source.title,
                                              url: source.url,
                                              isWikipedia: source.isWikipedia,
                                            ),
                                        ],
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  static final BoxDecoration _panelDecoration =
      MapChromeDecorations.leatherPanel(
        borderRadius: BorderRadius.circular(14),
        soft: true,
      ).copyWith(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      );
}
