import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/goalvdline_comparison_store.dart';
import '../../lib/services/goalvdline_league_strength_evaluator.dart';

void main() {
  const modelVersion = GoalVdLineLeagueStrengthEvaluator.d2b2ModelVersion;

  GoalVdLineComparisonRecord record({
    required int fixtureId,
    String version = modelVersion,
    bool prospectiveEligible = true,
    bool oddsUsed = false,
    bool adjustmentApplied = false,
    Object? ratingDifference = 100.0,
    Object? snr = 2.0,
    Object? passesEvidenceGate = true,
    int? homeGoals = 1,
    int? awayGoals = 0,
    String league = 'Test Competition',
  }) {
    final now = DateTime.utc(2026, 10, 20, 12);

    return GoalVdLineComparisonRecord(
      fixtureId: fixtureId,
      matchLabel: 'Home $fixtureId - Away $fixtureId',
      league: league,
      matchDate: now,
      smartBet: null,
      shadow: null,
      leagueStrength: <String, dynamic>{
        'modelVersion': version,
        'prospectiveEligible': prospectiveEligible,
        'oddsUsed': oddsUsed,
        'adjustmentApplied': adjustmentApplied,
        'ratingDifference': ratingDifference,
        'snr': snr,
        'passesEvidenceGate': passesEvidenceGate,
      },
      actualResult: homeGoals == null || awayGoals == null
          ? null
          : <String, dynamic>{
              'homeGoals': homeGoals,
              'awayGoals': awayGoals,
              'outcome': homeGoals > awayGoals
                  ? '1'
                  : homeGoals < awayGoals
                  ? '2'
                  : 'X',
            },
      createdAt: now,
      updatedAt: now,
    );
  }

  test('D2B.3 funnel accetta solo record prospettici validi', () {
    final evaluator = GoalVdLineLeagueStrengthEvaluator();

    final result = evaluator.calculateFromRecords([
      // Valido.
      record(fixtureId: 1),

      // Versione modello diversa.
      record(fixtureId: 2, version: 'old_model'),

      // Non prospettico.
      record(fixtureId: 3, prospectiveEligible: false),

      // Nessun risultato reale.
      record(fixtureId: 4, homeGoals: null, awayGoals: null),

      // Quote usate: deve essere escluso.
      record(fixtureId: 5, oddsUsed: true),

      // Adjustment già applicato: deve essere escluso.
      record(fixtureId: 6, adjustmentApplied: true),

      // Payload numerico non valido.
      record(fixtureId: 7, ratingDifference: 'invalid'),
    ]);

    expect(result.totalRecords, 7);

    expect(result.recordsWithLeagueStrength, 7);
    expect(result.matchingModelVersionRecords, 6);
    expect(result.prospectiveRecords, 5);
    expect(result.completedProspectiveRecords, 4);

    expect(result.excludedOddsUsed, 1);
    expect(result.excludedAdjustmentApplied, 1);
    expect(result.excludedInvalidPayload, 1);

    expect(result.analyzedRecords, 1);
    expect(result.overall.count, 1);
    expect(result.hasUsableSample, isTrue);
  });

  test('D2B.3 misura direzione, gate, SNR e rating difference', () {
    final evaluator = GoalVdLineLeagueStrengthEvaluator();

    final result = evaluator.calculateFromRecords([
      // Lega di casa più forte -> casa vince.
      record(
        fixtureId: 10,
        ratingDifference: 100.0,
        snr: 2.2,
        passesEvidenceGate: true,
        homeGoals: 2,
        awayGoals: 0,
        league: 'Champions League',
      ),

      // Lega ospite più forte -> ospite vince.
      record(
        fixtureId: 11,
        ratingDifference: -120.0,
        snr: 2.5,
        passesEvidenceGate: true,
        homeGoals: 0,
        awayGoals: 1,
        league: 'Champions League',
      ),

      // Lega casa più forte, ma pareggio.
      record(
        fixtureId: 12,
        ratingDifference: 60.0,
        snr: 1.2,
        passesEvidenceGate: false,
        homeGoals: 1,
        awayGoals: 1,
        league: 'Champions League',
      ),

      // Lega ospite più forte, ma vince la casa.
      record(
        fixtureId: 13,
        ratingDifference: -30.0,
        snr: 0.8,
        passesEvidenceGate: false,
        homeGoals: 2,
        awayGoals: 0,
        league: 'Europa League',
      ),
    ]);

    expect(result.analyzedRecords, 4);

    final overall = result.overall;

    expect(overall.count, 4);

    expect(overall.homeWins, 2);
    expect(overall.draws, 1);
    expect(overall.awayWins, 1);

    expect(overall.strongerLeagueWins, 2);
    expect(overall.weakerLeagueWins, 1);
    expect(overall.zeroRatingDifference, 0);

    expect(overall.strongerLeagueWinRate, closeTo(50.0, 0.0001));

    expect(overall.strongerLeagueDecisiveWinRate, closeTo(66.666666, 0.001));

    expect(overall.meanAlignedGoalDifference, closeTo(0.25, 0.0001));

    expect(overall.ratingGoalDifferenceCorrelation, isNotNull);

    expect(result.byGate['GATE PASS']?.count, 2);
    expect(result.byGate['GATE FAIL']?.count, 2);

    expect(result.bySnrBand['SNR < 1.0']?.count, 1);
    expect(result.bySnrBand['SNR 1.0–<2.0']?.count, 1);
    expect(result.bySnrBand['SNR 2.0–<3.0']?.count, 2);

    expect(result.byAbsoluteRatingDifferenceBand['|Δ rating| < 50']?.count, 1);

    expect(
      result.byAbsoluteRatingDifferenceBand['|Δ rating| 50–<100']?.count,
      1,
    );

    expect(
      result.byAbsoluteRatingDifferenceBand['|Δ rating| 100–<150']?.count,
      2,
    );

    expect(result.byRatingDifferenceSign['HOME LEAGUE STRONGER']?.count, 2);

    expect(result.byRatingDifferenceSign['AWAY LEAGUE STRONGER']?.count, 2);

    expect(result.byCompetition['Champions League']?.count, 3);

    expect(result.byCompetition['Europa League']?.count, 1);
  });
}
