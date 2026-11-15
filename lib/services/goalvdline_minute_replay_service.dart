import 'dart:math' as math;

/// B53 - replay probabilistico dei gol lungo i 90 minuti.
///
/// Modello SHADOW: processi di Poisson omogenei, condizionati ai gol attesi
/// prepartita. Rappresenta il *tempo dei gol*, non occasioni, tiri, tattiche
/// o sostituzioni: questi eventi richiedono dati e validazione dedicati.
/// Nessuna quota, nessuna richiesta API, nessuna modifica al coupon ufficiale.
class GoalVdLineReplayGoal {
  final int minute;
  final bool homeTeam;
  final int homeScore;
  final int awayScore;

  const GoalVdLineReplayGoal({
    required this.minute,
    required this.homeTeam,
    required this.homeScore,
    required this.awayScore,
  });

  Map<String, Object> toJson() => {
    'minute': minute,
    'team': homeTeam ? 'home' : 'away',
    'homeScore': homeScore,
    'awayScore': awayScore,
  };
}

class GoalVdLineMinuteReplayReport {
  final int fixtureId;
  final int simulations;
  final double expectedHomeGoals;
  final double expectedAwayGoals;
  final Map<String, double> probabilities;
  final Map<String, double> topExactScores;

  /// Una partita casuale dimostrativa, NON l'esito più probabile.
  final List<GoalVdLineReplayGoal> illustrativeGoals;
  final int halftimeHome;
  final int halftimeAway;
  final int fulltimeHome;
  final int fulltimeAway;

  const GoalVdLineMinuteReplayReport({
    required this.fixtureId,
    required this.simulations,
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.probabilities,
    required this.topExactScores,
    required this.illustrativeGoals,
    required this.halftimeHome,
    required this.halftimeAway,
    required this.fulltimeHome,
    required this.fulltimeAway,
  });

  Map<String, Object> toJson() => {
    'modelVersion': GoalVdLineMinuteReplayService.modelVersion,
    'mode': 'shadow_only',
    'scope': 'timed_goals_only',
    'fixtureId': fixtureId,
    'simulations': simulations,
    'expectedHomeGoals': expectedHomeGoals,
    'expectedAwayGoals': expectedAwayGoals,
    'probabilities': probabilities,
    'topExactScores': topExactScores,
    'illustrativeReplay': {
      'halftime': '$halftimeHome-$halftimeAway',
      'fulltime': '$fulltimeHome-$fulltimeAway',
      'goals': [for (final goal in illustrativeGoals) goal.toJson()],
    },
    'limitations': [
      'Minuti dei gol modellati con intensità costante, senza tattiche.',
      'Nessun tiro, cartellino, sostituzione o fattore di stato calibrato.',
      'La partita dimostrativa non è una previsione del risultato finale.',
      'Le probabilità non certificano quote bookmaker.',
    ],
  };
}

class GoalVdLineMinuteReplayService {
  const GoalVdLineMinuteReplayService();

  static const modelVersion = 'b53-minute-goal-replay-shadow-v1';
  static const int defaultSimulations = 5000;

  GoalVdLineMinuteReplayReport simulate({
    required int fixtureId,
    required double expectedHomeGoals,
    required double expectedAwayGoals,
    int simulations = defaultSimulations,
  }) {
    if (fixtureId <= 0) {
      throw ArgumentError.value(fixtureId, 'fixtureId', 'ID non valido');
    }
    // Il vecchio AnalysisResult usa 0 come sentinella di xG mancanti:
    // non interpretarlo come una previsione di 0 gol.
    if (!expectedHomeGoals.isFinite ||
        !expectedAwayGoals.isFinite ||
        expectedHomeGoals <= 0 ||
        expectedAwayGoals <= 0 ||
        expectedHomeGoals > 6 ||
        expectedAwayGoals > 6) {
      throw ArgumentError('xG prepartita mancanti o non validi (0, 6].');
    }
    if (simulations < 1000 || simulations > 100000) {
      throw ArgumentError.value(simulations, 'simulations', 'Range 1000..100000');
    }

    final random = math.Random((fixtureId ^ 0x4d5a21b3) & 0x7fffffff);
    final counts = <String, int>{
      '1': 0,
      'X': 0,
      '2': 0,
      '1X': 0,
      'X2': 0,
      '12': 0,
      'GOAL': 0,
      'NO GOAL': 0,
      'OVER 1.5': 0,
      'UNDER 1.5': 0,
      'OVER 2.5': 0,
      'UNDER 2.5': 0,
    };
    final scoreCounts = <String, int>{};
    var firstGoals = <GoalVdLineReplayGoal>[];
    var halfHome = 0;
    var halfAway = 0;
    var firstHome = 0;
    var firstAway = 0;

    for (var trial = 0; trial < simulations; trial++) {
      // In un processo di Poisson, gli intervalli tra gol hanno distribuzione
      // esponenziale. Questa implementazione simula tempi continui (0, 90]
      // e permette più gol nello stesso minuto senza perdere eventi.
      final timed = <({double at, bool home})>[
        ..._goalTimes(random, expectedHomeGoals, true),
        ..._goalTimes(random, expectedAwayGoals, false),
      ]..sort((a, b) => a.at.compareTo(b.at));

      var home = 0;
      var away = 0;
      var htHome = 0;
      var htAway = 0;
      final goals = <GoalVdLineReplayGoal>[];
      for (final event in timed) {
        if (event.home) {
          home++;
        } else {
          away++;
        }
        if (event.at <= 45) {
          if (event.home) {
            htHome++;
          } else {
            htAway++;
          }
        }
        if (trial == 0) {
          goals.add(GoalVdLineReplayGoal(
            minute: event.at.ceil().clamp(1, 90).toInt(),
            homeTeam: event.home,
            homeScore: home,
            awayScore: away,
          ));
        }
      }

      if (trial == 0) {
        firstGoals = goals;
        halfHome = htHome;
        halfAway = htAway;
        firstHome = home;
        firstAway = away;
      }

      void add(String market) => counts[market] = counts[market]! + 1;
      if (home > away) add('1');
      if (home == away) add('X');
      if (home < away) add('2');
      if (home >= away) add('1X');
      if (home <= away) add('X2');
      if (home != away) add('12');
      if (home > 0 && away > 0) add('GOAL');
      if (home == 0 || away == 0) add('NO GOAL');
      if (home + away >= 2) {
        add('OVER 1.5');
      } else {
        add('UNDER 1.5');
      }
      if (home + away >= 3) {
        add('OVER 2.5');
      } else {
        add('UNDER 2.5');
      }
      final key = '$home-$away';
      scoreCounts[key] = (scoreCounts[key] ?? 0) + 1;
    }

    final sortedScores = scoreCounts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    return GoalVdLineMinuteReplayReport(
      fixtureId: fixtureId,
      simulations: simulations,
      expectedHomeGoals: expectedHomeGoals,
      expectedAwayGoals: expectedAwayGoals,
      probabilities: Map.unmodifiable({
        for (final entry in counts.entries) entry.key: entry.value / simulations,
      }),
      topExactScores: Map.unmodifiable({
        for (final entry in sortedScores.take(5))
          entry.key: entry.value / simulations,
      }),
      illustrativeGoals: List.unmodifiable(firstGoals),
      halftimeHome: halfHome,
      halftimeAway: halfAway,
      fulltimeHome: firstHome,
      fulltimeAway: firstAway,
    );
  }

  Iterable<({double at, bool home})> _goalTimes(
    math.Random random,
    double expectedGoals,
    bool home,
  ) sync* {
    final rate = expectedGoals / 90.0;
    var elapsed = 0.0;
    while (true) {
      final u = math.max(random.nextDouble(), 1e-12);
      elapsed += -math.log(u) / rate;
      if (elapsed > 90) return;
      yield (at: elapsed, home: home);
    }
  }
}
