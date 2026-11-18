/// Single source of truth for the bookmaking display, not for predictions.
/// The model must rank its markets BEFORE this policy is consulted.
class GoalVdLineQuotePolicy {
  const GoalVdLineQuotePolicy._();
  static const String bookmaker = 'Sisal';
  static const double minimumOdd = 1.20;
  // Avvio con Palinsesto Italia attivo. L'utente può disattivarlo:
  // è un filtro sui marchi presenti in Italia, non una certificazione
  // che il prezzo sia davvero disponibile sul sito .it.
  static const bool italianOnlyByDefault = true;

  static bool isSisal(String name) {
    final normalized = name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'sisal' || normalized == 'sisalit';
  }

  static bool isPlayable(double? odd) =>
      odd != null && odd.isFinite && odd > minimumOdd;
}
