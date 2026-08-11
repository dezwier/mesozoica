part of 'field_assistant_chip.dart';

extension on _FieldAssistantPanelState {
  Widget _buildSubjectPicker() {
    if (_subjectsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Loading dinosaurs…',
          style: TextStyle(
            color: MapChromeTheme.mutedGold,
            fontSize: 12,
          ),
        ),
      );
    }
    if (_subjectsError != null) {
      return Text(
        _subjectsError!,
        style: const TextStyle(
          color: Color(0xFFE07060),
          fontSize: 12,
          height: 1.3,
        ),
      );
    }
    if (_subjects.isEmpty) {
      return const Text(
        'No indexed dinosaurs yet.',
        style: TextStyle(
          color: MapChromeTheme.mutedGold,
          fontSize: 12,
        ),
      );
    }

    return Autocomplete<KnowledgeSubject>(
      displayStringForOption: (subject) => subject.name,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) {
          return _subjects.take(120);
        }
        return _subjects
            .where((s) => s.name.toLowerCase().contains(q))
            .take(120);
      },
      onSelected: _selectSubject,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        _attachSubjectFocusListener(focusNode);
        // Keep the Autocomplete field in sync with our selection text.
        if (controller.text != _subjectQuery.text &&
            _selectedSubject != null &&
            controller.text.isEmpty) {
          controller.text = _subjectQuery.text;
        }
        return SizedBox(
          height: _fieldHeight,
          child: TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: !_subjectKeyboardEnabled,
          // Keep a caret while browsing so focus state is visible.
          showCursor: true,
          enableInteractiveSelection: _subjectKeyboardEnabled,
          keyboardType: TextInputType.text,
          style: _fieldTextStyle,
          cursorColor: MapChromeTheme.mutedGold,
          onTap: () {
            // Focusing opens the dropdown; keyboard stays off until toggled.
            if (!_subjectKeyboardEnabled) {
              SystemChannels.textInput.invokeMethod('TextInput.hide');
            }
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Browse a dinosaur…',
            hintStyle: TextStyle(
              color: MapChromeTheme.mutedGold.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.25,
            ),
            prefixIcon: const Icon(
              Icons.pets,
              size: 18,
              color: MapChromeTheme.mutedGold,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: _fieldHeight,
            ),
            suffixIcon: _selectedSubject == null
                ? null
                : IconButton(
                    tooltip: 'Clear dinosaur',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: _fieldHeight,
                    ),
                    onPressed: () {
                      controller.clear();
                      _subjectQuery.clear();
                      _mutatePanelState(() {
                        _subjectKeyboardEnabled = false;
                        _selectedSubject = null;
                        _selectedSources = null;
                        _sourcesError = null;
                      });
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                    },
                    icon: Icon(
                      Icons.clear,
                      size: 18,
                      color: MapChromeTheme.mutedGold.withValues(alpha: 0.85),
                    ),
                  ),
            filled: true,
            fillColor: MapChromeTheme.leatherSoft,
            contentPadding: _fieldContentPadding,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: MapChromeTheme.chromeBorder,
                width: MapChromeTheme.chromeBorderWidth,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: MapChromeTheme.brassRim.withValues(alpha: 0.35),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: MapChromeTheme.brassMid.withValues(alpha: 0.7),
                width: 1.1,
              ),
            ),
          ),
          onChanged: (value) {
            _subjectQuery.text = value;
            if (_selectedSubject != null &&
                value.trim() != _selectedSubject!.name) {
              _mutatePanelState(() {
                _selectedSubject = null;
                _selectedSources = null;
                _sourcesError = null;
              });
            }
          },
          onSubmitted: (_) {
            _mutatePanelState(() => _subjectKeyboardEnabled = false);
            SystemChannels.textInput.invokeMethod('TextInput.hide');
            onFieldSubmitted();
          },
        ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList(growable: false);
        final media = MediaQuery.of(context);
        // Fill from the field down to the keyboard / screen bottom.
        final maxHeight = (media.size.height -
                media.viewInsets.bottom -
                media.padding.top -
                120)
            .clamp(220.0, media.size.height);
        final maxWidth = media.size.width - 48;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight,
                maxWidth: maxWidth,
              ),
              child: SizedBox(
                width: maxWidth,
                child: DecoratedBox(
                  decoration: MapChromeDecorations.leatherPanel(
                    borderRadius: BorderRadius.circular(10),
                    soft: true,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: opts.length,
                    itemBuilder: (context, index) {
                      final subject = opts[index];
                      return InkWell(
                        onTap: () => onSelected(subject),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            subject.name,
                            style: const TextStyle(
                              color: MapChromeTheme.cream,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCatalogBrowseBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sourcesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
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
        if (_selectedSources != null) _buildSourceGroups(_selectedSources!),
      ],
    );
  }

  Widget _buildAnswerTabs() {
    final answer = _answer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildResultTabBar(),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: _resultTab == 0
                ? _buildAnswerBody(answer)
                : _buildCatalogSourcesTab(),
          ),
        ),
      ],
    );
  }

  Widget _buildResultTabBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MapChromeTheme.leatherSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MapChromeTheme.brassRim.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
              child: _resultSegment(
                label: 'Answer',
                selected: _resultTab == 0,
                onTap: () => _mutatePanelState(() => _resultTab = 0),
              ),
            ),
            Expanded(
              child: _resultSegment(
                label: 'Sources',
                selected: _resultTab == 1,
                onTap: () => _mutatePanelState(() => _resultTab = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultSegment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? MapChromeTheme.leatherSoftMid : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? MapChromeTheme.cream
                  : MapChromeTheme.mutedGold.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerBody(AssistantAnswer answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          answer.answer,
          style: const TextStyle(
            color: MapChromeTheme.cream,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        if (answer.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'References',
            style: TextStyle(
              color: MapChromeTheme.mutedGold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final source in answer.sources) ...[
            _referenceChunkCard(source),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _referenceChunkCard(SourceLink source) {
    final hasLink = source.url.isNotEmpty;
    final text = _displayChunkText(source.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text.isNotEmpty)
          Text(
            text,
            softWrap: true,
            style: TextStyle(
              color: MapChromeTheme.cream.withValues(alpha: 0.92),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        if (source.title.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: hasLink ? () => _openUrl(source.url) : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    source.isWikipedia
                        ? Icons.menu_book_outlined
                        : Icons.article_outlined,
                    size: 13,
                    color: MapChromeTheme.hudGold,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _richTitle(
                      source.title,
                      style: TextStyle(
                        color: MapChromeTheme.hudGold,
                        fontSize: 12,
                        height: 1.2,
                        decoration: hasLink ? TextDecoration.underline : null,
                        decorationColor: MapChromeTheme.hudGold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Client-side guard against hard-wrapped wiki/paper chunks.
  String _displayChunkText(String raw) {
    final cleaned = raw
        .replaceAll('\u00ad', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  Widget _buildCatalogSourcesTab() {
    if (_sourcesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
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
      );
    }
    if (_sourcesError != null) {
      return Text(
        _sourcesError!,
        style: const TextStyle(
          color: Color(0xFFE07060),
          fontSize: 12,
          height: 1.3,
        ),
      );
    }
    if (_selectedSources == null) {
      return const Text(
        'Select a dinosaur above to browse its sources.',
        style: TextStyle(
          color: MapChromeTheme.mutedGold,
          fontSize: 13,
          height: 1.35,
        ),
      );
    }
    return _buildSourceGroups(_selectedSources!);
  }

  Widget _buildSourceGroups(KnowledgeSources sources) {
    if (sources.groups.isEmpty) {
      return const Text(
        'No indexed sources yet',
        style: TextStyle(
          color: MapChromeTheme.mutedGold,
          fontSize: 12,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sources.groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Text(
            sources.groups[i].label,
            style: const TextStyle(
              color: MapChromeTheme.mutedGold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in sources.groups[i].items)
            _sourceLinkRow(
              title: item.title,
              url: item.url,
              isWikipedia: item.isWikipedia,
            ),
        ],
      ],
    );
  }

  Widget _sourceLinkRow({
    required String title,
    required String url,
    required bool isWikipedia,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => _openUrl(url),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  isWikipedia
                      ? Icons.menu_book_outlined
                      : Icons.article_outlined,
                  size: 13,
                  color: MapChromeTheme.hudGold,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _richTitle(
                  title,
                  maxLines: 3,
                  style: const TextStyle(
                    color: MapChromeTheme.hudGold,
                    fontSize: 13,
                    height: 1.3,
                    decoration: TextDecoration.underline,
                    decorationColor: MapChromeTheme.hudGold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders API titles that may contain ``<i>…</i>`` italic spans.
  Widget _richTitle(
    String title, {
    required TextStyle style,
    int maxLines = 1,
  }) {
    return Text.rich(
      TextSpan(style: style, children: _titleSpans(title, style)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: maxLines > 1,
    );
  }

  List<InlineSpan> _titleSpans(String title, TextStyle style) {
    final italicStyle = style.copyWith(fontStyle: FontStyle.italic);
    final pattern = RegExp(r'<i>(.*?)</i>', caseSensitive: false, dotAll: true);
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(title)) {
      if (match.start > start) {
        spans.add(TextSpan(text: title.substring(start, match.start)));
      }
      final inner = match.group(1) ?? '';
      if (inner.isNotEmpty) {
        spans.add(TextSpan(text: inner, style: italicStyle));
      }
      start = match.end;
    }
    if (start < title.length) {
      spans.add(TextSpan(text: title.substring(start)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: title));
    }
    return spans;
  }
}
