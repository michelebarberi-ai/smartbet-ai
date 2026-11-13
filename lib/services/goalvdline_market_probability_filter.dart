/// Filtro sulla stima del mercato, distinto dallo SmartScore dell'analisi.
/// La soglia 0 disabilita il solo limite inferiore aggiuntivo.
class GoalVdLineMarketProbabilityFilter {
  const GoalVdLineMarketProbabilityFilter._();

  /// Raccomandazione predefinita, distinta dallo SmartScore.
  static const int recommendedMinimumPercent = 65;

  static bool accepts({required int probability, required int minimumPercent}) {
    if (minimumPercent < 0 || minimumPercent > 100) {
      throw RangeError.range(minimumPercent, 0, 100, 'minimumPercent');
    }
    return probability > 0 &&
        probability <= 100 &&
        probability >= minimumPercent;
  }
}
