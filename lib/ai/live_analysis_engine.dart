import 'dart:math' as math;

import '../services/live_match_service.dart';

class LiveAnalysisResult {
  final int homeScoresProbability;
  final int awayScoresProbability;

  final int atLeastOneMoreGoalProbability;
  final int atLeastTwoMoreGoalsProbability;

  final int nextGoalHomeProbability;
  final int nextGoalAwayProbability;
  final int noMoreGoalProbability;

  final double expectedRemainingHomeGoals;
  final double expectedRemainingAwayGoals;

  final int confidence;

  final String pressureTeam;
  final String dataQuality;
  final String summary;

  const LiveAnalysisResult({
    required this.homeScoresProbability,
    required this.awayScoresProbability,
    required this.atLeastOneMoreGoalProbability,
    required this.atLeastTwoMoreGoalsProbability,
    required this.nextGoalHomeProbability,
    required this.nextGoalAwayProbability,
    required this.noMoreGoalProbability,
    required this.expectedRemainingHomeGoals,
    required this.expectedRemainingAwayGoals,
    required this.confidence,
    required this.pressureTeam,
    required this.dataQuality,
    required this.summary,
  });
}

class LiveAnalysisEngine {
  static LiveAnalysisResult analyze(LiveMatchSnapshot snapshot) {
    final match = snapshot.match;

    final minute = match.elapsed.clamp(1, 95);
    final remainingMinutes = math.max(0.0, 95.0 - minute.toDouble());

    final home = snapshot.homeStats;
    final away = snapshot.awayStats;

    final homeAttack = _attackStrength(stats: home, minute: minute);

    final awayAttack = _attackStrength(stats: away, minute: minute);

    final totalAttack = homeAttack + awayAttack;

    double homeShare;
    double awayShare;

    if (totalAttack <= 0) {
      homeShare = 0.50;
      awayShare = 0.50;
    } else {
      homeShare = homeAttack / totalAttack;
      awayShare = awayAttack / totalAttack;
    }

    final totalExpectedRemaining = _expectedRemainingGoals(
      home: home,
      away: away,
      minute: minute,
      remainingMinutes: remainingMinutes,
    );

    var homeLambda = totalExpectedRemaining * homeShare;
    var awayLambda = totalExpectedRemaining * awayShare;

    // La squadra in svantaggio tende normalmente ad aumentare
    // il rischio offensivo soprattutto nella seconda parte.
    if (minute >= 55) {
      if (match.homeGoals < match.awayGoals) {
        homeLambda *= 1.12;
        awayLambda *= 0.96;
      } else if (match.awayGoals < match.homeGoals) {
        awayLambda *= 1.12;
        homeLambda *= 0.96;
      }
    }

    // Effetto espulsioni.
    if (home.redCards > away.redCards) {
      homeLambda *= 0.72;
      awayLambda *= 1.12;
    } else if (away.redCards > home.redCards) {
      awayLambda *= 0.72;
      homeLambda *= 1.12;
    }

    homeLambda = homeLambda.clamp(0.01, 3.0);
    awayLambda = awayLambda.clamp(0.01, 3.0);

    final totalLambda = homeLambda + awayLambda;

    final probabilityNoMoreGoal = math.exp(-totalLambda);

    final probabilityOneOrMore = 1.0 - probabilityNoMoreGoal;

    final probabilityTwoOrMore =
        1.0 - (math.exp(-totalLambda) * (1.0 + totalLambda));

    final homeScores = 1.0 - math.exp(-homeLambda);

    final awayScores = 1.0 - math.exp(-awayLambda);

    double nextHome = 0;
    double nextAway = 0;

    if (totalLambda > 0) {
      nextHome = probabilityOneOrMore * (homeLambda / totalLambda);

      nextAway = probabilityOneOrMore * (awayLambda / totalLambda);
    }

    final confidence = _confidence(home: home, away: away, minute: minute);

    final pressureTeam = _pressureTeam(
      match: match,
      homeAttack: homeAttack,
      awayAttack: awayAttack,
    );

    final quality = _dataQuality(home: home, away: away);

    final oneMorePercent = _percent(probabilityOneOrMore);

    final twoMorePercent = _percent(probabilityTwoOrMore);

    final nextHomePercent = _percent(nextHome);
    final nextAwayPercent = _percent(nextAway);

    final summary = _summary(
      snapshot: snapshot,
      oneMore: oneMorePercent,
      twoMore: twoMorePercent,
      nextHome: nextHomePercent,
      nextAway: nextAwayPercent,
      pressureTeam: pressureTeam,
    );

    return LiveAnalysisResult(
      homeScoresProbability: _percent(homeScores),
      awayScoresProbability: _percent(awayScores),
      atLeastOneMoreGoalProbability: oneMorePercent,
      atLeastTwoMoreGoalsProbability: twoMorePercent,
      nextGoalHomeProbability: nextHomePercent,
      nextGoalAwayProbability: nextAwayPercent,
      noMoreGoalProbability: _percent(probabilityNoMoreGoal),
      expectedRemainingHomeGoals: homeLambda,
      expectedRemainingAwayGoals: awayLambda,
      confidence: confidence,
      pressureTeam: pressureTeam,
      dataQuality: quality,
      summary: summary,
    );
  }

  static double _attackStrength({
    required LiveTeamStats stats,
    required int minute,
  }) {
    final safeMinute = math.max(10, minute);

    final shotsOnGoalPer90 = stats.shotsOnGoal / safeMinute * 90;

    final totalShotsPer90 = stats.totalShots / safeMinute * 90;

    final insideBoxPer90 = stats.shotsInsideBox / safeMinute * 90;

    final cornersPer90 = stats.corners / safeMinute * 90;

    final xgPer90 = stats.expectedGoals == null
        ? null
        : stats.expectedGoals! / safeMinute * 90;

    final shotsOnGoalScore = (shotsOnGoalPer90 / 5.0).clamp(0.0, 2.0);

    final totalShotsScore = (totalShotsPer90 / 14.0).clamp(0.0, 2.0);

    final insideBoxScore = (insideBoxPer90 / 9.0).clamp(0.0, 2.0);

    final cornersScore = (cornersPer90 / 5.5).clamp(0.0, 2.0);

    final possessionScore = stats.possession <= 0
        ? 1.0
        : (stats.possession / 50.0).clamp(0.5, 1.5);

    var score =
        shotsOnGoalScore * 0.32 +
        totalShotsScore * 0.18 +
        insideBoxScore * 0.20 +
        cornersScore * 0.10 +
        possessionScore * 0.10;

    if (xgPer90 != null) {
      final xgScore = (xgPer90 / 1.45).clamp(0.0, 2.5);

      score += xgScore * 0.20;
    } else {
      score += 0.10;
    }

    return score.clamp(0.10, 2.50);
  }

  static double _expectedRemainingGoals({
    required LiveTeamStats home,
    required LiveTeamStats away,
    required int minute,
    required double remainingMinutes,
  }) {
    if (remainingMinutes <= 0) {
      return 0.02;
    }

    final combinedXg = (home.expectedGoals ?? 0) + (away.expectedGoals ?? 0);

    double projectedMatchGoals;

    if (combinedXg > 0.05 && minute >= 10) {
      final projectedXg = combinedXg / minute * 90;

      // Blend tra ritmo xG della gara e media neutra.
      projectedMatchGoals = projectedXg * 0.70 + 2.65 * 0.30;
    } else {
      final totalShots = home.totalShots + away.totalShots;

      final shotsPer90 = totalShots / math.max(10, minute) * 90;

      final shotBasedProjection = 2.65 * (shotsPer90 / 24.0).clamp(0.55, 1.65);

      projectedMatchGoals = shotBasedProjection * 0.65 + 2.65 * 0.35;
    }

    var remaining = projectedMatchGoals * (remainingMinutes / 90.0);

    // Negli ultimi minuti aumenta leggermente
    // la volatilità se la gara è ancora aperta.
    if (minute >= 75 && minute <= 90) {
      remaining *= 1.08;
    }

    return remaining.clamp(0.03, 4.0);
  }

  static int _confidence({
    required LiveTeamStats home,
    required LiveTeamStats away,
    required int minute,
  }) {
    var available = 0;
    const total = 12;

    if (home.totalShots > 0) available++;
    if (away.totalShots > 0) available++;

    if (home.shotsOnGoal > 0) available++;
    if (away.shotsOnGoal > 0) available++;

    if (home.possession > 0) available++;
    if (away.possession > 0) available++;

    if (home.shotsInsideBox > 0) available++;
    if (away.shotsInsideBox > 0) available++;

    if (home.corners > 0) available++;
    if (away.corners > 0) available++;

    if (home.expectedGoals != null) available++;
    if (away.expectedGoals != null) available++;

    final completeness = available / total;

    var confidence = 45.0 + completeness * 40.0;

    if (minute < 15) {
      confidence -= 12;
    } else if (minute < 30) {
      confidence -= 6;
    } else if (minute >= 60) {
      confidence += 4;
    }

    return confidence.round().clamp(30, 92);
  }

  static String _pressureTeam({
    required LiveMatchSummary match,
    required double homeAttack,
    required double awayAttack,
  }) {
    final difference = homeAttack - awayAttack;

    if (difference.abs() < 0.12) {
      return 'Equilibrata';
    }

    if (difference > 0) {
      return match.homeTeam;
    }

    return match.awayTeam;
  }

  static String _dataQuality({
    required LiveTeamStats home,
    required LiveTeamStats away,
  }) {
    if (home.expectedGoals != null && away.expectedGoals != null) {
      return 'Alta';
    }

    if (home.totalShots > 0 &&
        away.totalShots > 0 &&
        home.possession > 0 &&
        away.possession > 0) {
      return 'Buona';
    }

    return 'Limitata';
  }

  static String _summary({
    required LiveMatchSnapshot snapshot,
    required int oneMore,
    required int twoMore,
    required int nextHome,
    required int nextAway,
    required String pressureTeam,
  }) {
    final match = snapshot.match;

    String goalOutlook;

    if (oneMore >= 70) {
      goalOutlook =
          'La gara mostra una forte possibilità di almeno un altro gol.';
    } else if (oneMore >= 50) {
      goalOutlook = 'La possibilità di almeno un altro gol è significativa.';
    } else {
      goalOutlook =
          'Il modello vede una probabilità più contenuta di altri gol.';
    }

    String nextGoal;

    if (nextHome - nextAway >= 12) {
      nextGoal =
          '${match.homeTeam} è la squadra più indicata per il prossimo gol.';
    } else if (nextAway - nextHome >= 12) {
      nextGoal =
          '${match.awayTeam} è la squadra più indicata per il prossimo gol.';
    } else {
      nextGoal =
          'Il prossimo gol non mostra un vantaggio netto per una delle due squadre.';
    }

    final extra = twoMore >= 45
        ? ' Anche due o più reti restano uno scenario rilevante.'
        : '';

    final pressure = pressureTeam == 'Equilibrata'
        ? ' La pressione offensiva è abbastanza equilibrata.'
        : ' La pressione offensiva favorisce $pressureTeam.';

    return '$goalOutlook $nextGoal$extra$pressure';
  }

  static int _percent(double probability) {
    return (probability * 100).round().clamp(0, 100);
  }
}
