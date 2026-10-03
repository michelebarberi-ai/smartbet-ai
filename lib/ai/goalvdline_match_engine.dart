import 'dart:math' as math;

import '../models/goalvdline_match_engine_models.dart';

class GoalVdLineMatchEngine {
  const GoalVdLineMatchEngine._();

  // ============================================================
  // SIMULAZIONE PRINCIPALE
  // ============================================================

  static GoalVdLineMatchEngineResult simulate(
    GoalVdLineMatchEngineInput input,
  ) {
    final simulations = input.simulations.clamp(1000, 100000).toInt();

    // ----------------------------------------------------------
    // GOL ATTESI
    // ----------------------------------------------------------

    final homeLambda = _calculateExpectedGoals(
      attacker: input.home,
      defender: input.away,
      opponent: input.away,
      isHome: true,
    );

    final awayLambda = _calculateExpectedGoals(
      attacker: input.away,
      defender: input.home,
      opponent: input.home,
      isHome: false,
    );

    // ----------------------------------------------------------
    // SEED DETERMINISTICO
    // ----------------------------------------------------------
    //
    // La stessa partita con gli stessi dati produce sempre
    // risultati confrontabili.
    // ----------------------------------------------------------

    final seed =
        (input.fixtureId ^
            (input.home.teamId * 31) ^
            (input.away.teamId * 131)) &
        0x7fffffff;

    final random = math.Random(seed);

    int homeWins = 0;
    int draws = 0;
    int awayWins = 0;

    int over15 = 0;
    int over25 = 0;
    int over35 = 0;

    int bothTeamsScore = 0;

    final exactScoreCounts = <String, int>{};

    // ==========================================================
    // MONTE CARLO
    // ==========================================================

    for (var i = 0; i < simulations; i++) {
      final homeGoals = _samplePoisson(random, homeLambda);
      final awayGoals = _samplePoisson(random, awayLambda);

      // --------------------------------------------------------
      // 1X2
      // --------------------------------------------------------

      if (homeGoals > awayGoals) {
        homeWins++;
      } else if (homeGoals < awayGoals) {
        awayWins++;
      } else {
        draws++;
      }

      // --------------------------------------------------------
      // MERCATI GOL
      // --------------------------------------------------------

      final totalGoals = homeGoals + awayGoals;

      if (totalGoals >= 2) {
        over15++;
      }

      if (totalGoals >= 3) {
        over25++;
      }

      if (totalGoals >= 4) {
        over35++;
      }

      if (homeGoals > 0 && awayGoals > 0) {
        bothTeamsScore++;
      }

      // --------------------------------------------------------
      // RISULTATO ESATTO
      // --------------------------------------------------------

      final key = '$homeGoals-$awayGoals';

      exactScoreCounts[key] = (exactScoreCounts[key] ?? 0) + 1;
    }

    // ==========================================================
    // PROBABILITÀ
    // ==========================================================

    final homeProbability = homeWins / simulations;
    final drawProbability = draws / simulations;
    final awayProbability = awayWins / simulations;

    final over15Probability = over15 / simulations;
    final over25Probability = over25 / simulations;
    final over35Probability = over35 / simulations;

    final goalProbability = bothTeamsScore / simulations;

    // ==========================================================
    // RISULTATI ESATTI PIÙ FREQUENTI
    // ==========================================================

    final exactScores = exactScoreCounts.entries.map((entry) {
      final parts = entry.key.split('-');

      return GoalVdLineExactScore(
        homeGoals: int.parse(parts[0]),
        awayGoals: int.parse(parts[1]),
        probability: entry.value / simulations,
      );
    }).toList();

    exactScores.sort((a, b) => b.probability.compareTo(a.probability));

    final topExactScores = exactScores.take(5).toList();

    // ==========================================================
    // AFFIDABILITÀ DATI
    // ==========================================================

    final dataConfidence = _calculateDataConfidence(input);

    // ==========================================================
    // AFFIDABILITÀ PREVISIONE
    // ==========================================================

    final predictionConfidence = _calculatePredictionConfidence(
      dataConfidence: dataConfidence,
      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,
    );

    // ==========================================================
    // AVVISI
    // ==========================================================

    final warnings = _buildWarnings(
      input: input,
      dataConfidence: dataConfidence,
    );

    return GoalVdLineMatchEngineResult(
      expectedHomeGoals: homeLambda,
      expectedAwayGoals: awayLambda,
      homeWinProbability: homeProbability,
      drawProbability: drawProbability,
      awayWinProbability: awayProbability,
      over15Probability: over15Probability,
      over25Probability: over25Probability,
      over35Probability: over35Probability,
      goalProbability: goalProbability,
      dataConfidence: dataConfidence,
      predictionConfidence: predictionConfidence,
      simulations: simulations,
      exactScores: topExactScores,
      warnings: warnings,
    );
  }

  // ============================================================
  // EXPECTED GOALS
  // ============================================================

  static double _calculateExpectedGoals({
    required GoalVdLineTeamState attacker,
    required GoalVdLineTeamState defender,
    required GoalVdLineTeamState opponent,
    required bool isHome,
  }) {
    // ----------------------------------------------------------
    // BASE GOL
    // ----------------------------------------------------------
    //
    // Non utilizziamo semplicemente la media della squadra.
    //
    // Combiniamo:
    // - capacità realizzativa generale
    // - vulnerabilità difensiva dell'avversario
    // - andamento offensivo recente
    // - andamento difensivo recente dell'avversario
    // ----------------------------------------------------------

    var expectedGoals =
        (_safeGoalValue(attacker.goalsForPerMatch) * 0.40) +
        (_safeGoalValue(defender.goalsAgainstPerMatch) * 0.30) +
        (_safeGoalValue(attacker.recentGoalsForPerMatch) * 0.15) +
        (_safeGoalValue(defender.recentGoalsAgainstPerMatch) * 0.15);

    // ==========================================================
    // MATCHUP ATTACCO VS DIFESA
    // ==========================================================

    final attackDefenseEdge =
        (attacker.attackStrength.clamp(0.0, 100.0) -
            defender.defenseStrength.clamp(0.0, 100.0)) /
        100.0;

    final attackDefenseFactor = 1.0 + (attackDefenseEdge * 0.22);

    expectedGoals *= attackDefenseFactor;

    // ==========================================================
    // FORZA COMPLESSIVA RELATIVA
    // ==========================================================

    final relativeStrength = _relativeStrength(attacker, opponent);

    expectedGoals *= 1.0 + (relativeStrength * 0.18);

    // ==========================================================
    // DISPONIBILITÀ ROSA
    // ==========================================================

    final availability =
        (attacker.availabilityStrength.clamp(0.0, 100.0) - 50.0) / 50.0;

    expectedGoals *= 1.0 + (availability * 0.08);

    // ==========================================================
    // CONTESTO
    // ==========================================================
    //
    // contextAdjustment:
    //
    //  0.00 = neutro
    // -0.10 = penalizzazione del 10% circa
    // +0.10 = beneficio del 10% circa
    // ==========================================================

    final contextAdjustment = attacker.contextAdjustment.clamp(-0.25, 0.25);

    expectedGoals *= 1.0 + contextAdjustment;

    // ==========================================================
    // FATTORE CAMPO
    // ==========================================================

    if (isHome) {
      expectedGoals *= 1.06;
    } else {
      expectedGoals *= 0.96;
    }

    // ==========================================================
    // LIMITI DI SICUREZZA
    // ==========================================================

    return expectedGoals.clamp(0.20, 4.50).toDouble();
  }

  // ============================================================
  // FORZA RELATIVA
  // ============================================================

  static double _relativeStrength(
    GoalVdLineTeamState team,
    GoalVdLineTeamState opponent,
  ) {
    double difference(double left, double right) {
      return ((left.clamp(0.0, 100.0) - right.clamp(0.0, 100.0)) / 100.0)
          .clamp(-1.0, 1.0)
          .toDouble();
    }

    const structuralWeight = 0.20;
    const squadWeight = 0.10;
    const formWeight = 0.25;
    const venueWeight = 0.18;
    const motivationWeight = 0.10;
    const availabilityWeight = 0.17;

    const totalWeight =
        structuralWeight +
        squadWeight +
        formWeight +
        venueWeight +
        motivationWeight +
        availabilityWeight;

    final weighted =
        difference(team.structuralStrength, opponent.structuralStrength) *
            structuralWeight +
        difference(team.squadStrength, opponent.squadStrength) * squadWeight +
        difference(team.recentFormStrength, opponent.recentFormStrength) *
            formWeight +
        difference(team.venueStrength, opponent.venueStrength) * venueWeight +
        difference(team.motivationStrength, opponent.motivationStrength) *
            motivationWeight +
        difference(team.availabilityStrength, opponent.availabilityStrength) *
            availabilityWeight;

    return (weighted / totalWeight).clamp(-1.0, 1.0).toDouble();
  }

  // ============================================================
  // POISSON RANDOM
  // ============================================================

  static int _samplePoisson(math.Random random, double lambda) {
    if (lambda <= 0) {
      return 0;
    }

    final limit = math.exp(-lambda);

    var product = 1.0;
    var k = 0;

    do {
      k++;
      product *= random.nextDouble();
    } while (product > limit);

    return k - 1;
  }

  // ============================================================
  // QUALITÀ DATI
  // ============================================================

  static int _calculateDataConfidence(GoalVdLineMatchEngineInput input) {
    final teamConfidence =
        (input.home.dataConfidence + input.away.dataConfidence) / 2.0;

    final competitionWeight = input.competitionWeight
        .clamp(0.50, 1.00)
        .toDouble();

    // La competizione riduce la fiducia,
    // ma non distrugge completamente un buon campione dati.
    final competitionFactor = 0.75 + (competitionWeight * 0.25);

    var confidence = teamConfidence * competitionFactor;

    // Una formazione disponibile aumenta leggermente
    // la qualità del quadro informativo.
    if (input.home.lineupAvailable) {
      confidence += 2;
    }

    if (input.away.lineupAvailable) {
      confidence += 2;
    }

    return confidence.round().clamp(1, 99);
  }

  // ============================================================
  // AFFIDABILITÀ PREVISIONE
  // ============================================================

  static int _calculatePredictionConfidence({
    required int dataConfidence,
    required double homeProbability,
    required double drawProbability,
    required double awayProbability,
  }) {
    final probabilities = [homeProbability, drawProbability, awayProbability]
      ..sort((a, b) => b.compareTo(a));

    final best = probabilities[0];
    final second = probabilities[1];

    // ==========================================================
    // CHIAREZZA DEL PRONOSTICO
    // ==========================================================
    //
    // La qualità dei dati NON significa automaticamente che
    // una partita sia facile da prevedere.
    //
    // Esempio:
    //
    // 1 = 38%
    // X = 27%
    // 2 = 35%
    //
    // può avere dati eccellenti, ma resta una partita molto
    // equilibrata e quindi poco prevedibile.
    // ==========================================================

    final bestProbabilityClarity =
        (((best - (1.0 / 3.0)) / (2.0 / 3.0)) * 100.0)
            .clamp(0.0, 100.0)
            .toDouble();

    // Differenza tra primo e secondo scenario.
    //
    // Un distacco di 40 punti percentuali viene considerato
    // già estremamente netto.
    final separationClarity = (((best - second) / 0.40) * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    final outcomeClarity =
        (bestProbabilityClarity * 0.60) + (separationClarity * 0.40);

    // 55% qualità dei dati
    // 45% chiarezza effettiva dell'esito simulato
    final confidence = (dataConfidence * 0.55) + (outcomeClarity * 0.45);

    return confidence.round().clamp(1, 95);
  }

  // ============================================================
  // WARNING
  // ============================================================

  static List<String> _buildWarnings({
    required GoalVdLineMatchEngineInput input,
    required int dataConfidence,
  }) {
    final warnings = <String>[];

    if (dataConfidence < 40) {
      warnings.add(
        'Qualità dati bassa: il pronostico viene mostrato '
        'ma deve essere considerato poco affidabile.',
      );
    } else if (dataConfidence < 60) {
      warnings.add(
        'Qualità dati parziale: interpretare il risultato '
        'con maggiore cautela.',
      );
    }

    if (!input.home.lineupAvailable) {
      warnings.add('Formazione ${input.home.teamName} non disponibile.');
    }

    if (!input.away.lineupAvailable) {
      warnings.add('Formazione ${input.away.teamName} non disponibile.');
    }

    if (input.home.unavailablePlayers > 0) {
      warnings.add(
        '${input.home.teamName}: '
        '${input.home.unavailablePlayers} indisponibili rilevati.',
      );
    }

    if (input.away.unavailablePlayers > 0) {
      warnings.add(
        '${input.away.teamName}: '
        '${input.away.unavailablePlayers} indisponibili rilevati.',
      );
    }

    warnings.addAll(input.home.contextNotes);
    warnings.addAll(input.away.contextNotes);

    return List<String>.unmodifiable(warnings);
  }

  // ============================================================
  // VALORE GOL SICURO
  // ============================================================

  static double _safeGoalValue(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }

    return value.clamp(0.0, 5.0).toDouble();
  }
}
