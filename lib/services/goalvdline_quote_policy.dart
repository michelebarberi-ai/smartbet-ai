/// Single source of truth for the bookmaking display, not for predictions.
/// The model must rank its markets BEFORE this policy is consulted.
class GoalVdLineQuotePolicy {
  const GoalVdLineQuotePolicy._();
  static const String bookmaker = 'Sisal';
  static const double minimumOdd = 1.20;

  static bool isSisal(String name) {
    final normalized = name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'sisal' || normalized == 'sisalit';
  }

  static bool isPlayable(double? odd) =>
      odd != null && odd.isFinite && odd >= minimumOdd;
}
