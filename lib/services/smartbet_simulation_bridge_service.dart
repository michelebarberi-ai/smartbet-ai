import 'dart:math' as math;

import '../models/analysis_result.dart';
import '../models/goalvdline_match_engine_models.dart';
import 'diego_ai_market_probability_service.dart';
import 'goalvdline_shadow_service.dart';
import 'smartbet_market_probability_service.dart';
import 'smartbet_match_simulation_service.dart';

/// P21B - confronto SPERIMENTALE, senza salvataggi e senza modificare le
/// previsioni della app. Non utilizza quote bookmaker.
///
/// Per comparare i motori bisogna fornire previsioni fatte sulla stessa
/// partita e PRIMA del calcio d'inizio; P21B non ne certifica il timestamp.
class SmartBetSimulationMarketDifference {
  final String market;
  final double existingProbability;
  final double simulatedProbability;

  const SmartBetSimulationMarketDifference({
    required this.market,
    required this.existingProbability,
    required this.simulatedProbability,
  });

  /// Differenza in punti probabilistici (0.1 equivale a 10 punti percentuali).
  double get delta => simulatedProbability - existingProbability;
  double get absoluteDelta => delta.abs();
}

class SmartBetSimulationComparisonReport {
  final String source;
  final String? fixtureId;
  final SmartBetSimulationResult simulation;
  final Map<String, double> existingProbabilities;
  final List<SmartBetSimulationMarketDifference> comparedMarkets;
  final List<String> unsupportedMarkets;

  const SmartBetSimulationComparisonReport({
    required this.source,
    required this.fixtureId,
    required this.simulation,
    required this.existingProbabilities,
    required this.comparedMarkets,
    required this.unsupportedMarkets,
  });

  double get dataQuality => simulation.input.dataQuality;

  List<SmartBetSimulationMarketDifference> get mostDifferent {
    final sorted = List<SmartBetSimulationMarketDifference>.of(comparedMarkets)
      ..sort((a, b) {
        final d = b.absoluteDelta.compareTo(a.absoluteDelta);
        return d != 0 ? d : a.market.compareTo(b.market);
      });
    return List.unmodifiable(sorted);
  }
}

/// Probabilita' ricavate dal SOLO scenario sportivo, comprese combo
/// che P21A non esponeva ancora esplicitamente nella mappa base.
class SmartBetSimulationMarketAdapter {
  const SmartBetSimulationMarketAdapter._();

  static double? forMarket(SmartBetSimulationResult result, String market) {
    final key = market.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    final direct = result.marketProbabilities[key];
    if (direct != null) return direct;

    if (key == 'CASA SEGNA') return result.probabilityFor('HOME SCORES');
    if (key == 'OSPITE SEGNA') return result.probabilityFor('AWAY SCORES');

    // Solo Poisson indipendente: una componente comune cambia il processo
    // del primo gol; non forniamo una formula priva di validazione.
    if (key == 'CASA SEGNA PRIMA' || key == 'OSPITE SEGNA PRIMA') {
      if (result.input.sharedGoalIntensity != 0) return null;
      final h = result.input.expectedHomeGoals;
      final a = result.input.expectedAwayGoals;
      final total = h + a;
      if (total == 0) return 0;
      return ((key == 'CASA SEGNA PRIMA' ? h : a) / total) *
          (1.0 - math.exp(-total));
    }

    bool Function(int, int)? predicate;
    switch (key) {
      case 'CASA 2+ GOL':
        predicate = (h, a) => h >= 2;
        break;
      case 'OSPITE 2+ GOL':
        predicate = (h, a) => a >= 2;
        break;
      case 'CASA 3+ GOL':
        predicate = (h, a) => h >= 3;
        break;
      case 'OSPITE 3+ GOL':
        predicate = (h, a) => a >= 3;
        break;
      case 'GOAL + O2.5':
        predicate = (h, a) => h > 0 && a > 0 && h + a >= 3;
        break;
      case 'NO GOAL + U2.5':
        predicate = (h, a) => (h == 0 || a == 0) && h + a <= 2;
        break;
      default:
        final combo = RegExp(
          r'^(1X|X2|1|2) \+ (O|U)([123])\.5$',
        ).firstMatch(key);
        if (combo != null) {
          final side = combo.group(1)!;
          final direction = combo.group(2)!;
          final threshold = int.parse(combo.group(3)!);
          predicate = (h, a) {
            final resultOk = switch (side) {
              '1X' => h >= a,
              'X2' => a >= h,
              '1' => h > a,
              '2' => a > h,
              _ => false,
            };
            final goalsOk = direction == 'O'
                ? h + a > threshold
                : h + a <= threshold;
            return resultOk && goalsOk;
          };
        }
    }
    if (predicate == null) return null;
    var probability = 0.0;
    for (final score in result.exactScores) {
      if (predicate(score.homeGoals, score.awayGoals)) {
        probability += score.probability;
      }
    }
    return probability.clamp(0.0, 1.0).toDouble();
  }
}

class SmartBetSimulationBridgeService {
  final SmartBetMatchSimulationService simulator;

  const SmartBetSimulationBridgeService({
    this.simulator = const SmartBetMatchSimulationService(),
  });

  /// Confronto senza scritture: i due motori ricevono GLI STESSI xG.
  /// `existingProbabilities` contiene valori 0..1 (non percentuali 0..100).
  SmartBetSimulationComparisonReport compare({
    required String source,
    required double expectedHomeGoals,
    required double expectedAwayGoals,
    required double dataQuality,
    required Map<String, double> existingProbabilities,
    String? fixtureId,
  }) {
    if (source.trim().isEmpty) throw ArgumentError('Fonte mancante.');
    final simulation = simulator.simulate(
      SmartBetMatchSimulationInput(
        expectedHomeGoals: expectedHomeGoals,
        expectedAwayGoals: expectedAwayGoals,
        dataQuality: dataQuality,
      ),
    );
    final existing = <String, double>{};
    for (final entry in existingProbabilities.entries) {
      final key = entry.key.trim().toUpperCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (key.isEmpty || existing.containsKey(key)) {
        throw ArgumentError('Mercato vuoto o duplicato: ${entry.key}');
      }
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw ArgumentError('Probabilita fuori intervallo 0..1: $key');
      }
      existing[key] = entry.value;
    }
    final compared = <SmartBetSimulationMarketDifference>[];
    final unsupported = <String>[];
    for (final entry in existing.entries) {
      final probability = SmartBetSimulationMarketAdapter.forMarket(
        simulation,
        entry.key,
      );
      if (probability == null) {
        unsupported.add(entry.key);
      } else {
        compared.add(
          SmartBetSimulationMarketDifference(
            market: entry.key,
            existingProbability: entry.value,
            simulatedProbability: probability,
          ),
        );
      }
    }
    return SmartBetSimulationComparisonReport(
      source: source,
      fixtureId: fixtureId,
      simulation: simulation,
      existingProbabilities: Map.unmodifiable(existing),
      comparedMarkets: List.unmodifiable(compared),
      unsupportedMarkets: List.unmodifiable(unsupported),
    );
  }

  /// Usa realmente il catalogo mercati SmartBet e i suoi gol attesi.
  /// Non chiamare se gli xG sono zero usato come sentinella di dati assenti.
  SmartBetSimulationComparisonReport fromSmartBet({
    required AnalysisResult result,
    required double dataQuality,
    String? fixtureId,
  }) {
    _requireObservedGoals(result.expectedHomeGoals, result.expectedAwayGoals);
    return compare(
      source: 'SMARTBET',
      fixtureId: fixtureId,
      expectedHomeGoals: result.expectedHomeGoals,
      expectedAwayGoals: result.expectedAwayGoals,
      dataQuality: dataQuality,
      existingProbabilities: {
        // P21C: includiamo i mercati NATIVI, specialmente la X.
        // Non interpretiamo una coppia 0/0 (valore di default) come dato.
        if (_probabilitiesSumToOne([
          result.homeProbability,
          result.drawProbability,
          result.awayProbability,
        ])) ...{
          '1': result.homeProbability / 100.0,
          'X': result.drawProbability / 100.0,
          '2': result.awayProbability / 100.0,
        },
        if (_probabilitiesSumToOne([
          result.over15Probability,
          result.under15Probability,
        ])) ...{
          'OVER 1.5': result.over15Probability / 100.0,
          'UNDER 1.5': result.under15Probability / 100.0,
        },
        if (_probabilitiesSumToOne([
          result.over25Probability,
          result.under25Probability,
        ])) ...{
          'OVER 2.5': result.over25Probability / 100.0,
          'UNDER 2.5': result.under25Probability / 100.0,
        },
        if (_probabilitiesSumToOne([
          result.goalProbability,
          result.noGoalProbability,
        ])) ...{
          'GOAL': result.goalProbability / 100.0,
          'NO GOAL': result.noGoalProbability / 100.0,
        },
        for (final market in SmartBetMarketProbabilityService.extendedMarkets)
          market:
              SmartBetMarketProbabilityService.probabilityFor(result, market) /
              100.0,
      },
    );
  }

  /// Confronta anche i mercati nativi Diego: possono essere diversi da
  /// Poisson pur a parita' di xG. NON li ricalcola come se fossero identici.
  SmartBetSimulationComparisonReport fromDiego({
    required GoalVdLineMatchEngineResult result,
    required double dataQuality,
    String? fixtureId,
  }) {
    _requireObservedGoals(result.expectedHomeGoals, result.expectedAwayGoals);
    return compare(
      source: 'DIEGO',
      fixtureId: fixtureId,
      expectedHomeGoals: result.expectedHomeGoals,
      expectedAwayGoals: result.expectedAwayGoals,
      dataQuality: dataQuality,
      existingProbabilities: const DiegoAiMarketProbabilityService().asMap(
        result,
      ),
    );
  }

  /// Utilizza uno snapshot preesistente di GoalVdLine senza avviare API.
  /// Le sue probabilita' sono in percentuale 0..100.
  SmartBetSimulationComparisonReport fromGoalVdLineShadow({
    required GoalVdLineShadowSnapshot snapshot,
    required double dataQuality,
  }) {
    _requireObservedGoals(
      snapshot.expectedHomeGoals,
      snapshot.expectedAwayGoals,
    );
    return compare(
      source: 'GOALVDLINE_SHADOW',
      fixtureId: snapshot.fixtureId.toString(),
      expectedHomeGoals: snapshot.expectedHomeGoals,
      expectedAwayGoals: snapshot.expectedAwayGoals,
      dataQuality: dataQuality,
      existingProbabilities: {
        '1': snapshot.homeProbability / 100.0,
        'X': snapshot.drawProbability / 100.0,
        '2': snapshot.awayProbability / 100.0,
        'OVER 1.5': snapshot.over15Probability / 100.0,
        'OVER 2.5': snapshot.over25Probability / 100.0,
        'OVER 3.5': snapshot.over35Probability / 100.0,
        'GOAL': snapshot.goalProbability / 100.0,
      },
    );
  }

  // Dati percentuali interi. Piccoli arrotondamenti sono tollerati.
  static bool _probabilitiesSumToOne(List<int> values) {
    if (values.any((value) => value < 0 || value > 100)) return false;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return total >= 98 && total <= 102;
  }

  static void _requireObservedGoals(double h, double a) {
    if (!h.isFinite || !a.isFinite || h <= 0 || a <= 0) {
      throw ArgumentError('xG mancanti o non validi per confronto P21B.');
    }
  }
}
