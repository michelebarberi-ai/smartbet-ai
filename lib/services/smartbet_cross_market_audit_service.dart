import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';

class SmartBetCrossMarketMetrics {
  final String smartBetMarket;
  final String diegoMarket;
  final int pairs;
  final int distinctDays;
  final int bothCorrect;
  final int smartBetOnlyCorrect;
  final int diegoOnlyCorrect;
  final int bothWrong;
  final double smartBetBrier;
  final double diegoBrier;

  const SmartBetCrossMarketMetrics({
    required this.smartBetMarket,
    required this.diegoMarket,
    required this.pairs,
    required this.distinctDays,
    required this.bothCorrect,
    required this.smartBetOnlyCorrect,
    required this.diegoOnlyCorrect,
    required this.bothWrong,
    required this.smartBetBrier,
    required this.diegoBrier,
  });

  double get smartBetAccuracy => (bothCorrect + smartBetOnlyCorrect) / pairs;

  double get diegoAccuracy => (bothCorrect + diegoOnlyCorrect) / pairs;

  bool get enoughForExploratoryReview => pairs >= 30 && distinctDays >= 10;
}

class SmartBetCrossMarketReport {
  final List<SmartBetCrossMarketMetrics> groups;
  final int totalPairs;
  final int distinctFixtures;
  final int excludedLinks;

  const SmartBetCrossMarketReport({
    required this.groups,
    required this.totalPairs,
    required this.distinctFixtures,
    required this.excludedLinks,
  });
}

/// Shadow: usa solamente record e link già persistiti.
/// Non modifica previsioni, quote o schedine.
class SmartBetCrossMarketAuditService {
  const SmartBetCrossMarketAuditService();

  SmartBetCrossMarketReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required Iterable<SmartBetAnalysisComparisonLink> links,
  }) {
    final byKey = <String, SmartBetAnalysisRecord>{};

    for (final record in records) {
      byKey.putIfAbsent(record.key, () => record);
    }

    final buckets = <String, _CrossMarketBucket>{};
    final seenLinks = <String>{};
    final distinctFixtures = <int>{};

    var totalPairs = 0;
    var excludedLinks = 0;

    for (final link in links) {
      final smartBet = byKey[link.smartBetRecordKey];
      final diego = byKey[link.diegoRecordKey];

      if (smartBet == null ||
          diego == null ||
          !_validPair(link, smartBet, diego) ||
          !seenLinks.add(link.key)) {
        excludedLinks++;
        continue;
      }

      final marketA = normalizeAnalysisMarket(smartBet.market);
      final marketB = normalizeAnalysisMarket(diego.market);
      final groupKey = '$marketA|$marketB';

      final bucket = buckets.putIfAbsent(
        groupKey,
        () => _CrossMarketBucket(marketA, marketB),
      );

      final smartWon = smartBet.status == SmartBetAnalysisStatus.correct;
      final diegoWon = diego.status == SmartBetAnalysisStatus.correct;

      if (smartWon && diegoWon) {
        bucket.bothCorrect++;
      } else if (smartWon) {
        bucket.smartBetOnlyCorrect++;
      } else if (diegoWon) {
        bucket.diegoOnlyCorrect++;
      } else {
        bucket.bothWrong++;
      }

      final smartError = smartBet.probability! - (smartWon ? 1.0 : 0.0);
      final diegoError = diego.probability! - (diegoWon ? 1.0 : 0.0);

      bucket.smartBetBrierSum += smartError * smartError;
      bucket.diegoBrierSum += diegoError * diegoError;
      bucket.pairs++;

      final day = smartBet.matchDate.toUtc();
      bucket.days.add('${day.year}-${day.month}-${day.day}');

      distinctFixtures.add(link.fixtureId);
      totalPairs++;
    }

    final groups =
        buckets.values.map((bucket) {
          return SmartBetCrossMarketMetrics(
            smartBetMarket: bucket.smartBetMarket,
            diegoMarket: bucket.diegoMarket,
            pairs: bucket.pairs,
            distinctDays: bucket.days.length,
            bothCorrect: bucket.bothCorrect,
            smartBetOnlyCorrect: bucket.smartBetOnlyCorrect,
            diegoOnlyCorrect: bucket.diegoOnlyCorrect,
            bothWrong: bucket.bothWrong,
            smartBetBrier: bucket.smartBetBrierSum / bucket.pairs,
            diegoBrier: bucket.diegoBrierSum / bucket.pairs,
          );
        }).toList()..sort((a, b) {
          final count = b.pairs.compareTo(a.pairs);
          if (count != 0) return count;
          final first = a.smartBetMarket.compareTo(b.smartBetMarket);
          return first != 0 ? first : a.diegoMarket.compareTo(b.diegoMarket);
        });

    return SmartBetCrossMarketReport(
      groups: List.unmodifiable(groups),
      totalPairs: totalPairs,
      distinctFixtures: distinctFixtures.length,
      excludedLinks: excludedLinks,
    );
  }

  bool _validPair(
    SmartBetAnalysisComparisonLink link,
    SmartBetAnalysisRecord smartBet,
    SmartBetAnalysisRecord diego,
  ) {
    if (smartBet.engine != SmartBetAnalysisEngine.smartBet ||
        diego.engine != SmartBetAnalysisEngine.diego ||
        diego.qualified != true ||
        smartBet.fixtureId != link.fixtureId ||
        diego.fixtureId != link.fixtureId ||
        smartBet.key != link.smartBetRecordKey ||
        diego.key != link.diegoRecordKey ||
        normalizeAnalysisMarket(smartBet.market) !=
            normalizeAnalysisMarket(link.smartBetMarket) ||
        normalizeAnalysisMarket(diego.market) !=
            normalizeAnalysisMarket(link.diegoMarket) ||
        normalizeAnalysisMarket(smartBet.market) ==
            normalizeAnalysisMarket(diego.market)) {
      return false;
    }

    if (!_eligible(smartBet) || !_eligible(diego)) {
      return false;
    }

    if (!smartBet.matchDate.toUtc().isAtSameMomentAs(diego.matchDate.toUtc()) ||
        !link.firstSeenAt.toUtc().isBefore(smartBet.matchDate.toUtc()) ||
        smartBet.actualHomeGoals != diego.actualHomeGoals ||
        smartBet.actualAwayGoals != diego.actualAwayGoals) {
      return false;
    }

    return true;
  }

  bool _eligible(SmartBetAnalysisRecord record) {
    final probability = record.probability;
    final resolvedAt = record.resolvedAt;
    final kickoff = record.matchDate.toUtc();

    return record.prospectiveEligible &&
        probability != null &&
        probability.isFinite &&
        probability >= 0 &&
        probability <= 1 &&
        record.hasActualResult &&
        record.asianSettlement == null &&
        resolvedAt != null &&
        resolvedAt.toUtc().isAfter(kickoff) &&
        record.firstSeenAt.toUtc().isBefore(kickoff) &&
        (record.status == SmartBetAnalysisStatus.correct ||
            record.status == SmartBetAnalysisStatus.wrong);
  }
}

class _CrossMarketBucket {
  final String smartBetMarket;
  final String diegoMarket;

  int pairs = 0;
  int bothCorrect = 0;
  int smartBetOnlyCorrect = 0;
  int diegoOnlyCorrect = 0;
  int bothWrong = 0;

  double smartBetBrierSum = 0;
  double diegoBrierSum = 0;

  final Set<String> days = {};

  _CrossMarketBucket(this.smartBetMarket, this.diegoMarket);
}
