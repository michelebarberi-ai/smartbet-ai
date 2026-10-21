import 'dart:math' as math;

import 'goalvdline_comparison_store.dart';

class GoalVdLineLeagueStrengthBucketStats {
  final int count;

  final int homeWins;
  final int draws;
  final int awayWins;

  final int strongerLeagueWins;
  final int weakerLeagueWins;
  final int zeroRatingDifference;

  final double meanRatingDifference;
  final double meanAbsoluteRatingDifference;
  final double meanSnr;

  final double meanActualGoalDifference;
  final double meanAlignedGoalDifference;

  final double? ratingGoalDifferenceCorrelation;

  const GoalVdLineLeagueStrengthBucketStats({
    required this.count,
    required this.homeWins,
    required this.draws,
    required this.awayWins,
    required this.strongerLeagueWins,
    required this.weakerLeagueWins,
    required this.zeroRatingDifference,
    required this.meanRatingDifference,
    required this.meanAbsoluteRatingDifference,
    required this.meanSnr,
    required this.meanActualGoalDifference,
    required this.meanAlignedGoalDifference,
    required this.ratingGoalDifferenceCorrelation,
  });

  double get drawRate => _percentage(draws, count);

  /// Vittorie della squadra appartenente alla lega più forte
  /// considerando anche i pareggi nel denominatore.
  double get strongerLeagueWinRate =>
      _percentage(strongerLeagueWins, count - zeroRatingDifference);

  /// Come sopra, ma limitato agli esiti non pareggiati.
  double get strongerLeagueDecisiveWinRate =>
      _percentage(strongerLeagueWins, strongerLeagueWins + weakerLeagueWins);

  static double _percentage(int numerator, int denominator) {
    if (denominator <= 0) {
      return 0.0;
    }

    return numerator / denominator * 100.0;
  }
}

class GoalVdLineLeagueStrengthEvaluation {
  final String modelVersion;

  // Funnel prima delle statistiche.
  final int totalRecords;
  final int recordsWithLeagueStrength;
  final int matchingModelVersionRecords;
  final int prospectiveRecords;
  final int completedProspectiveRecords;
  final int analyzedRecords;

  // Record rifiutati dopo il filtro prospettico + risultato.
  final int excludedOddsUsed;
  final int excludedAdjustmentApplied;
  final int excludedInvalidPayload;

  final GoalVdLineLeagueStrengthBucketStats overall;

  final Map<String, GoalVdLineLeagueStrengthBucketStats> byGate;
  final Map<String, GoalVdLineLeagueStrengthBucketStats> bySnrBand;
  final Map<String, GoalVdLineLeagueStrengthBucketStats>
  byAbsoluteRatingDifferenceBand;
  final Map<String, GoalVdLineLeagueStrengthBucketStats> byRatingDifferenceSign;
  final Map<String, GoalVdLineLeagueStrengthBucketStats> byCompetition;

  const GoalVdLineLeagueStrengthEvaluation({
    required this.modelVersion,
    required this.totalRecords,
    required this.recordsWithLeagueStrength,
    required this.matchingModelVersionRecords,
    required this.prospectiveRecords,
    required this.completedProspectiveRecords,
    required this.analyzedRecords,
    required this.excludedOddsUsed,
    required this.excludedAdjustmentApplied,
    required this.excludedInvalidPayload,
    required this.overall,
    required this.byGate,
    required this.bySnrBand,
    required this.byAbsoluteRatingDifferenceBand,
    required this.byRatingDifferenceSign,
    required this.byCompetition,
  });

  bool get hasUsableSample => analyzedRecords > 0;
}

class GoalVdLineLeagueStrengthEvaluator {
  static const String d2b2ModelVersion =
      'd2b2_ls_v1_prev1_qual05_main1_lambda3_gate1_c90v1_mainstagev1';

  final GoalVdLineComparisonStore _store;

  GoalVdLineLeagueStrengthEvaluator({GoalVdLineComparisonStore? store})
    : _store = store ?? GoalVdLineComparisonStore.instance;

  Future<GoalVdLineLeagueStrengthEvaluation> calculate({
    String modelVersion = d2b2ModelVersion,
  }) async {
    final records = await _store.readAll();

    return calculateFromRecords(records, modelVersion: modelVersion);
  }

  GoalVdLineLeagueStrengthEvaluation calculateFromRecords(
    List<GoalVdLineComparisonRecord> records, {
    String modelVersion = d2b2ModelVersion,
  }) {
    var recordsWithLeagueStrength = 0;
    var matchingModelVersionRecords = 0;
    var prospectiveRecords = 0;
    var completedProspectiveRecords = 0;

    var excludedOddsUsed = 0;
    var excludedAdjustmentApplied = 0;
    var excludedInvalidPayload = 0;

    final samples = <_LeagueStrengthSample>[];

    for (final record in records) {
      final leagueStrength = record.leagueStrength;

      if (leagueStrength == null) {
        continue;
      }

      recordsWithLeagueStrength++;

      if (leagueStrength['modelVersion']?.toString() != modelVersion) {
        continue;
      }

      matchingModelVersionRecords++;

      if (_toBool(leagueStrength['prospectiveEligible']) != true) {
        continue;
      }

      prospectiveRecords++;

      if (!record.hasActualResult) {
        continue;
      }

      completedProspectiveRecords++;

      // D2B.3 deve restare completamente odds-free.
      if (_toBool(leagueStrength['oddsUsed']) != false) {
        excludedOddsUsed++;
        continue;
      }

      // Valutiamo esclusivamente il modello SHADOW non applicato.
      if (_toBool(leagueStrength['adjustmentApplied']) != false) {
        excludedAdjustmentApplied++;
        continue;
      }

      final ratingDifference = _toDouble(leagueStrength['ratingDifference']);
      final snr = _toDouble(leagueStrength['snr']);
      final passesEvidenceGate = _toBool(leagueStrength['passesEvidenceGate']);

      final actual = record.actualResult;
      final homeGoals = _toInt(actual?['homeGoals']);
      final awayGoals = _toInt(actual?['awayGoals']);

      if (ratingDifference == null ||
          !ratingDifference.isFinite ||
          snr == null ||
          !snr.isFinite ||
          passesEvidenceGate == null ||
          homeGoals == null ||
          awayGoals == null ||
          homeGoals < 0 ||
          awayGoals < 0) {
        excludedInvalidPayload++;
        continue;
      }

      final competition = record.league.trim().isEmpty
          ? 'Competizione N/D'
          : record.league.trim();

      samples.add(
        _LeagueStrengthSample(
          ratingDifference: ratingDifference,
          snr: snr,
          passesEvidenceGate: passesEvidenceGate,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
          competition: competition,
        ),
      );
    }

    return GoalVdLineLeagueStrengthEvaluation(
      modelVersion: modelVersion,
      totalRecords: records.length,
      recordsWithLeagueStrength: recordsWithLeagueStrength,
      matchingModelVersionRecords: matchingModelVersionRecords,
      prospectiveRecords: prospectiveRecords,
      completedProspectiveRecords: completedProspectiveRecords,
      analyzedRecords: samples.length,
      excludedOddsUsed: excludedOddsUsed,
      excludedAdjustmentApplied: excludedAdjustmentApplied,
      excludedInvalidPayload: excludedInvalidPayload,
      overall: _stats(samples),
      byGate: _groupedStats(
        samples,
        (sample) => sample.passesEvidenceGate ? 'GATE PASS' : 'GATE FAIL',
      ),
      bySnrBand: _groupedStats(samples, (sample) {
        if (sample.snr < 1.0) {
          return 'SNR < 1.0';
        }

        if (sample.snr < 2.0) {
          return 'SNR 1.0–<2.0';
        }

        if (sample.snr < 3.0) {
          return 'SNR 2.0–<3.0';
        }

        return 'SNR ≥ 3.0';
      }),
      byAbsoluteRatingDifferenceBand: _groupedStats(samples, (sample) {
        final difference = sample.ratingDifference.abs();

        if (difference < 50.0) {
          return '|Δ rating| < 50';
        }

        if (difference < 100.0) {
          return '|Δ rating| 50–<100';
        }

        if (difference < 150.0) {
          return '|Δ rating| 100–<150';
        }

        return '|Δ rating| ≥ 150';
      }),
      byRatingDifferenceSign: _groupedStats(samples, (sample) {
        if (sample.ratingDifference > 0.0) {
          return 'HOME LEAGUE STRONGER';
        }

        if (sample.ratingDifference < 0.0) {
          return 'AWAY LEAGUE STRONGER';
        }

        return 'EQUAL RATING';
      }),
      byCompetition: _groupedStats(samples, (sample) => sample.competition),
    );
  }

  Map<String, GoalVdLineLeagueStrengthBucketStats> _groupedStats(
    List<_LeagueStrengthSample> samples,
    String Function(_LeagueStrengthSample sample) keyFor,
  ) {
    final grouped = <String, List<_LeagueStrengthSample>>{};

    for (final sample in samples) {
      (grouped[keyFor(sample)] ??= <_LeagueStrengthSample>[]).add(sample);
    }

    final keys = grouped.keys.toList()..sort();

    return Map<String, GoalVdLineLeagueStrengthBucketStats>.unmodifiable({
      for (final key in keys) key: _stats(grouped[key]!),
    });
  }

  GoalVdLineLeagueStrengthBucketStats _stats(
    List<_LeagueStrengthSample> samples,
  ) {
    if (samples.isEmpty) {
      return const GoalVdLineLeagueStrengthBucketStats(
        count: 0,
        homeWins: 0,
        draws: 0,
        awayWins: 0,
        strongerLeagueWins: 0,
        weakerLeagueWins: 0,
        zeroRatingDifference: 0,
        meanRatingDifference: 0.0,
        meanAbsoluteRatingDifference: 0.0,
        meanSnr: 0.0,
        meanActualGoalDifference: 0.0,
        meanAlignedGoalDifference: 0.0,
        ratingGoalDifferenceCorrelation: null,
      );
    }

    var homeWins = 0;
    var draws = 0;
    var awayWins = 0;

    var strongerLeagueWins = 0;
    var weakerLeagueWins = 0;
    var zeroRatingDifference = 0;

    var ratingTotal = 0.0;
    var absoluteRatingTotal = 0.0;
    var snrTotal = 0.0;

    var actualGoalDifferenceTotal = 0.0;
    var alignedGoalDifferenceTotal = 0.0;

    for (final sample in samples) {
      final goalDifference = sample.homeGoals - sample.awayGoals;

      if (goalDifference > 0) {
        homeWins++;
      } else if (goalDifference < 0) {
        awayWins++;
      } else {
        draws++;
      }

      final direction = sample.ratingDifference > 0.0
          ? 1
          : sample.ratingDifference < 0.0
          ? -1
          : 0;

      if (direction == 0) {
        zeroRatingDifference++;
      } else if (goalDifference != 0) {
        if (direction * goalDifference > 0) {
          strongerLeagueWins++;
        } else {
          weakerLeagueWins++;
        }
      }

      ratingTotal += sample.ratingDifference;
      absoluteRatingTotal += sample.ratingDifference.abs();
      snrTotal += sample.snr;

      actualGoalDifferenceTotal += goalDifference;
      alignedGoalDifferenceTotal += direction * goalDifference;
    }

    final count = samples.length;

    return GoalVdLineLeagueStrengthBucketStats(
      count: count,
      homeWins: homeWins,
      draws: draws,
      awayWins: awayWins,
      strongerLeagueWins: strongerLeagueWins,
      weakerLeagueWins: weakerLeagueWins,
      zeroRatingDifference: zeroRatingDifference,
      meanRatingDifference: ratingTotal / count,
      meanAbsoluteRatingDifference: absoluteRatingTotal / count,
      meanSnr: snrTotal / count,
      meanActualGoalDifference: actualGoalDifferenceTotal / count,
      meanAlignedGoalDifference: alignedGoalDifferenceTotal / count,
      ratingGoalDifferenceCorrelation: _pearsonRatingVsGoalDifference(samples),
    );
  }

  double? _pearsonRatingVsGoalDifference(List<_LeagueStrengthSample> samples) {
    if (samples.length < 2) {
      return null;
    }

    final count = samples.length.toDouble();

    final meanRating =
        samples
            .map((sample) => sample.ratingDifference)
            .reduce((a, b) => a + b) /
        count;

    final meanGoalDifference =
        samples
            .map((sample) => (sample.homeGoals - sample.awayGoals).toDouble())
            .reduce((a, b) => a + b) /
        count;

    var covariance = 0.0;
    var ratingVariance = 0.0;
    var goalVariance = 0.0;

    for (final sample in samples) {
      final ratingDelta = sample.ratingDifference - meanRating;

      final goalDelta =
          (sample.homeGoals - sample.awayGoals) - meanGoalDifference;

      covariance += ratingDelta * goalDelta;
      ratingVariance += ratingDelta * ratingDelta;
      goalVariance += goalDelta * goalDelta;
    }

    if (ratingVariance <= 0.0 || goalVariance <= 0.0) {
      return null;
    }

    return covariance / math.sqrt(ratingVariance * goalVariance);
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  bool? _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    final normalized = value?.toString().trim().toLowerCase();

    if (normalized == 'true') {
      return true;
    }

    if (normalized == 'false') {
      return false;
    }

    return null;
  }
}

class _LeagueStrengthSample {
  final double ratingDifference;
  final double snr;
  final bool passesEvidenceGate;

  final int homeGoals;
  final int awayGoals;

  final String competition;

  const _LeagueStrengthSample({
    required this.ratingDifference,
    required this.snr,
    required this.passesEvidenceGate,
    required this.homeGoals,
    required this.awayGoals,
    required this.competition,
  });
}
