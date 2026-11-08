import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// Version 1 compares alternatives within a fixed market family. The history
/// supplied by the caller is the local state observed at capture time.
class SmartBetChoiceTrial {
  static const families = [
    ['1', 'X', '2'],
    ['GOAL', 'NO GOAL'],
    ['CASA SEGNA', 'OSPITE SEGNA'],
    ['OVER 1.5', 'UNDER 1.5'],
    ['OVER 2.5', 'UNDER 2.5'],
    ['OVER 3.5', 'UNDER 3.5'],
    ['OVER 4.5', 'UNDER 4.5'],
  ];

  static String? choose({
    required String official,
    required Map<String, double> original,
    required Map<String, double> simulated,
    required SmartBetAnalysisEngine engine,
    required int fixtureId,
    required DateTime cutoff,
    required Iterable<SmartBetAnalysisRecord> history,
    required bool historyObservedNow,
  }) {
    for (final family in families) {
      if (!family.contains(official)) continue;
      if (!family.every(
        (m) => original.containsKey(m) && simulated.containsKey(m),
      )) {
        return null;
      }
      final errors = <String, double>{};
      final counts = <String, int>{};
      for (final r in history) {
        final p = r.probability;
        if (r.engine != engine ||
            r.fixtureId == fixtureId ||
            !family.contains(r.market) ||
            !r.prospectiveEligible ||
            !r.firstSeenAt.isBefore(r.matchDate) ||
            !r.matchDate.isBefore(cutoff) ||
            p == null ||
            !p.isFinite ||
            p < 0 ||
            p > 1 ||
            !r.hasActualResult) {
          continue;
        }
        final resolved = r.resolvedAt;
        if (resolved == null
            ? !historyObservedNow
            : (resolved.isBefore(r.matchDate) || !resolved.isBefore(cutoff))) {
          continue;
        }
        if (r.status != SmartBetAnalysisStatus.correct &&
            r.status != SmartBetAnalysisStatus.wrong) {
          continue;
        }
        final actual = r.status == SmartBetAnalysisStatus.correct ? 1.0 : 0.0;
        errors[r.market] = (errors[r.market] ?? 0) + actual - p;
        counts[r.market] = (counts[r.market] ?? 0) + 1;
      }

      double score(String market) {
        final correction =
            ((errors[market] ?? 0) / (100 + (counts[market] ?? 0))).clamp(
              -0.10,
              0.10,
            );
        return ((original[market]! + simulated[market]!) / 2 + correction)
            .clamp(0.0, 1.0)
            .toDouble();
      }

      var best = official;
      for (final candidate in family) {
        if (score(candidate) > score(best)) best = candidate;
      }
      return best;
    }
    return null;
  }
}

class SmartBetChoiceTotals {
  int settled = 0;
  int officialHits = 0;
  int alternativeHits = 0;
  int fixed = 0;
  int introduced = 0;

  void add(String official, String alternative, int home, int away) {
    SmartBetAnalysisSettlement settle(String market) =>
        SmartBetAnalysisMarketSettlement.evaluate(
          market: market,
          homeGoals: home,
          awayGoals: away,
        );
    final first = settle(official);
    final second = settle(alternative);
    if (first == SmartBetAnalysisSettlement.unsupported ||
        second == SmartBetAnalysisSettlement.unsupported) {
      return;
    }
    settled++;
    if (first == SmartBetAnalysisSettlement.correct) officialHits++;
    if (second == SmartBetAnalysisSettlement.correct) alternativeHits++;
    if (second != first) {
      if (second == SmartBetAnalysisSettlement.correct) {
        fixed++;
      } else {
        introduced++;
      }
    }
  }

  Map<String, int> toJson() => {
    'settled': settled,
    'officialHits': officialHits,
    'alternativeHits': alternativeHits,
    'fixed': fixed,
    'introduced': introduced,
  };
}
