import 'dart:math' as math;

import 'value_bet_calculator.dart';

// ============================================================
// STAKE RECOMMENDATION
// ============================================================

class StakeRecommendation {
  final bool shouldBet;

  final String outcome;

  final double odd;

  final String bookmakerName;

  final String valueClassification;

  final double aiProbability;

  final double expectedValue;

  final double edge;

  // Kelly pieno teorico.
  final double fullKellyFraction;

  // Kelly frazionato prima dei limiti finali.
  final double adjustedKellyFraction;

  // Stake finale espresso come frazione del bankroll.
  //
  // Esempio:
  // 0.005 = 0.50%
  final double stakeFraction;

  final int aiConfidence;

  final int dossierConfidence;

  final String risk;

  final String explanation;

  const StakeRecommendation({
    required this.shouldBet,
    required this.outcome,
    required this.odd,
    required this.bookmakerName,
    required this.valueClassification,
    required this.aiProbability,
    required this.expectedValue,
    required this.edge,
    required this.fullKellyFraction,
    required this.adjustedKellyFraction,
    required this.stakeFraction,
    required this.aiConfidence,
    required this.dossierConfidence,
    required this.risk,
    required this.explanation,
  });

  // ==========================================================
  // STAKE %
  // ==========================================================

  double get stakePercent {
    return stakeFraction * 100.0;
  }

  // ==========================================================
  // UNITÀ
  // ==========================================================
  //
  // SmartBet usa:
  //
  // 1 unità = 1% del bankroll
  //
  // Esempio:
  //
  // stakePercent = 0.50%
  // stakeUnits   = 0.50
  // ==========================================================

  double get stakeUnits {
    return stakePercent;
  }

  // ==========================================================
  // IMPORTO REALE
  // ==========================================================

  double amountForBankroll(double bankroll) {
    if (bankroll <= 0 || stakeFraction <= 0) {
      return 0.0;
    }

    return bankroll * stakeFraction;
  }

  // ==========================================================
  // NO BET
  // ==========================================================

  factory StakeRecommendation.noBet({
    required String reason,
    int aiConfidence = 0,
    int dossierConfidence = 0,
    String risk = '',
  }) {
    return StakeRecommendation(
      shouldBet: false,
      outcome: '',
      odd: 0.0,
      bookmakerName: '',
      valueClassification: 'NO VALUE',
      aiProbability: 0.0,
      expectedValue: 0.0,
      edge: 0.0,
      fullKellyFraction: 0.0,
      adjustedKellyFraction: 0.0,
      stakeFraction: 0.0,
      aiConfidence: aiConfidence,
      dossierConfidence: dossierConfidence,
      risk: risk,
      explanation: reason,
    );
  }
}

// ============================================================
// STAKE ENGINE
// ============================================================

class StakeEngine {
  const StakeEngine();

  // ============================================================
  // CONFIGURAZIONE
  // ============================================================

  // Kelly frazionato.
  //
  // Usiamo 1/4 Kelly per evitare esposizione aggressiva.
  static const double _kellyMultiplier = 0.25;

  // Tetto assoluto:
  //
  // mai oltre il 2% del bankroll su una singola giocata.
  static const double _absoluteMaximumStake = 0.02;

  // Se lo stake finale è inferiore allo 0.10%,
  // consideriamo il vantaggio troppo debole per giocare.
  static const double _minimumUsefulStake = 0.001;

  // ============================================================
  // CALCOLO
  // ============================================================

  StakeRecommendation calculate({
    required ValueBetResult valueResult,
    required int aiConfidence,
    required int dossierConfidence,
    required String risk,
  }) {
    // ==========================================================
    // VALUE BET PRESENTE?
    // ==========================================================

    final bestValue = valueResult.bestValue;

    if (bestValue == null || !bestValue.hasValue) {
      return StakeRecommendation.noBet(
        reason: 'Nessuna Value Bet valida: stake 0%.',
        aiConfidence: aiConfidence,
        dossierConfidence: dossierConfidence,
        risk: risk,
      );
    }

    // ==========================================================
    // DATI BASE
    // ==========================================================

    final probability = bestValue.aiProbability;

    final odd = bestValue.bestOdd;

    if (probability <= 0.0 || probability >= 1.0 || odd <= 1.0) {
      return StakeRecommendation.noBet(
        reason: 'Parametri non validi per il calcolo dello stake.',
        aiConfidence: aiConfidence,
        dossierConfidence: dossierConfidence,
        risk: risk,
      );
    }

    // ==========================================================
    // KELLY COMPLETO
    // ==========================================================
    //
    // Formula:
    //
    // f = (p * quota - 1) / (quota - 1)
    //
    // Dove:
    //
    // p     = probabilità SmartBet
    // quota = best odd disponibile
    // ==========================================================

    final fullKelly = ((probability * odd) - 1.0) / (odd - 1.0);

    if (fullKelly <= 0.0) {
      return StakeRecommendation.noBet(
        reason: 'Kelly non positivo: stake 0%.',
        aiConfidence: aiConfidence,
        dossierConfidence: dossierConfidence,
        risk: risk,
      );
    }

    // ==========================================================
    // FRACTIONAL KELLY
    // ==========================================================

    final fractionalKelly = fullKelly * _kellyMultiplier;

    // ==========================================================
    // CONFIDENCE FACTOR
    // ==========================================================
    //
    // Usiamo la confidence più bassa tra:
    //
    // AI
    // DOSSIER
    //
    // per evitare che una confidence AI elevata
    // compensi dati strutturali deboli.
    // ==========================================================

    final effectiveConfidence = math.min(aiConfidence, dossierConfidence);

    final confidenceFactor =
        effectiveConfidence.clamp(0, 100).toDouble() / 100.0;

    // ==========================================================
    // RISK FACTOR
    // ==========================================================

    final riskFactor = _riskFactor(risk);

    // ==========================================================
    // STAKE PRIMA DEI CAP
    // ==========================================================

    final adjustedKelly = fractionalKelly * confidenceFactor * riskFactor;

    // ==========================================================
    // CAP PER CLASSIFICAZIONE
    // ==========================================================

    final classificationCap = _classificationCap(bestValue.classification);

    if (classificationCap <= 0.0) {
      return StakeRecommendation.noBet(
        reason: 'Classificazione Value Bet non sufficiente.',
        aiConfidence: aiConfidence,
        dossierConfidence: dossierConfidence,
        risk: risk,
      );
    }

    // ==========================================================
    // STAKE FINALE
    // ==========================================================

    var stake = math.min(adjustedKelly, classificationCap);

    stake = math.min(stake, _absoluteMaximumStake);

    // ==========================================================
    // MINIMO OPERATIVO
    // ==========================================================

    if (stake < _minimumUsefulStake) {
      return StakeRecommendation.noBet(
        reason:
            'Stake teorico inferiore allo 0.10% del bankroll: '
            'vantaggio troppo debole.',
        aiConfidence: aiConfidence,
        dossierConfidence: dossierConfidence,
        risk: risk,
      );
    }

    // ==========================================================
    // DESCRIZIONE
    // ==========================================================

    final stakePercent = stake * 100.0;

    final fullKellyPercent = fullKelly * 100.0;

    final adjustedKellyPercent = adjustedKelly * 100.0;

    final edgePercent = bestValue.edge * 100.0;

    final evPercent = bestValue.expectedValue * 100.0;

    final explanation =
        '${bestValue.classification} '
        '${bestValue.outcome} '
        '@ ${bestValue.bestOdd.toStringAsFixed(2)} '
        '(${bestValue.bookmakerName}) | '
        'Stake consigliato '
        '${stakePercent.toStringAsFixed(2)}% bankroll '
        '(${stakePercent.toStringAsFixed(2)} unità) | '
        'Kelly pieno '
        '${fullKellyPercent.toStringAsFixed(2)}% | '
        'Kelly corretto '
        '${adjustedKellyPercent.toStringAsFixed(2)}% | '
        'Edge ${edgePercent >= 0 ? '+' : ''}'
        '${edgePercent.toStringAsFixed(1)} p.p. | '
        'EV ${evPercent >= 0 ? '+' : ''}'
        '${evPercent.toStringAsFixed(1)}%';

    return StakeRecommendation(
      shouldBet: true,
      outcome: bestValue.outcome,
      odd: bestValue.bestOdd,
      bookmakerName: bestValue.bookmakerName,
      valueClassification: bestValue.classification,
      aiProbability: bestValue.aiProbability,
      expectedValue: bestValue.expectedValue,
      edge: bestValue.edge,
      fullKellyFraction: fullKelly,
      adjustedKellyFraction: adjustedKelly,
      stakeFraction: stake,
      aiConfidence: aiConfidence,
      dossierConfidence: dossierConfidence,
      risk: risk,
      explanation: explanation,
    );
  }

  // ============================================================
  // CAP VALUE
  // ============================================================

  double _classificationCap(String classification) {
    switch (classification.toUpperCase().trim()) {
      // --------------------------------------------------------
      // WEAK
      // --------------------------------------------------------
      //
      // massimo 0.50% bankroll
      // --------------------------------------------------------

      case 'WEAK VALUE':
        return 0.005;

      // --------------------------------------------------------
      // VALUE
      // --------------------------------------------------------
      //
      // massimo 1.00%
      // --------------------------------------------------------

      case 'VALUE':
        return 0.01;

      // --------------------------------------------------------
      // STRONG
      // --------------------------------------------------------
      //
      // massimo 1.50%
      // --------------------------------------------------------

      case 'STRONG VALUE':
        return 0.015;

      default:
        return 0.0;
    }
  }

  // ============================================================
  // RISCHIO
  // ============================================================

  double _riskFactor(String risk) {
    final normalized = risk.toLowerCase().trim();

    if (normalized.contains('basso') || normalized.contains('low')) {
      return 1.0;
    }

    if (normalized.contains('medio') || normalized.contains('medium')) {
      return 0.75;
    }

    if (normalized.contains('alto') || normalized.contains('high')) {
      return 0.50;
    }

    // Rischio sconosciuto:
    // impostazione prudente.
    return 0.60;
  }
}
