import 'smartbet_match_simulation_service.dart';
import 'smartbet_market_probability_service.dart';

/// La valutazione viene fatta SOLO DOPO l'esito definitivo e non modifica
/// il modello. Le previsioni devono essere state archiviate prima del match.
class SmartBetSimulationCompletedFixture {
  final String fixtureId;
  final SmartBetSimulationResult preMatchPrediction;
  final int finalHomeGoals;
  final int finalAwayGoals;

  const SmartBetSimulationCompletedFixture({
    required this.fixtureId,
    required this.preMatchPrediction,
    required this.finalHomeGoals,
    required this.finalAwayGoals,
  });
}

class SmartBetSimulationMarketMetric {
  final String market;
  final int sampleSize;
  final double meanPredictedProbability;
  final double observedFrequency;
  final double brierScore;

  const SmartBetSimulationMarketMetric({
    required this.market,
    required this.sampleSize,
    required this.meanPredictedProbability,
    required this.observedFrequency,
    required this.brierScore,
  });

  /// Calibrazione aggregata: positivo => il modello ha sovrastimato il mercato.
  double get overestimation => meanPredictedProbability - observedFrequency;
}

/// Audit in shadow mode di TUTTI i mercati supportati, inclusi quelli
/// scartati dalla schedina. Non utilizza le quote e non riscrive previsioni.
class SmartBetSimulationAuditService {
  const SmartBetSimulationAuditService();

  Map<String, SmartBetSimulationMarketMetric> summarize(
    Iterable<SmartBetSimulationCompletedFixture> fixtures,
  ) {
    final seen = <String>{};
    final sums = <String, _MetricAccumulator>{};
    for (final fixture in fixtures) {
      if (fixture.fixtureId.trim().isEmpty || !seen.add(fixture.fixtureId)) {
        throw ArgumentError(
          'ID partita vuoto o duplicato: ${fixture.fixtureId}',
        );
      }
      if (fixture.finalHomeGoals < 0 || fixture.finalAwayGoals < 0) {
        throw ArgumentError('Risultato finale non valido.');
      }
      for (final entry
          in fixture.preMatchPrediction.marketProbabilities.entries) {
        final probability = entry.value;
        final occurred = _settled(
          entry.key,
          fixture.finalHomeGoals,
          fixture.finalAwayGoals,
        );
        if (!probability.isFinite || probability < 0 || probability > 1) {
          throw StateError('Probabilita non valida per ${entry.key}.');
        }
        final acc = sums.putIfAbsent(entry.key, _MetricAccumulator.new);
        acc.samples++;
        acc.sumPredicted += probability;
        acc.sumObserved += occurred ? 1 : 0;
        final error = probability - (occurred ? 1.0 : 0.0);
        acc.sumBrier += error * error;
      }
    }
    return Map.unmodifiable(
      sums.map(
        (market, acc) => MapEntry(
          market,
          SmartBetSimulationMarketMetric(
            market: market,
            sampleSize: acc.samples,
            meanPredictedProbability: acc.sumPredicted / acc.samples,
            observedFrequency: acc.sumObserved / acc.samples,
            brierScore: acc.sumBrier / acc.samples,
          ),
        ),
      ),
    );
  }

  bool _settled(String market, int h, int a) {
    // I 14 mercati OPPURE sono unioni logiche sul risultato finale.
    // Sono esattamente gli stessi mercati ammessi dal simulatore;
    // non li sommiamo come eventi indipendenti.
    if (SmartBetMarketProbabilityService.orMarkets.contains(market)) {
      final parts = market.split(' O ');
      if (parts.length != 2) {
        throw StateError('Mercato OR non valido: $market');
      }
      return _settled(parts.first, h, a) || _settled(parts.last, h, a);
    }
    final total = h + a;
    if (market == '1') return h > a;
    if (market == 'X') return h == a;
    if (market == '2') return h < a;
    if (market == '1X') return h >= a;
    if (market == 'X2') return h <= a;
    if (market == '12') return h != a;
    if (market == 'GOAL') return h > 0 && a > 0;
    if (market == 'NO GOAL') return h == 0 || a == 0;
    if (market == 'HOME SCORES') return h > 0;
    if (market == 'AWAY SCORES') return a > 0;
    final overUnder = RegExp(r'^(OVER|UNDER) ([0-4])\.5$').firstMatch(market);
    if (overUnder != null) {
      final threshold = int.parse(overUnder.group(2)!);
      return overUnder.group(1) == 'OVER'
          ? total > threshold
          : total <= threshold;
    }
    final multigol = RegExp(r'^MULTIGOL ([1-3])-([3-5])$').firstMatch(market);
    if (multigol != null) {
      return total >= int.parse(multigol.group(1)!) &&
          total <= int.parse(multigol.group(2)!);
    }
    throw StateError('Mercato non valutabile: $market');
  }
}

class _MetricAccumulator {
  int samples = 0;
  double sumPredicted = 0;
  double sumObserved = 0;
  double sumBrier = 0;
}
