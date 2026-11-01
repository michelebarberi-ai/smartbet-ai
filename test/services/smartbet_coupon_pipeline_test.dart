import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_coupon_service.dart';

MatchModel fixture(int id) => MatchModel(
  fixtureId: id,
  homeTeamId: id * 2,
  awayTeamId: id * 2 + 1,
  homeTeam: 'Casa $id',
  awayTeam: 'Ospite $id',
  league: 'Campionato Test',
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

AnalysisResult fakeAnalysis({
  String audit = 'CONFIRM',
  List<String> blocked = const <String>[],
}) => AnalysisResult(
  smartScore: 82,
  predictionConfidence: 82,
  dataConfidence: 80,
  sportsAuditStatus: audit,
  sportsAuditBlockedMarkets: blocked,
  homeProbability: 65,
  drawProbability: 20,
  awayProbability: 15,
  over25Probability: 72,
  goalProbability: 80,
  prediction: '1',
  valueBet: '',
  risk: 'Basso',
  explanation: '',
  // Lo Stake Engine non approva e sceglie un altro esito.
  // Non deve influenzare la selezione sportiva.
  shouldBet: false,
  stakeOutcome: '2',
  stakeOdd: 12,
  recommendedStakePercent: 4,
);

FixtureMarketOdds fakeOdds(
  int fixtureId, {
  double goalOdd = 1.40,
  double overOdd = 1.65,
}) {
  BestOdd quoted(String market, double odd) => BestOdd(
    outcome: market,
    odd: odd,
    bookmakerId: 1,
    bookmakerName: 'Bookmaker Test',
  );

  return FixtureMarketOdds(
    fixtureId: fixtureId,
    matchWinner: null,
    bookmakerCount: 1,
    bestByOutcome: {
      'GOAL': quoted('GOAL', goalOdd),
      'OVER 2.5': quoted('OVER 2.5', overOdd),
      '1': quoted('1', 3.50),
    },
  );
}

SmartBetCouponService fakeService({
  double goalOdd = 1.40,
  double overOdd = 1.65,
  String Function(int)? auditForFixture,
  List<String> Function(int)? blockedForFixture,
  bool missingOdds = false,
}) {
  return SmartBetCouponService(
    analysisProvider: (match) async => fakeAnalysis(
      audit: auditForFixture?.call(match.fixtureId) ?? 'CONFIRM',
      blocked: blockedForFixture?.call(match.fixtureId) ?? const <String>[],
    ),
    oddsProvider: (id) async =>
        missingOdds ? null : fakeOdds(id, goalOdd: goalOdd, overOdd: overOdd),
  );
}

void main() {
  final matches = [1, 2, 3, 4].map(fixture).toList();

  test('Premium, Bilanciata e Value generano schedine', () async {
    final result = await fakeService().buildCouponSet(matches: matches);

    expect(result.premium.hasCoupon, isTrue);
    expect(result.balanced.hasCoupon, isTrue);
    expect(result.value.hasCoupon, isTrue);

    expect(result.premium.selectionCount, 2);
    expect(result.balanced.selectionCount, 4);
    expect(result.value.selectionCount, 4);

    for (final selection in result.value.selections) {
      expect(selection.outcome, 'GOAL');
      expect(selection.bookmaker, 'Bookmaker Test');
      expect(selection.odd, 1.40);
    }
  });

  test('Una quota molto alta non cambia le selezioni', () async {
    final normal = await fakeService(
      goalOdd: 1.40,
    ).buildCouponSet(matches: matches);

    final high = await fakeService(
      goalOdd: 8.90,
    ).buildCouponSet(matches: matches);

    for (final pair in [
      (normal.premium, high.premium),
      (normal.balanced, high.balanced),
      (normal.value, high.value),
    ]) {
      final a = pair.$1.selections;
      final b = pair.$2.selections;

      expect(
        a.map((e) => '${e.match.fixtureId}:${e.outcome}').toList(),
        b.map((e) => '${e.match.fixtureId}:${e.outcome}').toList(),
      );

      expect(
        pair.$1.estimatedCombinedProbability,
        pair.$2.estimatedCombinedProbability,
      );
      expect(pair.$1.riskLevel, pair.$2.riskLevel);
    }
  });

  test('Quota sotto 1.25: usa il mercato successivo', () async {
    final result = await fakeService(
      goalOdd: 1.24,
    ).buildCouponSet(matches: [fixture(1)], minimumRequired: 1);

    expect(result.premium.hasCoupon, isTrue);
    expect(result.premium.selections.single.outcome, 'OVER 2.5');
    expect(result.premium.selections.single.odd, 1.65);
  });

  test('Auditor blocca contraddizioni e analisi non verificate', () async {
    final result = await fakeService(
      auditForFixture: (id) {
        if (id == 3) return 'STRONG_CONTRADICTION';
        if (id == 4) return 'NOT_RUN';
        return 'CONFIRM';
      },
    ).buildCouponSet(matches: matches);

    expect(result.premium.selectionCount, 2);

    for (final selection in result.premium.selections) {
      expect(selection.match.fixtureId, isNot(3));
      expect(selection.match.fixtureId, isNot(4));
    }

    expect(result.balanced.hasCoupon, isFalse);
    expect(result.value.hasCoupon, isFalse);
  });

  test('Nessuno stake ereditato da un altro pronostico', () async {
    final result = await fakeService().buildCouponSet(matches: matches);

    expect(result.premium.recommendedStakePercent, 0);
    expect(result.balanced.recommendedStakePercent, 0);
    expect(result.value.recommendedStakePercent, 0);

    expect(result.premium.selections.first.outcome, 'GOAL');
    expect(result.premium.selections.first.analysis.stakeOutcome, '2');
  });

  test('Auditor blocca Goal ma conserva Over 2.5', () async {
    final result = await fakeService(
      auditForFixture: (_) => 'DOUBT',
      blockedForFixture: (_) => ['BTTS YES'],
    ).buildCouponSet(matches: matches);

    expect(result.premium.hasCoupon, isTrue);
    expect(result.balanced.hasCoupon, isTrue);
    expect(result.value.hasCoupon, isTrue);

    for (final profile in [result.premium, result.balanced, result.value]) {
      for (final selection in profile.selections) {
        expect(selection.outcome, 'OVER 2.5');
        expect(selection.analysis.goalProbability, 80);
      }
    }
  });

  test('Contraddizione globale mantiene il veto sulla partita', () async {
    final result = await fakeService(
      auditForFixture: (_) => 'STRONG_CONTRADICTION',
      blockedForFixture: (_) => ['GOAL'],
    ).buildCouponSet(matches: matches);

    expect(result.hasAnyCoupon, isFalse);
    expect(result.availableProfiles, 0);
  });

  test('Quote assenti: nessuna schedina eseguibile', () async {
    final result = await fakeService(
      missingOdds: true,
    ).buildCouponSet(matches: matches);

    expect(result.hasAnyCoupon, isFalse);
    expect(result.availableProfiles, 0);
  });
}
