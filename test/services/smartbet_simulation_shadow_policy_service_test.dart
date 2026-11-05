import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_learning_validation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_policy_service.dart';

SmartBetSimulationLearningMarketResult candidate({
  int training = 80,
  int validation = 60,
  double? weight = 0.25,
  double oldScore = 0.22,
  double newScore = 0.20,
  SmartBetSimulationLearningDecision decision =
      SmartBetSimulationLearningDecision.trialCandidate,
}) => SmartBetSimulationLearningMarketResult(
  engine: 'SMARTBET',
  market: 'X',
  modelVersion: 'p21a-bivariate-poisson-v1',
  decision: decision,
  eligibleCases: training + validation,
  trainingCases: training,
  validationCases: validation,
  lowQualityCases: 10,
  trainingDays: 18,
  validationDays: 12,
  candidateSimulationWeight: weight,
  trainingOriginalBrier: 0.24,
  trainingCandidateBrier: 0.21,
  validationOriginalBrier: oldScore,
  validationCandidateBrier: newScore,
  firstValidationHalfImprovement: oldScore - newScore,
  secondValidationHalfImprovement: oldScore - newScore,
);

SmartBetSimulationLearningReport report(
  SmartBetSimulationLearningMarketResult market,
) => SmartBetSimulationLearningReport(
  totalSnapshots: 300,
  pendingSnapshots: 10,
  conflictingSnapshots: 0,
  invalidSnapshots: 0,
  duplicateSnapshots: 0,
  unmatchedPairs: 0,
  unsupportedPairs: 0,
  markets: [market],
);

void main() {
  final service = SmartBetSimulationShadowPolicyService();
  final asOf = DateTime.utc(2026, 11, 4);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('P21L: consenso necessario prima del salvataggio', () async {
    final result = await service.refresh(
      report: report(candidate()),
      optedIn: false,
      asOf: asOf,
    );
    expect(result.enabled, isFalse);
    expect(await service.readPolicies(), isEmpty);
  });
  test('P21L: promuove soltanto un trial shadow validato', () async {
    final result = await service.refresh(
      report: report(candidate()),
      optedIn: true,
      asOf: asOf,
    );
    expect(result.promoted, 1);
    final p = (await service.readPolicies()).single;
    expect(p.simulationWeight, 0.25);
    expect(p.market, 'X');
    expect(p.validationCases, 60);
  });
  test('P21L: blend non altera il dato originario', () async {
    await service.refresh(
      report: report(candidate()),
      optedIn: true,
      asOf: asOf,
    );
    final transformed = await service.shadowBlend(
      engine: 'SMARTBET',
      market: 'X',
      modelVersion: 'p21a-bivariate-poisson-v1',
      original: 0.25,
      simulated: 0.45,
    );
    expect(transformed, closeTo(0.30, 1e-10));
    final raw = await service.shadowBlend(
      engine: 'DIEGO',
      market: 'X',
      modelVersion: 'p21a-bivariate-poisson-v1',
      original: 0.25,
      simulated: 0.45,
    );
    expect(raw, 0.25);
  });
  test('P21L: respinge il peso troppo aggressivo', () async {
    final result = await service.refresh(
      report: report(candidate(weight: 1.0)),
      optedIn: true,
      asOf: asOf,
    );
    expect(result.promoted, 0);
    expect(await service.readPolicies(), isEmpty);
  });
  test('P21L: campione non sufficiente impedisce la promozione', () async {
    final result = await service.refresh(
      report: report(candidate(training: 15, validation: 10)),
      optedIn: true,
      asOf: asOf,
    );
    expect(result.promoted, 0);
  });
  test('P21L: peggioramento in holdout piu ampio provoca rollback', () async {
    await service.refresh(
      report: report(candidate()),
      optedIn: true,
      asOf: asOf,
    );
    final result = await service.refresh(
      report: report(
        candidate(
          validation: 80,
          oldScore: 0.20,
          newScore: 0.23,
          decision: SmartBetSimulationLearningDecision.validationFailed,
        ),
      ),
      optedIn: true,
      asOf: asOf.add(const Duration(days: 30)),
    );
    expect(result.rolledBack, 1);
    expect(await service.readPolicies(), isEmpty);
  });
  test('P21L: nessun rollback per un campione inferiore', () async {
    await service.refresh(
      report: report(candidate()),
      optedIn: true,
      asOf: asOf,
    );
    final result = await service.refresh(
      report: report(
        candidate(
          validation: 55,
          oldScore: 0.20,
          newScore: 0.23,
          decision: SmartBetSimulationLearningDecision.validationFailed,
        ),
      ),
      optedIn: true,
      asOf: asOf.add(const Duration(days: 30)),
    );
    expect(result.rolledBack, 0);
    expect((await service.readPolicies()).length, 1);
  });
  test('P21L: cancellazione ripristina il modello originale shadow', () async {
    await service.refresh(
      report: report(candidate()),
      optedIn: true,
      asOf: asOf,
    );
    await service.disableAll();
    expect(await service.readPolicies(), isEmpty);
  });
  test('P21L: rifiuta probabilita non valide', () async {
    await expectLater(
      () => service.shadowBlend(
        engine: 'SMARTBET',
        market: 'X',
        modelVersion: 'v1',
        original: 1.5,
        simulated: 0.2,
      ),
      throwsArgumentError,
    );
  });
  test('P21L: dati corrotti non vengono attivati', () async {
    SharedPreferences.setMockInitialValues({
      SmartBetSimulationShadowPolicyService.storageKey: 'INVALID JSON',
    });
    expect(await service.readPolicies(), isEmpty);
  });
}
