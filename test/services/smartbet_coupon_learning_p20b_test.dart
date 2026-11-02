import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_coupon_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shared_local_learning_service.dart';

MatchModel _match(int id) => MatchModel(
  fixtureId: id,
  homeTeamId: id * 2,
  awayTeamId: id * 2 + 1,
  homeTeam: 'Casa $id',
  awayTeam: 'Ospite $id',
  league: 'Test',
  leagueId: 1,
  country: 'Italia',
  countryCode: 'IT',
  date: '2026-12-01T18:00:00+01:00',
  leagueType: 'domestic',
  isEuropeanCup: false,
  isFriendly: false,
  isNational: false,
  aiWeight: 0.7,
  smartScore: 82,
  homeWin: 65,
  draw: 20,
  awayWin: 15,
  valueBet: '',
  odd: 0,
);

AnalysisResult _analysis() => AnalysisResult(
  smartScore: 82,
  predictionConfidence: 82,
  dataConfidence: 80,
  sportsAuditStatus: 'CONFIRM',
  homeProbability: 65,
  drawProbability: 20,
  awayProbability: 15,
  goalProbability: 80,
  over25Probability: 72,
  prediction: '1',
  valueBet: '',
  risk: 'Basso',
  explanation: '',
  shouldBet: false,
  stakeOutcome: '2',
  stakeOdd: 12,
  recommendedStakePercent: 0,
);

FixtureMarketOdds _odds(int id) {
  BestOdd make(String name, double odd) => BestOdd(
    outcome: name,
    odd: odd,
    bookmakerId: 1,
    bookmakerName: 'Quote Test',
  );
  return FixtureMarketOdds(
    fixtureId: id,
    matchWinner: null,
    bookmakerCount: 1,
    bestByOutcome: {
      'GOAL': make('GOAL', 1.40),
      'OVER 2.5': make('OVER 2.5', 1.65),
    },
  );
}

void main() {
  final matches = [1, 2, 3, 4].map(_match).toList();

  test('OFF: usa probabilità originale e nessuna calibrazione', () async {
    final saved = <SmartBetCouponSelection>[];
    final service = SmartBetCouponService(
      analysisProvider: (_) async => _analysis(),
      oddsProvider: (id) async => _odds(id),
      learningProvider: () async => null,
      registrationProvider: (selection) async => saved.add(selection),
    );
    final coupons = await service.buildCouponSet(matches: matches);
    expect(coupons.value.selectionCount, 4);
    for (final selection in coupons.value.selections) {
      expect(selection.outcome, 'GOAL');
      expect(selection.originalProbabilityPercent, 80);
      expect(selection.effectiveProbabilityPercent, 80);
      expect(selection.hasLocalCalibration, isFalse);
    }
    expect(
      coupons.value.estimatedCombinedProbability,
      closeTo(0.4096, 0.00001),
    );
    // Premium/Bilanciata/Value riusano le stesse fixture: una sola registrazione.
    expect(saved.length, 4);
    expect(saved.map((e) => e.match.fixtureId).toSet().length, 4);
  });

  test('Correzione autorizzata: incide su ranking e stima combinata', () async {
    final saved = <SmartBetCouponSelection>[];
    var evaluated = 0;
    final service = SmartBetCouponService(
      analysisProvider: (_) async => _analysis(),
      oddsProvider: (id) async => _odds(id),
      learningProvider: () async => null,
      learningEvaluator:
          ({
            required session,
            required market,
            required originalPercent,
            required fixtureId,
            required hasRealOdd,
          }) {
            evaluated++;
            expect(market, 'GOAL');
            expect(originalPercent, 80);
            expect(hasRealOdd, isTrue);
            return const SmartBetSharedLearningProbability(
              originalPercent: 80,
              percent: 70,
              samples: 135,
            );
          },
      registrationProvider: (selection) async => saved.add(selection),
    );
    final coupons = await service.buildCouponSet(matches: matches);
    expect(evaluated, 4);
    expect(coupons.value.selectionCount, 4);
    expect(
      coupons.value.estimatedCombinedProbability,
      closeTo(0.2401, 0.00001),
    );
    for (final selection in coupons.value.selections) {
      expect(selection.outcome, 'GOAL');
      expect(selection.sportsPick!.probability, 80); // storico originale
      expect(selection.effectiveProbabilityPercent, 70);
      expect(selection.hasLocalCalibration, isTrue);
      expect(selection.learningSamples, 135);
    }
    expect(saved.length, 4);
    expect(saved.every((e) => e.originalProbabilityPercent == 80), isTrue);
  });

  test('Nessuna quota reale: non calibra ne registra selezioni', () async {
    var evaluated = 0;
    var registered = 0;
    final service = SmartBetCouponService(
      analysisProvider: (_) async => _analysis(),
      oddsProvider: (_) async => null,
      learningProvider: () async => null,
      learningEvaluator:
          ({
            required session,
            required market,
            required originalPercent,
            required fixtureId,
            required hasRealOdd,
          }) {
            evaluated++;
            return SmartBetSharedLearningProbability(
              originalPercent: originalPercent,
              percent: originalPercent,
            );
          },
      registrationProvider: (_) async {
        registered++;
      },
    );
    final coupons = await service.buildCouponSet(matches: matches);
    expect(coupons.hasAnyCoupon, isFalse);
    expect(evaluated, 0);
    expect(registered, 0);
  });

  test('Errore nel salvataggio non impedisce la schedina', () async {
    final service = SmartBetCouponService(
      analysisProvider: (_) async => _analysis(),
      oddsProvider: (id) async => _odds(id),
      learningProvider: () async => null,
      registrationProvider: (_) async => throw StateError('test'),
    );
    final coupons = await service.buildCouponSet(matches: matches);
    expect(coupons.value.selectionCount, 4);
  });
}
