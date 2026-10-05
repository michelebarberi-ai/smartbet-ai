import '../models/goalvdline_match_engine_models.dart';
import '../models/match_dossier.dart';

class GoalVdLineDrawSuitabilityResult {
  final int score;
  final String level;

  final double balanceScore;
  final double seasonDrawScore;
  final double venueDrawScore;
  final double lowScoringScore;
  final double simulatedDrawScore;

  final double xgBalanceScore;

  const GoalVdLineDrawSuitabilityResult({
    required this.score,
    required this.level,
    required this.balanceScore,
    required this.seasonDrawScore,
    required this.venueDrawScore,
    required this.lowScoringScore,
    required this.simulatedDrawScore,
    this.xgBalanceScore = 0.0,
  });
}

class GoalVdLineDrawSuitability {
  const GoalVdLineDrawSuitability._();

  // ============================================================
  // V1
  // ============================================================

  static GoalVdLineDrawSuitabilityResult evaluate({
    required MatchDossier dossier,
    required GoalVdLineMatchEngineResult simulation,
  }) {
    final winProbabilityDifference =
        (simulation.homeWinPercent - simulation.awayWinPercent).abs();

    final balanceScore = (100.0 - (winProbabilityDifference * 1.8))
        .clamp(0.0, 100.0)
        .toDouble();

    final season = _seasonDrawData(dossier);
    final venue = _venueDrawData(dossier);

    final lowScoringScore = (simulation.under25Probability * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    final simulatedDrawScore = ((simulation.drawProbability / 0.40) * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    var weightedScore = 0.0;
    var totalWeight = 0.0;

    void addComponent(double value, double weight) {
      weightedScore += value * weight;
      totalWeight += weight;
    }

    addComponent(balanceScore, 0.30);
    addComponent(simulatedDrawScore, 0.30);
    addComponent(lowScoringScore, 0.20);

    if (season.available) {
      addComponent(season.score, 0.12);
    }

    if (venue.available) {
      addComponent(venue.score, 0.08);
    }

    final rawScore = totalWeight > 0.0
        ? weightedScore / totalWeight
        : simulatedDrawScore;

    final score = rawScore.round().clamp(0, 100);

    return GoalVdLineDrawSuitabilityResult(
      score: score,
      level: _levelForScore(score),
      balanceScore: balanceScore,
      seasonDrawScore: season.score,
      venueDrawScore: venue.score,
      lowScoringScore: lowScoringScore,
      simulatedDrawScore: simulatedDrawScore,
    );
  }

  // ============================================================
  // V2 SPERIMENTALE
  // ============================================================
  //
  // Obiettivo:
  //
  // - xG balance          = segnale primario
  // - equilibrio 1 / 2    = segnale primario
  // - probabilità X       = segnale primario
  // - Under 2.5           = supporto
  // - storico pareggi     = correttivo
  // - venue pareggi       = correttivo
  //
  // La V2 NON modifica ancora il motore principale.
  // ============================================================

  static GoalVdLineDrawSuitabilityResult evaluateV2({
    required MatchDossier dossier,
    required GoalVdLineMatchEngineResult simulation,
  }) {
    final winProbabilityDifference =
        (simulation.homeWinPercent - simulation.awayWinPercent).abs();

    // Più severo rispetto alla V1.
    final balanceScore = (100.0 - (winProbabilityDifference * 2.0))
        .clamp(0.0, 100.0)
        .toDouble();

    // ==========================================================
    // EQUILIBRIO EXPECTED GOALS
    // ==========================================================

    final xgDifference =
        (simulation.expectedHomeGoals - simulation.expectedAwayGoals).abs();

    // ΔxG 0.00 -> 100
    // ΔxG 0.50 -> 65
    // ΔxG 1.00 -> 30
    // ΔxG >=1.43 -> 0
    final xgBalanceScore = (100.0 - (xgDifference * 70.0))
        .clamp(0.0, 100.0)
        .toDouble();

    final season = _seasonDrawData(dossier);
    final venue = _venueDrawData(dossier);

    final lowScoringScore = (simulation.under25Probability * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    // Nella V2 allarghiamo maggiormente la distanza tra
    // probabilità X deboli e realmente interessanti.
    //
    // 15% -> 0
    // 25% -> 50
    // 35% -> 100
    final simulatedDrawScore =
        (((simulation.drawPercent - 15.0) / 20.0) * 100.0)
            .clamp(0.0, 100.0)
            .toDouble();

    var weightedScore = 0.0;
    var totalWeight = 0.0;

    void addComponent(double value, double weight) {
      weightedScore += value * weight;
      totalWeight += weight;
    }

    // 90% del punteggio arriva dalla singola partita.
    addComponent(xgBalanceScore, 0.30);
    addComponent(balanceScore, 0.25);
    addComponent(simulatedDrawScore, 0.25);
    addComponent(lowScoringScore, 0.10);

    // Solo il 10% massimo deriva dalla storia.
    if (season.available) {
      addComponent(season.score, 0.06);
    }

    if (venue.available) {
      addComponent(venue.score, 0.04);
    }

    var rawScore = totalWeight > 0.0
        ? weightedScore / totalWeight
        : simulatedDrawScore;

    // ==========================================================
    // GUARDRAIL STRUTTURALI
    // ==========================================================
    //
    // Impediscono che molti pareggi storici trasformino una
    // partita chiaramente sbilanciata in un candidato X forte.
    // ==========================================================

    if (simulation.drawPercent < 20.0) {
      rawScore = rawScore.clamp(0.0, 45.0).toDouble();
    }

    if (xgDifference >= 1.40) {
      rawScore = rawScore.clamp(0.0, 35.0).toDouble();
    } else if (xgDifference >= 1.00) {
      rawScore = rawScore.clamp(0.0, 48.0).toDouble();
    } else if (xgDifference >= 0.80) {
      rawScore = rawScore.clamp(0.0, 58.0).toDouble();
    }

    if (winProbabilityDifference >= 30.0) {
      rawScore = rawScore.clamp(0.0, 42.0).toDouble();
    } else if (winProbabilityDifference >= 22.0) {
      rawScore = rawScore.clamp(0.0, 55.0).toDouble();
    }

    final score = rawScore.round().clamp(0, 100);

    return GoalVdLineDrawSuitabilityResult(
      score: score,
      level: _levelForScore(score),
      balanceScore: balanceScore,
      seasonDrawScore: season.score,
      venueDrawScore: venue.score,
      lowScoringScore: lowScoringScore,
      simulatedDrawScore: simulatedDrawScore,
      xgBalanceScore: xgBalanceScore,
    );
  }

  static _DrawComponent _seasonDrawData(MatchDossier dossier) {
    final home = _ratio(
      dossier.homeStatistics,
      numeratorKey: 'draws',
      denominatorKey: 'matchesPlayed',
    );

    final away = _ratio(
      dossier.awayStatistics,
      numeratorKey: 'draws',
      denominatorKey: 'matchesPlayed',
    );

    final rate = _averageAvailable(home, away);

    return _DrawComponent(
      available: rate != null,
      score: rate == null ? 0.0 : _drawRateToScore(rate),
    );
  }

  static _DrawComponent _venueDrawData(MatchDossier dossier) {
    final home = _ratio(
      dossier.homeVenue,
      numeratorKey: 'draws',
      denominatorKey: 'matches',
    );

    final away = _ratio(
      dossier.awayVenue,
      numeratorKey: 'draws',
      denominatorKey: 'matches',
    );

    final rate = _averageAvailable(home, away);

    return _DrawComponent(
      available: rate != null,
      score: rate == null ? 0.0 : _drawRateToScore(rate),
    );
  }

  static double? _ratio(
    Map<String, dynamic> source, {
    required String numeratorKey,
    required String denominatorKey,
  }) {
    final numerator = _toDouble(source[numeratorKey]);
    final denominator = _toDouble(source[denominatorKey]);

    if (numerator == null || denominator == null || denominator <= 0.0) {
      return null;
    }

    return (numerator / denominator).clamp(0.0, 1.0).toDouble();
  }

  static double? _averageAvailable(double? a, double? b) {
    if (a != null && b != null) {
      return (a + b) / 2.0;
    }

    return a ?? b;
  }

  static double _drawRateToScore(double drawRate) {
    return ((drawRate / 0.40) * 100.0).clamp(0.0, 100.0).toDouble();
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }

    return null;
  }

  static String _levelForScore(int score) {
    if (score >= 75) {
      return 'MOLTO ALTA';
    }

    if (score >= 65) {
      return 'ALTA';
    }

    if (score >= 55) {
      return 'MEDIA';
    }

    if (score >= 45) {
      return 'BASSA';
    }

    return 'MOLTO BASSA';
  }
}

class _DrawComponent {
  final bool available;
  final double score;

  const _DrawComponent({required this.available, required this.score});
}
