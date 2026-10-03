import '../models/goalvdline_match_engine_models.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';

class GoalVdLineMatchInputAdapter {
  const GoalVdLineMatchInputAdapter._();

  static GoalVdLineMatchEngineInput fromDossier({
    required MatchModel match,
    required MatchDossier dossier,
    int simulations = 20000,
  }) {
    final home = _buildTeamState(
      teamId: match.homeTeamId,
      teamName: match.homeTeam,
      statistics: dossier.homeStatistics,
      form: dossier.homeForm,
      venue: dossier.homeVenue,
      dossier: dossier,
      isHome: true,
    );

    final away = _buildTeamState(
      teamId: match.awayTeamId,
      teamName: match.awayTeam,
      statistics: dossier.awayStatistics,
      form: dossier.awayForm,
      venue: dossier.awayVenue,
      dossier: dossier,
      isHome: false,
    );

    return GoalVdLineMatchEngineInput(
      fixtureId: match.fixtureId,
      home: home,
      away: away,
      competitionWeight: match.aiWeight,
      simulations: simulations,
    );
  }

  // ============================================================
  // COSTRUZIONE STATO SQUADRA
  // ============================================================

  static GoalVdLineTeamState _buildTeamState({
    required int teamId,
    required String teamName,
    required Map<String, dynamic> statistics,
    required Map<String, dynamic> form,
    required Map<String, dynamic> venue,
    required MatchDossier dossier,
    required bool isHome,
  }) {
    final matchesPlayed = _toInt(statistics['matchesPlayed']);
    final wins = _toInt(statistics['wins']);
    final draws = _toInt(statistics['draws']);

    final goalsPerMatch =
        _toDouble(statistics['goalsPerMatch']) ??
        _average(total: _toInt(statistics['goalsFor']), matches: matchesPlayed);

    final concededPerMatch =
        _toDouble(statistics['concededPerMatch']) ??
        _average(
          total: _toInt(statistics['goalsAgainst']),
          matches: matchesPlayed,
        );

    // ==========================================================
    // FORMA STAGIONALE
    // ==========================================================

    final seasonForm = _pointsStrength(
      wins: wins,
      draws: draws,
      matches: matchesPlayed,
    );

    // ==========================================================
    // ATTACCO / DIFESA
    // ==========================================================

    final attackStrength = ((goalsPerMatch / 3.0) * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    final defenseStrength = (100.0 - ((concededPerMatch / 3.0) * 100.0))
        .clamp(0.0, 100.0)
        .toDouble();

    final goalDifferenceScore =
        (50.0 + ((goalsPerMatch - concededPerMatch) * 20.0))
            .clamp(0.0, 100.0)
            .toDouble();

    // ==========================================================
    // FORZA STRUTTURALE
    // ==========================================================
    //
    // Questa rappresenta la forza di fondo della squadra,
    // distinta dal momento recente.
    // ==========================================================

    final structuralStrength =
        (seasonForm * 0.35) +
        (attackStrength * 0.25) +
        (defenseStrength * 0.25) +
        (goalDifferenceScore * 0.15);

    // ==========================================================
    // CASA / TRASFERTA
    // ==========================================================

    final venueStrength = _pointsStrength(
      wins: _toInt(venue['wins']),
      draws: _toInt(venue['draws']),
      matches: _toInt(venue['matches']),
    );

    // ==========================================================
    // MOMENTO RECENTE
    // ==========================================================

    final recent = _parseRecentMatches(teamName: teamName, form: form);

    final recentFormStrength = recent.matches > 0
        ? _pointsStrength(
            wins: recent.wins,
            draws: recent.draws,
            matches: recent.matches,
          )
        : seasonForm;

    final recentGoalsFor = recent.matches > 0
        ? recent.goalsFor / recent.matches
        : goalsPerMatch;

    final recentGoalsAgainst = recent.matches > 0
        ? recent.goalsAgainst / recent.matches
        : concededPerMatch;

    // ==========================================================
    // ASSENZE
    // ==========================================================

    final injuries = _countTeamEntries(dossier.injuries, teamName);

    final suspensions = _countTeamEntries(dossier.suspensions, teamName);

    final unavailable = injuries + suspensions;

    // 85 = disponibilità neutra/prudente.
    // Non assumiamo 100 solo perché non abbiamo trovato assenze.
    final availabilityStrength = (85.0 - (unavailable * 6.0))
        .clamp(45.0, 95.0)
        .toDouble();

    // ==========================================================
    // FORMAZIONE
    // ==========================================================

    final lineupAvailable = _hasTeamLineup(dossier.probableLineups, teamName);

    // ==========================================================
    // QUALITÀ DATI
    // ==========================================================

    final rawStatisticsConfidence = _toDouble(statistics['confidence']);

    final statisticsConfidence = rawStatisticsConfidence == null
        ? dossier.dataConfidence.toDouble()
        : rawStatisticsConfidence <= 1.0
        ? rawStatisticsConfidence * 100.0
        : rawStatisticsConfidence;

    var dataConfidence =
        (statisticsConfidence * 0.70) + (dossier.dataConfidence * 0.30);

    if (recent.matches == 0) {
      dataConfidence -= 8;
    } else if (recent.matches < 3) {
      dataConfidence -= 4;
    }

    // ==========================================================
    // NOTE
    // ==========================================================

    final notes = <String>[];

    if (recent.matches == 0) {
      notes.add(
        '$teamName: forma recente non interpretabile; '
        'usati i valori stagionali come fallback.',
      );
    }

    if (!lineupAvailable) {
      notes.add('$teamName: formazione probabile non disponibile.');
    }

    // Per ora NON inventiamo una forza rosa.
    // 50 è neutro e quindi non influenza il confronto.
    const squadStrength = 50.0;

    // Per ora il contesto testuale non modifica numericamente
    // la simulazione. Verrà collegato nella fase successiva.
    const contextAdjustment = 0.0;

    // Motivazione neutra finché non avremo un segnale reale
    // e strutturato dal contesto.
    const motivationStrength = 50.0;

    return GoalVdLineTeamState(
      teamId: teamId,
      teamName: teamName,
      structuralStrength: structuralStrength,
      squadStrength: squadStrength,
      attackStrength: attackStrength,
      defenseStrength: defenseStrength,
      recentFormStrength: recentFormStrength,
      venueStrength: venueStrength,
      motivationStrength: motivationStrength,
      availabilityStrength: availabilityStrength,
      goalsForPerMatch: goalsPerMatch,
      goalsAgainstPerMatch: concededPerMatch,
      recentGoalsForPerMatch: recentGoalsFor,
      recentGoalsAgainstPerMatch: recentGoalsAgainst,
      injuredPlayers: injuries,
      suspendedPlayers: suspensions,
      unavailablePlayers: unavailable,
      contextAdjustment: contextAdjustment,
      lineupAvailable: lineupAvailable,
      dataConfidence: dataConfidence.round().clamp(1, 99),
      contextNotes: notes,
    );
  }

  // ============================================================
  // FORMA RECENTE
  // ============================================================

  static _RecentSnapshot _parseRecentMatches({
    required String teamName,
    required Map<String, dynamic> form,
  }) {
    final rawMatches = form['matches'];

    if (rawMatches is! List) {
      return const _RecentSnapshot();
    }

    var matches = 0;
    var wins = 0;
    var draws = 0;
    var losses = 0;
    var goalsFor = 0;
    var goalsAgainst = 0;

    final normalizedTeam = teamName.trim().toLowerCase();

    final scorePattern = RegExp(r'(\d+)\s*-\s*(\d+)');

    for (final raw in rawMatches) {
      final text = raw.toString().trim();

      if (text.isEmpty) {
        continue;
      }

      final score = scorePattern.firstMatch(text);

      if (score == null) {
        continue;
      }

      final homeGoals = int.tryParse(score.group(1) ?? '');
      final awayGoals = int.tryParse(score.group(2) ?? '');

      if (homeGoals == null || awayGoals == null) {
        continue;
      }

      final beforeScore = text.substring(0, score.start).trim().toLowerCase();

      final afterScore = text.substring(score.end).trim().toLowerCase();

      final bool teamWasHome;
      final int teamGoals;
      final int opponentGoals;

      if (beforeScore.contains(normalizedTeam)) {
        teamWasHome = true;
        teamGoals = homeGoals;
        opponentGoals = awayGoals;
      } else if (afterScore.contains(normalizedTeam)) {
        teamWasHome = false;
        teamGoals = awayGoals;
        opponentGoals = homeGoals;
      } else {
        continue;
      }

      // Manteniamo la variabile per rendere esplicito
      // che la posizione casa/trasferta è stata identificata.
      if (teamWasHome) {
        // Nessuna correzione artificiale.
      }

      matches++;
      goalsFor += teamGoals;
      goalsAgainst += opponentGoals;

      if (teamGoals > opponentGoals) {
        wins++;
      } else if (teamGoals == opponentGoals) {
        draws++;
      } else {
        losses++;
      }
    }

    return _RecentSnapshot(
      matches: matches,
      wins: wins,
      draws: draws,
      losses: losses,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
    );
  }

  // ============================================================
  // RENDIMENTO
  // ============================================================

  static double _pointsStrength({
    required int wins,
    required int draws,
    required int matches,
  }) {
    if (matches <= 0) {
      return 50.0;
    }

    final points = (wins * 3) + draws;
    final maximum = matches * 3;

    return ((points / maximum) * 100.0).clamp(0.0, 100.0).toDouble();
  }

  // ============================================================
  // CONTESTO
  // ============================================================

  static int _countTeamEntries(List<String> entries, String teamName) {
    final prefix = '${teamName.trim().toLowerCase()}:';

    return entries.where((entry) {
      return entry.trim().toLowerCase().startsWith(prefix);
    }).length;
  }

  static bool _hasTeamLineup(List<String> entries, String teamName) {
    final marker = teamName.trim().toLowerCase();

    for (final entry in entries) {
      final normalized = entry.trim().toLowerCase();

      if (normalized.contains(marker)) {
        return true;
      }
    }

    return false;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static double _average({required int total, required int matches}) {
    if (matches <= 0) {
      return 0.0;
    }

    return total / matches;
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }
}

class _RecentSnapshot {
  final int matches;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;

  const _RecentSnapshot({
    this.matches = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
  });
}
