import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kPrivacyPolicyAsset = 'assets/policies/privacy-policy.md';
const String kTermsAsset = 'assets/policies/terms-and-conditions.md';
const String kDeleteAccountAsset = 'assets/policies/delete-account.md';
const String kDeleteDataAsset = 'assets/policies/delete-data.md';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required String assetPath,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(title: title, assetPath: assetPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.trim().isEmpty) {
            return Center(
              child: Text(
                'Document is currently unavailable.',
                style: theme.textTheme.bodyMedium,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: _blocksFor(snapshot.data!, theme),
          );
        },
      ),
    );
  }
}

List<Widget> _blocksFor(String markdown, ThemeData theme) {
  final blocks = markdown.replaceAll('\r\n', '\n').trim().split(RegExp(r'\n\s*\n'));
  return [
    for (final block in blocks)
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _blockWidget(block.trim(), theme),
      ),
  ];
}

Widget _blockWidget(String block, ThemeData theme) {
  if (block.startsWith('# ')) {
    return Text(
      block.substring(2),
      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
  if (block.startsWith('## ')) {
    return Text(
      block.substring(3),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
  if (block.startsWith('### ')) {
    return Text(
      block.substring(4),
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
  final lines = block.split('\n');
  if (lines.every((line) => line.startsWith('- '))) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyMedium),
                Expanded(child: _rich(line.substring(2), theme)),
              ],
            ),
          ),
      ],
    );
  }
  if (lines.every((line) => RegExp(r'^\d+\.\s').hasMatch(line))) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: _rich(line, theme),
          ),
      ],
    );
  }
  return _rich(block.replaceAll('\n', ' '), theme);
}

Widget _rich(String text, ThemeData theme) {
  final style = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)');
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    if (match.group(1) != null) {
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: TextStyle(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }
    start = match.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return Text.rich(TextSpan(style: style, children: spans));
}
