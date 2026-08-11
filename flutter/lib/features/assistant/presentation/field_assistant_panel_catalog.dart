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
          return _subjects.take(40);
        }
        return _subjects
            .where((s) => s.name.toLowerCase().contains(q))
            .take(40);
      },
      onSelected: _selectSubject,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Keep the Autocomplete field in sync with our selection text.
        if (controller.text != _subjectQuery.text &&
            _selectedSubject != null &&
            controller.text.isEmpty) {
          controller.text = _subjectQuery.text;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(
            color: MapChromeTheme.cream,
            fontSize: 13,
            height: 1.3,
          ),
          cursorColor: MapChromeTheme.mutedGold,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Browse a dinosaur…',
            hintStyle: TextStyle(
              color: MapChromeTheme.mutedGold.withValues(alpha: 0.7),
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.pets,
              size: 16,
              color: MapChromeTheme.mutedGold,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 32,
            ),
            suffixIcon: _selectedSubject == null
                ? null
                : IconButton(
                    tooltip: 'Clear dinosaur',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      controller.clear();
                      _subjectQuery.clear();
                      _mutatePanelState(() {
                        _selectedSubject = null;
                        _selectedSources = null;
                        _sourcesError = null;
                      });
                    },
                    icon: Icon(
                      Icons.clear,
                      size: 16,
                      color: MapChromeTheme.mutedGold.withValues(alpha: 0.85),
                    ),
                  ),
            filled: true,
            fillColor: MapChromeTheme.leatherSoft,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
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
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 360),
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
                          vertical: 8,
                        ),
                        child: Text(
                          subject.name,
                          style: const TextStyle(
                            color: MapChromeTheme.cream,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
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
                child: Text(
                  title,
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
}
