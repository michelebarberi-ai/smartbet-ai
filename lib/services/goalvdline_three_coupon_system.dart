import 'goalvdline_quote_policy.dart';

/// Tre schedine alternative che mantengono esattamente gli stessi incontri.
/// Non è un sistema integrale di scommesse: è una proposta di tre varianti.
class GoalVdLineSystemSelection {
  final int fixtureId;
  final String market;
  final int probability;
  final double odd;
  final String bookmaker;

  const GoalVdLineSystemSelection({
    required this.fixtureId,
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
  });
}

class GoalVdLineThreeCouponSystem {
  static const int minimumCount = 3;
  static const int maximumCount = 15;

  static bool _valid(GoalVdLineSystemSelection pick, int minProbability) =>
      pick.fixtureId > 0 &&
      pick.market.trim().isNotEmpty &&
      pick.probability >= minProbability &&
      pick.probability <= 100 &&
      pick.odd.isFinite &&
      GoalVdLineQuotePolicy.isPlayable(pick.odd);

  /// Restituisce esattamente tre varianti distinte, oppure null.
  /// Non abbassa la soglia e non forza mercati inesistenti.
  static List<List<GoalVdLineSystemSelection>>? create({
    required List<GoalVdLineSystemSelection> original,
    required Map<int, List<GoalVdLineSystemSelection>> alternatives,
    int minimumProbability = 65,
  }) {
    if (original.length < minimumCount ||
        original.length > maximumCount ||
        minimumProbability < 1 ||
        minimumProbability > 100 ||
        original.any((item) => !_valid(item, minimumProbability)) ||
        original.map((e) => e.fixtureId).toSet().length != original.length) {
      return null;
    }

    final options = <int, List<GoalVdLineSystemSelection>>{};
    for (final base in original) {
      // Le selezioni più solide restano immutate. Diversifichiamo
      // dove il mercato originale ha una probabilità inferiore all'80%.
      if (base.probability >= 80) continue;
      final seen = <String>{};
      final valid =
          (alternatives[base.fixtureId] ?? const <GoalVdLineSystemSelection>[])
              .where(
                (candidate) =>
                    candidate.fixtureId == base.fixtureId &&
                    candidate.market != base.market &&
                    candidate.probability >= base.probability - 12 &&
                    _valid(candidate, minimumProbability) &&
                    seen.add(candidate.market),
              )
              .toList()
            ..sort((a, b) {
              final probability = b.probability.compareTo(a.probability);
              return probability != 0 ? probability : b.odd.compareTo(a.odd);
            });
      if (valid.isNotEmpty) options[base.fixtureId] = valid;
    }

    if (options.isEmpty) return null;
    final uncertainFixtures = original
        .where((base) => options.containsKey(base.fixtureId))
        .map((base) => base.fixtureId)
        .toList();

    final balanced = original
        .map((base) => options[base.fixtureId]?.first ?? base)
        .toList();

    // Variante 3: privilegia il secondo mercato se esiste.
    // Se per ogni partita esiste una sola alternativa, mantenere
    // originale una delle partite genera un'altra combinazione reale.
    final adventurous = original.map((base) {
      final choices = options[base.fixtureId];
      if (choices == null) return base;
      if (choices.length >= 2) return choices[1];
      if (uncertainFixtures.length >= 2 &&
          base.fixtureId == uncertainFixtures.first) {
        return base;
      }
      return choices.first;
    }).toList();

    String signature(List<GoalVdLineSystemSelection> coupon) =>
        coupon.map((e) => '${e.fixtureId}|${e.market}').join(';');
    final signatures = <String>{
      signature(original),
      signature(balanced),
      signature(adventurous),
    };
    if (signatures.length != 3) return null;
    return [List.of(original), balanced, adventurous];
  }
}
