import '../models/analysis_result.dart';
import '../models/match_dossier.dart';
import 'smartbet_contextual_simulation_service.dart';

/// P21N: prova metamorfica delle probabilita' del SOLO simulatore contestuale.
/// A differenza di un audit backend end-to-end, non certifica l'indipendenza
/// del motore remoto SmartBet: quello richiede verificare anche /analyze.
class SmartBetSportingOddsAuditResult {
  final bool passed;
  final int testedMarkets;
  final double maximumDifference;
  const SmartBetSportingOddsAuditResult({
    required this.passed,
    required this.testedMarkets,
    required this.maximumDifference,
  });
}

class SmartBetSportingOddsAuditService {
  final SmartBetContextualSimulationService simulator;
  const SmartBetSportingOddsAuditService({
    this.simulator = const SmartBetContextualSimulationService(),
  });

  SmartBetSportingOddsAuditResult testMetadataInvariance({
    required MatchDossier original,
    required MatchDossier changedMarketMetadata,
    required AnalysisResult baseline,
    required DateTime observedAt,
  }) {
    // Per essere una prova valida, cambiano SOLTANTO le informazioni mercato.
    final a = original.toJson();
    final b = changedMarketMetadata.toJson();
    final contextA = Map<String, dynamic>.from(a['context'] as Map);
    final contextB = Map<String, dynamic>.from(b['context'] as Map);
    contextA.remove('marketInformation');
    contextB.remove('marketInformation');
    a['context'] = contextA;
    b['context'] = contextB;
    if (!_deepEqual(a, b)) {
      throw ArgumentError(
        'Sono cambiati anche dati sportivi, non soltanto quote.',
      );
    }
    final first = simulator.evaluate(
      dossier: original,
      baseline: baseline,
      observedAt: observedAt,
    );
    final second = simulator.evaluate(
      dossier: changedMarketMetadata,
      baseline: baseline,
      observedAt: observedAt,
    );
    final p = first.simulation?.marketProbabilities;
    final q = second.simulation?.marketProbabilities;
    if (p == null || q == null) {
      return const SmartBetSportingOddsAuditResult(
        passed: false,
        testedMarkets: 0,
        maximumDifference: 0,
      );
    }
    var delta = 0.0;
    for (final key in p.keys) {
      final difference = (p[key]! - q[key]!).abs();
      if (difference > delta) delta = difference;
    }
    return SmartBetSportingOddsAuditResult(
      passed: delta <= 1e-12,
      testedMarkets: p.length,
      maximumDifference: delta,
    );
  }

  static bool _deepEqual(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
