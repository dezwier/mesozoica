/// Compact relative / absolute timestamp for card subtitles and timelines.
String formatRelativeWhen(DateTime utc) {
  final local = utc.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${local.month}/${local.day}/${local.year}';
}
