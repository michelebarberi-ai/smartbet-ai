class SmartBetDecision {
  final String outcome;
  final int probability;
  final String reason;

  const SmartBetDecision({
    required this.outcome,
    required this.probability,
    required this.reason,
  });

  bool get isDoubleChance {
    return outcome == '1X' || outcome == 'X2' || outcome == '12';
  }
}

class DecisionEngine {
  const DecisionEngine._();

  // ============================================================
  // PRONOSTICO FINALE SMARTBET
  // ============================================================
  //
  // Riceve le probabilità reali 1 / X / 2 e decide se mantenere
  // un esito singolo oppure proteggere il pronostico con una
  // doppia chance.
  //
  // IMPORTANTE:
  // non scegliamo semplicemente la probabilità più alta tra
  // 1, X, 2, 1X, X2 e 12, perché le doppie chance vincerebbero
  // quasi sempre per costruzione matematica.
  // ============================================================

  static SmartBetDecision decide({
    required int homeProbability,
    required int drawProbability,
    required int awayProbability,
  }) {
    final home = homeProbability.clamp(0, 100);
    final draw = drawProbability.clamp(0, 100);
    final away = awayProbability.clamp(0, 100);

    final total = home + draw + away;

    if (total <= 0) {
      return const SmartBetDecision(
        outcome: 'N/D',
        probability: 0,
        reason: 'Probabilità insufficienti per generare un pronostico.',
      );
    }

    // ----------------------------------------------------------
    // NORMALIZZAZIONE
    // ----------------------------------------------------------
    //
    // Il backend normalmente restituisce 100%.
    // Se per arrotondamenti il totale fosse diverso, normalizziamo
    // prima di applicare le regole decisionali.
    // ----------------------------------------------------------

    final h = ((home / total) * 100).round();
    final x = ((draw / total) * 100).round();

    // Manteniamo il totale esattamente a 100.
    final a = 100 - h - x;

    final homeDraw = h + x;
    final drawAway = x + a;
    final homeAway = h + a;

    // ==========================================================
    // 1) VITTORIA CASA FORTE
    // ==========================================================

    if (h >= 58 && (h - x) >= 12 && (h - a) >= 12) {
      return SmartBetDecision(
        outcome: '1',
        probability: h,
        reason:
            'La vittoria della squadra di casa è sufficientemente '
            'forte e distacca sia pareggio sia vittoria ospite.',
      );
    }

    // ==========================================================
    // 2) VITTORIA OSPITE FORTE
    // ==========================================================

    if (a >= 58 && (a - x) >= 12 && (a - h) >= 12) {
      return SmartBetDecision(
        outcome: '2',
        probability: a,
        reason:
            'La vittoria della squadra ospite è sufficientemente '
            'forte e distacca sia pareggio sia vittoria casa.',
      );
    }

    // ==========================================================
    // 3) PAREGGIO REALMENTE DOMINANTE
    // ==========================================================
    //
    // Il segno X viene scelto soltanto quando il pareggio è
    // davvero il singolo esito più forte, non semplicemente
    // perché la partita è equilibrata.
    // ==========================================================

    if (x >= 38 && (x - h) >= 4 && (x - a) >= 4) {
      return SmartBetDecision(
        outcome: 'X',
        probability: x,
        reason:
            'Il pareggio è il singolo esito statisticamente più forte '
            'con un vantaggio sufficiente sugli altri risultati.',
      );
    }

    // ==========================================================
    // 4) DOPPIA CHANCE 12
    // ==========================================================
    //
    // La usiamo quando il pareggio è poco probabile e le due
    // vittorie restano abbastanza vicine tra loro.
    // ==========================================================

    if (x <= 22 && (h - a).abs() <= 18) {
      return SmartBetDecision(
        outcome: '12',
        probability: homeAway,
        reason:
            'Il pareggio ha probabilità contenuta mentre le due '
            'vittorie restano abbastanza equilibrate.',
      );
    }

    // ==========================================================
    // 5) CASA FAVORITA MA NON ABBASTANZA PER IL SEGNO 1
    // ==========================================================

    if (h >= a && a <= 28) {
      return SmartBetDecision(
        outcome: '1X',
        probability: homeDraw,
        reason:
            'La squadra di casa è favorita, ma il vantaggio non è '
            'abbastanza netto per escludere il pareggio.',
      );
    }

    // ==========================================================
    // 6) OSPITE FAVORITA MA NON ABBASTANZA PER IL SEGNO 2
    // ==========================================================

    if (a > h && h <= 28) {
      return SmartBetDecision(
        outcome: 'X2',
        probability: drawAway,
        reason:
            'La squadra ospite è favorita, ma il vantaggio non è '
            'abbastanza netto per escludere il pareggio.',
      );
    }

    // ==========================================================
    // 7) SINGOLO FORTE, MA NON DA SOGLIA PRINCIPALE
    // ==========================================================

    final outcomes = <MapEntry<String, int>>[
      MapEntry('1', h),
      MapEntry('X', x),
      MapEntry('2', a),
    ]..sort((left, right) => right.value.compareTo(left.value));

    final best = outcomes[0];
    final second = outcomes[1];

    if (best.value >= 50 && (best.value - second.value) >= 8) {
      return SmartBetDecision(
        outcome: best.key,
        probability: best.value,
        reason:
            'Un singolo esito mantiene un vantaggio significativo '
            'sulle alternative anche senza raggiungere la soglia forte.',
      );
    }

    // ==========================================================
    // 8) FALLBACK INTELLIGENTE
    // ==========================================================
    //
    // Escludiamo semplicemente l'esito meno probabile.
    // Così la doppia chance scelta protegge i due scenari che
    // SmartBet considera complessivamente più plausibili.
    // ==========================================================

    if (a <= h && a <= x) {
      return SmartBetDecision(
        outcome: '1X',
        probability: homeDraw,
        reason:
            'La vittoria ospite è lo scenario meno probabile; '
            'SmartBet protegge casa e pareggio.',
      );
    }

    if (h <= x && h <= a) {
      return SmartBetDecision(
        outcome: 'X2',
        probability: drawAway,
        reason:
            'La vittoria casa è lo scenario meno probabile; '
            'SmartBet protegge pareggio e vittoria ospite.',
      );
    }

    return SmartBetDecision(
      outcome: '12',
      probability: homeAway,
      reason:
          'Il pareggio è lo scenario meno probabile; '
          'SmartBet protegge entrambe le possibilità di vittoria.',
    );
  }
}
