import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_simulation_learning_validation_service.dart';

/// P21L: pesi sperimentali SOLO SHADOW. Non vengono applicati al motore
/// delle schedine, alle analisi ufficiali o ai record originali prepartita.
class SmartBetSimulationShadowPolicy {
  final String engine;
  final String market;
  final String modelVersion;
  final double simulationWeight;
  final double validationImprovement;
  final int trainingCases;
  final int validationCases;
  final DateTime promotedAt;

  const SmartBetSimulationShadowPolicy({
    required this.engine,
    required this.market,
    required this.modelVersion,
    required this.simulationWeight,
    required this.validationImprovement,
    required this.trainingCases,
    required this.validationCases,
    required this.promotedAt,
  });

  String get key => '$engine|$market|$modelVersion';

  Map<String, Object> toJson() => {
    'engine': engine,
    'market': market,
    'modelVersion': modelVersion,
    'simulationWeight': simulationWeight,
    'validationImprovement': validationImprovement,
    'trainingCases': trainingCases,
    'validationCases': validationCases,
    'promotedAt': promotedAt.toUtc().toIso8601String(),
  };

  static SmartBetSimulationShadowPolicy? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final engine = value['engine']?.toString().toUpperCase() ?? '';
      final market = value['market']?.toString().toUpperCase() ?? '';
      final version = value['modelVersion']?.toString() ?? '';
      final weight = value['simulationWeight'];
      final gain = value['validationImprovement'];
      final trained = value['trainingCases'];
      final verified = value['validationCases'];
      final at = DateTime.parse(value['promotedAt'].toString()).toUtc();
      if (engine.isEmpty ||
          market.isEmpty ||
          version.isEmpty ||
          weight is! num ||
          !weight.isFinite ||
          weight <= 0 ||
          weight > 0.5 ||
          gain is! num ||
          !gain.isFinite ||
          gain <= 0 ||
          trained is! int ||
          trained < 70 ||
          verified is! int ||
          verified < 50) {
        return null;
      }
      return SmartBetSimulationShadowPolicy(
        engine: engine,
        market: market,
        modelVersion: version,
        simulationWeight: weight.toDouble(),
        validationImprovement: gain.toDouble(),
        trainingCases: trained,
        validationCases: verified,
        promotedAt: at,
      );
    } catch (_) {
      return null;
    }
  }
}

class SmartBetShadowPolicyRefreshReport {
  final int promoted;
  final int rolledBack;
  final int rejected;
  final bool enabled;
  const SmartBetShadowPolicyRefreshReport({
    required this.promoted,
    required this.rolledBack,
    required this.rejected,
    required this.enabled,
  });
}

class SmartBetSimulationShadowPolicyService {
  static const storageKey = 'smartbet_p21l_shadow_policies_v1';
  static const int minTraining = 70;
  static const int minValidation = 50;
  static const int minTrainingDays = 14;
  static const int minValidationDays = 10;
  static const double minimumGain = 0.003;

  /// Richiede consenso esplicito per aggiornare lo stato locale.
  /// Se disattivato, non promuove alcun esperimento.
  Future<SmartBetShadowPolicyRefreshReport> refresh({
    required SmartBetSimulationLearningReport report,
    required bool optedIn,
    required DateTime asOf,
  }) async {
    if (!optedIn) {
      return const SmartBetShadowPolicyRefreshReport(
        promoted: 0,
        rolledBack: 0,
        rejected: 0,
        enabled: false,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final current = _read(prefs);
    var promoted = 0;
    var rolledBack = 0;
    var rejected = 0;
    for (final result in report.markets) {
      final key =
          '${result.engine.trim().toUpperCase()}|'
          '${result.market.trim().toUpperCase()}|${result.modelVersion}';
      final enough =
          result.trainingCases >= minTraining &&
          result.validationCases >= minValidation &&
          result.trainingDays >= minTrainingDays &&
          result.validationDays >= minValidationDays;
      if (!enough) continue;
      final gain = result.validationImprovement;
      final weight = result.candidateSimulationWeight;
      final halvesPositive =
          result.firstValidationHalfImprovement != null &&
          result.secondValidationHalfImprovement != null &&
          result.firstValidationHalfImprovement! > 0 &&
          result.secondValidationHalfImprovement! > 0;
      final accepted =
          result.trialSuggested &&
          gain != null &&
          gain.isFinite &&
          gain >= minimumGain &&
          halvesPositive &&
          weight != null &&
          weight.isFinite &&
          weight > 0 &&
          weight <= 0.5;
      if (accepted) {
        final previous = current[key];
        // Non sovrascrivere una policy gia' testata con meno dati.
        if (previous == null ||
            result.validationCases > previous.validationCases) {
          current[key] = SmartBetSimulationShadowPolicy(
            engine: result.engine.trim().toUpperCase(),
            market: result.market.trim().toUpperCase(),
            modelVersion: result.modelVersion,
            simulationWeight: weight,
            validationImprovement: gain,
            trainingCases: result.trainingCases,
            validationCases: result.validationCases,
            promotedAt: asOf.toUtc(),
          );
          promoted++;
        }
      } else if (current.containsKey(key) &&
          gain != null &&
          gain <= 0 &&
          result.validationCases > current[key]!.validationCases) {
        // Rollback solo con un holdout PIU' GRANDE e peggioramento misurato.
        current.remove(key);
        rolledBack++;
      } else {
        rejected++;
      }
    }
    await prefs.setString(
      storageKey,
      jsonEncode({
        'schema': 'smartbet_p21l_shadow_policies_v1',
        'policies': current.values.map((p) => p.toJson()).toList(),
      }),
    );
    return SmartBetShadowPolicyRefreshReport(
      promoted: promoted,
      rolledBack: rolledBack,
      rejected: rejected,
      enabled: true,
    );
  }

  Future<List<SmartBetSimulationShadowPolicy>> readPolicies() async {
    return List.unmodifiable(
      _read(await SharedPreferences.getInstance()).values,
    );
  }

  Future<void> disableAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  /// Restituisce soltanto una probabilita SHADOW, non quella ufficiale.
  Future<double> shadowBlend({
    required String engine,
    required String market,
    required String modelVersion,
    required double original,
    required double simulated,
  }) async {
    if (!original.isFinite ||
        original < 0 ||
        original > 1 ||
        !simulated.isFinite ||
        simulated < 0 ||
        simulated > 1) {
      throw ArgumentError('Probabilita non valide');
    }
    final policies = _read(await SharedPreferences.getInstance());
    final key =
        '${engine.trim().toUpperCase()}|'
        '${market.trim().toUpperCase()}|$modelVersion';
    final weight = policies[key]?.simulationWeight ?? 0.0;
    return (original * (1 - weight) + simulated * weight)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static Map<String, SmartBetSimulationShadowPolicy> _read(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['schema'] != 'smartbet_p21l_shadow_policies_v1' ||
          decoded['policies'] is! List)
        return {};
      final result = <String, SmartBetSimulationShadowPolicy>{};
      for (final item in decoded['policies'] as List) {
        final policy = SmartBetSimulationShadowPolicy.fromJson(item);
        if (policy != null) result[policy.key] = policy;
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}
