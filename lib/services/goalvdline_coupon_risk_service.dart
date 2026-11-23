/// B78 read-only analysis of a multiple's structural risk.
/// The model's percentages are NOT assumed calibrated and the outcome
/// correlations between different matches have not been verified.
class GoalVdLineCouponRiskSelection {
  final String fixtureId;
  final double? probabilityPercent;
  final double? realOdd;

  const GoalVdLineCouponRiskSelection({
    required this.fixtureId,
    this.probabilityPercent,
    this.realOdd,
  });
}

class GoalVdLineCouponRiskReport {
  final int events;
  final int distinctFixtures;
  final int repeatedFixtureSelections;
  final int missingOrInvalidProbabilities;
  final int lowOrUnknownOdds;
  /// Pure hypothetical product IF all forecasts were correct/independent.
  /// Null if any probability is absent, invalid, or a fixture repeats.
  final double? independenceScenarioPercent;

  const GoalVdLineCouponRiskReport({
    required this.events,
    required this.distinctFixtures,
    required this.repeatedFixtureSelections,
    required this.missingOrInvalidProbabilities,
    required this.lowOrUnknownOdds,
    required this.independenceScenarioPercent,
  });

  bool get longMultiple => events >= 8;
  bool get veryLongMultiple => events >= 12;
  bool get hasRepeatRisk => repeatedFixtureSelections > 0;
  bool get requiresAttention => longMultiple || hasRepeatRisk ||
      (independenceScenarioPercent != null &&
          independenceScenarioPercent! < 35.0);
}

class GoalVdLineCouponRiskService {
  const GoalVdLineCouponRiskService();

  GoalVdLineCouponRiskReport evaluate(
    Iterable<GoalVdLineCouponRiskSelection> selections,
  ) {
    final picks = selections.toList(growable: false);
    final distinctIds = <String>{};
    var missing = 0;
    var oddsUnknown = 0;
    var product = 1.0;
    for (final pick in picks) {
      distinctIds.add(pick.fixtureId.trim());
      final probability = pick.probabilityPercent;
      if (probability == null || !probability.isFinite ||
          probability <= 0 || probability > 100) {
        missing++;
      } else {
        product *= probability / 100.0;
      }
      final odd = pick.realOdd;
      if (odd == null || !odd.isFinite || odd <= 1.20) {
        oddsUnknown++;
      }
    }
    final repeated = picks.length - distinctIds.length;
    final scenario = picks.isEmpty || repeated > 0 || missing > 0 ||
            !product.isFinite
        ? null : product * 100.0;

    return GoalVdLineCouponRiskReport(
      events: picks.length,
      distinctFixtures: distinctIds.length,
      repeatedFixtureSelections: repeated,
      missingOrInvalidProbabilities: missing,
      lowOrUnknownOdds: oddsUnknown,
      independenceScenarioPercent: scenario,
    );
  }
}
