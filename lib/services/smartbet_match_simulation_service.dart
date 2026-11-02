import 'dart:math' as math;

/// Motore sportivo indipendente dalle quote (P21A).
///
/// Questa prima versione e' un modello di distribuzione dei gol, non ancora
/// una simulazione tattica minuto-per-minuto. Non apprende automaticamente.
/// Il fattore comune e' opzionale: 0 => Poisson indipendenti; valori positivi
/// introducono una correlazione positiva fra i gol delle due squadre.
class SmartBetMatchSimulationInput {
  final double expectedHomeGoals;
  final double expectedAwayGoals;
  final double sharedGoalIntensity;

  /// Qualita' dei dati in ingresso, NON probabilita' di successo.
  final double dataQuality;

  const SmartBetMatchSimulationInput({
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    this.sharedGoalIntensity = 0,
    required this.dataQuality,
  });

  void validate() {
    if (!expectedHomeGoals.isFinite ||
        !expectedAwayGoals.isFinite ||
        expectedHomeGoals < 0 ||
        expectedAwayGoals < 0 ||
        expectedHomeGoals > 6 ||
        expectedAwayGoals > 6) {
      throw ArgumentError('Gol attesi non validi (intervallo: 0..6).');
    }
    if (!sharedGoalIntensity.isFinite ||
        sharedGoalIntensity < 0 ||
        sharedGoalIntensity > math.min(expectedHomeGoals, expectedAwayGoals)) {
      throw ArgumentError('Intensita comune non valida.');
    }
    if (!dataQuality.isFinite || dataQuality < 0 || dataQuality > 1) {
      throw ArgumentError('Qualita dei dati non valida (0..1).');
    }
  }
}

class SmartBetSimulatedScore {
  final int homeGoals;
  final int awayGoals;
  final double probability;

  const SmartBetSimulatedScore(
    this.homeGoals,
    this.awayGoals,
    this.probability,
  );

  String get label => '$homeGoals-$awayGoals';
}

class SmartBetSimulationResult {
  final SmartBetMatchSimulationInput input;
  final Map<String, double> marketProbabilities;
  final List<SmartBetSimulatedScore> exactScores;

  /// Probabilita' non rappresentata nella griglia (prima della normalizzazione).
  final double truncatedTailProbability;

  const SmartBetSimulationResult({
    required this.input,
    required this.marketProbabilities,
    required this.exactScores,
    required this.truncatedTailProbability,
  });

  double get homeWin => probabilityFor('1');
  double get draw => probabilityFor('X');
  double get awayWin => probabilityFor('2');

  double probabilityFor(String market) {
    final key = market.trim().toUpperCase();
    final result = marketProbabilities[key];
    if (result == null) {
      throw ArgumentError.value(market, 'market', 'Mercato non supportato');
    }
    return result;
  }

  double exactScoreProbability(int home, int away) {
    if (home < 0 || away < 0) return 0;
    for (final score in exactScores) {
      if (score.homeGoals == home && score.awayGoals == away) {
        return score.probability;
      }
    }
    return 0;
  }

  List<SmartBetSimulatedScore> topExactScores({int count = 3}) {
    if (count <= 0) throw ArgumentError.value(count, 'count');
    final sorted = List<SmartBetSimulatedScore>.of(exactScores)
      ..sort((a, b) {
        final c = b.probability.compareTo(a.probability);
        if (c != 0) return c;
        final d = a.homeGoals.compareTo(b.homeGoals);
        return d != 0 ? d : a.awayGoals.compareTo(b.awayGoals);
      });
    return sorted.take(count).toList(growable: false);
  }
}

class SmartBetMatchSimulationService {
  const SmartBetMatchSimulationService();

  static const String modelVersion = 'p21a-bivariate-poisson-v1';
  static const int _maxGoals = 24;

  /// Restituisce tutte le probabilita' dallo stesso modello di punteggio.
  /// Non accetta quote, handicap o percentuali di bookmaker.
  SmartBetSimulationResult simulate(SmartBetMatchSimulationInput input) {
    input.validate();
    final common = input.sharedGoalIntensity;
    final home = _poissonSeries(input.expectedHomeGoals - common);
    final away = _poissonSeries(input.expectedAwayGoals - common);
    final shared = _poissonSeries(common);

    final raw = <SmartBetSimulatedScore>[];
    var mass = 0.0;
    for (var h = 0; h <= _maxGoals; h++) {
      for (var a = 0; a <= _maxGoals; a++) {
        var probability = 0.0;
        for (var k = 0; k <= math.min(h, a); k++) {
          probability += home[h - k] * away[a - k] * shared[k];
        }
        mass += probability;
        raw.add(SmartBetSimulatedScore(h, a, probability));
      }
    }
    if (!mass.isFinite || mass <= 0) {
      throw StateError('La simulazione non ha prodotto probabilita valide.');
    }
    final tail = (1.0 - mass).clamp(0.0, 1.0).toDouble();
    if (tail > 0.000001) {
      throw StateError('Massa fuori griglia troppo alta: $tail');
    }
    final scores = <SmartBetSimulatedScore>[];
    final probabilities = <String, double>{
      '1': 0,
      'X': 0,
      '2': 0,
      '1X': 0,
      'X2': 0,
      '12': 0,
      'GOAL': 0,
      'NO GOAL': 0,
      'HOME SCORES': 0,
      'AWAY SCORES': 0,
      for (final threshold in [0, 1, 2, 3, 4]) ...{
        'OVER ${threshold}.5': 0,
        'UNDER ${threshold}.5': 0,
      },
      for (final range in [(1, 3), (1, 4), (2, 4), (2, 5), (3, 5)])
        'MULTIGOL ${range.$1}-${range.$2}': 0,
    };

    for (final score in raw) {
      final h = score.homeGoals;
      final a = score.awayGoals;
      final goals = h + a;
      final p = score.probability / mass;
      scores.add(SmartBetSimulatedScore(h, a, p));
      void add(String key) {
        probabilities[key] = probabilities[key]! + p;
      }

      if (h > a) add('1');
      if (h == a) add('X');
      if (h < a) add('2');
      if (h >= a) add('1X');
      if (h <= a) add('X2');
      if (h != a) add('12');
      if (h > 0 && a > 0) add('GOAL');
      if (h == 0 || a == 0) add('NO GOAL');
      if (h > 0) add('HOME SCORES');
      if (a > 0) add('AWAY SCORES');
      for (final threshold in [0, 1, 2, 3, 4]) {
        add(goals > threshold ? 'OVER ${threshold}.5' : 'UNDER ${threshold}.5');
      }
      for (final range in [(1, 3), (1, 4), (2, 4), (2, 5), (3, 5)]) {
        if (goals >= range.$1 && goals <= range.$2) {
          add('MULTIGOL ${range.$1}-${range.$2}');
        }
      }
    }

    return SmartBetSimulationResult(
      input: input,
      marketProbabilities: Map.unmodifiable(probabilities),
      exactScores: List.unmodifiable(scores),
      truncatedTailProbability: tail,
    );
  }

  static List<double> _poissonSeries(double lambda) {
    final probabilities = List<double>.filled(_maxGoals + 1, 0);
    probabilities[0] = math.exp(-lambda);
    for (var i = 1; i <= _maxGoals; i++) {
      probabilities[i] = probabilities[i - 1] * lambda / i;
    }
    return probabilities;
  }
}

/// Unicamente le partite selezionate dall'utente, senza recuperare fixture extra.
class SmartBetXPremiumCandidate {
  final String fixtureId;
  final SmartBetSimulationResult simulation;

  const SmartBetXPremiumCandidate({
    required this.fixtureId,
    required this.simulation,
  });
}

class SmartBetXPremiumRankedCandidate {
  final SmartBetXPremiumCandidate candidate;
  final bool priority;
  final String reason;

  const SmartBetXPremiumRankedCandidate({
    required this.candidate,
    required this.priority,
    required this.reason,
  });

  double get drawProbability => candidate.simulation.draw;
}

/// Classifica senza nascondere nessuna partita richiesta.
/// Le soglie sono parametri operativi, NON garanzie di precisione.
class SmartBetXPremiumRanker {
  const SmartBetXPremiumRanker();

  List<SmartBetXPremiumRankedCandidate> rank({
    required List<SmartBetXPremiumCandidate> selectedMatches,
    required double minimumDrawProbability,
    required double minimumDataQuality,
  }) {
    if (!minimumDrawProbability.isFinite ||
        minimumDrawProbability < 0 ||
        minimumDrawProbability > 1 ||
        !minimumDataQuality.isFinite ||
        minimumDataQuality < 0 ||
        minimumDataQuality > 1) {
      throw ArgumentError('Soglie X Premium non valide.');
    }
    if (selectedMatches.map((m) => m.fixtureId).toSet().length !=
        selectedMatches.length) {
      throw ArgumentError('ID partita duplicato.');
    }
    final ranked = selectedMatches.map((match) {
      final probabilityOk = match.simulation.draw >= minimumDrawProbability;
      final dataOk = match.simulation.input.dataQuality >= minimumDataQuality;
      final priority = probabilityOk && dataOk;
      final reason = !dataOk
          ? 'Qualita dati insufficiente'
          : !probabilityOk
          ? 'Probabilita X sotto la soglia impostata'
          : 'Supera entrambe le soglie configurate';
      return SmartBetXPremiumRankedCandidate(
        candidate: match,
        priority: priority,
        reason: reason,
      );
    }).toList();
    ranked.sort((a, b) {
      if (a.priority != b.priority) return a.priority ? -1 : 1;
      final p = b.drawProbability.compareTo(a.drawProbability);
      if (p != 0) return p;
      final q = b.candidate.simulation.input.dataQuality.compareTo(
        a.candidate.simulation.input.dataQuality,
      );
      if (q != 0) return q;
      return a.candidate.fixtureId.compareTo(b.candidate.fixtureId);
    });
    return List.unmodifiable(ranked);
  }
}
