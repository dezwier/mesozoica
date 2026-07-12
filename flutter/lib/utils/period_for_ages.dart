/// Mesozoic period from site ages (Ma), matching backend `period_for_ages`.
///
/// Bounds: Triassic 252–201, Jurassic 201–145, Cretaceous 145–66.
/// Uses the midpoint when both bounds are present.
String? periodForAges(double? minAgeMa, double? maxAgeMa) {
  if (minAgeMa == null && maxAgeMa == null) return null;

  final double mid;
  if (minAgeMa != null && maxAgeMa != null) {
    mid = (minAgeMa + maxAgeMa) / 2;
  } else {
    mid = minAgeMa ?? maxAgeMa!;
  }

  if (mid > 201) return 'triassic';
  if (mid > 145) return 'jurassic';
  if (mid >= 66) return 'cretaceous';
  return null;
}
