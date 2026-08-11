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
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        media.size.height - widget.topClearance - keyboardInset - 32;
    final hasAnswer = _answer != null;
    final hasBrowseBody =
        _selectedSources != null || _sourcesLoading || hasAnswer;
    final askHint = _selectedSubject == null
        ? 'Ask about dinosaurs…'
        : 'Ask about ${_selectedSubject!.name}…';

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onScrimTap,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: widget.topClearance + 16,
              bottom: keyboardInset + 16,
              left: 16,
              right: 16,
            ),
            // Hug the top under the profile HUD; grow downward with content.
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: _panelDecoration,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                                tooltip: 'Hide keyboard',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                onPressed: _dismissKeyboard,
                                icon: Icon(
                                  Icons.keyboard_hide_outlined,
                                  size: 18,
                                  color: MapChromeTheme.mutedGold.withValues(
                                    alpha: 0.85,
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
                          _buildSubjectPicker(),
                          const SizedBox(height: 10),
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
                                    hintText: askHint,
                                    hintStyle: TextStyle(
                                      color: MapChromeTheme.mutedGold
                                          .withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                    filled: true,
                                    fillColor: MapChromeTheme.leatherSoft,
                                    contentPadding: const EdgeInsets.symmetric(
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
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: MapChromeTheme.cream,
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
                          if (hasBrowseBody) ...[
                            const SizedBox(height: 12),
                            Flexible(
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
