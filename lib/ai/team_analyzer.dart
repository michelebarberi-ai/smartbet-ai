import '../models/team_analysis.dart';
import '../services/team_statistics_service.dart';
import '../services/team_form_service.dart';

class TeamAnalyzer {
  const TeamAnalyzer._();

  // ============================================================
  // METODO COMPATIBILE CON IL VECCHIO CODICE
  // ============================================================

  static TeamAnalysis analyze({
    required String teamName,
    required int form,
    required int attack,
    required int defense,
    required int homeAway,
    required int motivation,
  }) {
    return TeamAnalysis(
      teamName: teamName,
      form: form,
      attack: attack,
      defense: defense,
      homeAway: homeAway,
      motivation: motivation,
    );
  }

  // ============================================================
  // NUOVO METODO: ANALISI DALLE ULTIME PARTITE
  // ============================================================

  static TeamAnalysis analyzeFromForm(
    TeamFormData formData, {
    bool isHome = false,
  }) {
    final form = formData.formScore;

    final attack = formData.attackScore;

    final defense = formData.defenseScore;

    final homePerformance = formData.homePerformance;

    final awayPerformance = formData.awayPerformance;

    final homeAway = isHome ? homePerformance : awayPerformance;

    final motivation = _calculateMotivationFromForm(formData);

    return TeamAnalysis(
      teamName: formData.teamName,
      form: form,
      attack: attack,
      defense: defense,
      homeAway: homeAway,
      motivation: motivation,
      matchesPlayed: formData.matchesPlayed,
      homePerformance: homePerformance,
      awayPerformance: awayPerformance,
    );
  }

  // ============================================================
  // METODO COMPATIBILE CON LE VECCHIE STATISTICHE
  // ============================================================

  static TeamAnalysis analyzeFromStatistics(
    TeamStatistics statistics, {
    bool isHome = false,
  }) {
    final form = _calculateForm(statistics);

    final attack = _calculateAttack(statistics);

    final defense = _calculateDefense(statistics);

    final homeAway = isHome
        ? _calculateHomePerformance(statistics)
        : _calculateAwayPerformance(statistics);

    final motivation = _calculateMotivation(statistics);

    return TeamAnalysis(
      teamName: statistics.teamName,
      form: form,
      attack: attack,
      defense: defense,
      homeAway: homeAway,
      motivation: motivation,
      matchesPlayed: statistics.matchesPlayed,
      homePerformance: _calculateHomePerformance(statistics),
      awayPerformance: _calculateAwayPerformance(statistics),
    );
  }

  // ============================================================
  // MOTIVAZIONE DALLE ULTIME PARTITE
  // ============================================================

  static int _calculateMotivationFromForm(TeamFormData data) {
    if (data.matchesPlayed <= 0) {
      return 50;
    }

    final goalDifference = data.goalDifference;

    final recentForm = data.formScore;

    final score = 50 + ((recentForm - 50) * 0.5) + (goalDifference * 2);

    return score.round().clamp(0, 100);
  }

  // ============================================================
  // FORMA
  // ============================================================

  static int _calculateForm(TeamStatistics statistics) {
    if (statistics.matchesPlayed <= 0) {
      return 0;
    }

    final winPoints = statistics.wins * 3;

    final drawPoints = statistics.draws;

    final maximumPoints = statistics.matchesPlayed * 3;

    if (maximumPoints <= 0) {
      return 0;
    }

    final percentage = (winPoints + drawPoints) / maximumPoints * 100;

    return percentage.round().clamp(0, 100);
  }

  // ============================================================
  // ATTACCO
  // ============================================================

  static int _calculateAttack(TeamStatistics statistics) {
    if (statistics.matchesPlayed <= 0) {
      return 0;
    }

    final goalsPerMatch = statistics.goalsFor / statistics.matchesPlayed;

    final score = (goalsPerMatch / 3) * 100;

    return score.round().clamp(0, 100);
  }

  // ============================================================
  // DIFESA
  // ============================================================

  static int _calculateDefense(TeamStatistics statistics) {
    if (statistics.matchesPlayed <= 0) {
      return 0;
    }

    final concededPerMatch = statistics.goalsAgainst / statistics.matchesPlayed;

    final score = 100 - ((concededPerMatch / 3) * 100);

    return score.round().clamp(0, 100);
  }

  // ============================================================
  // RENDIMENTO CASA
  // ============================================================

  static int _calculateHomePerformance(TeamStatistics statistics) {
    final total =
        statistics.homeWins + statistics.homeDraws + statistics.homeLosses;

    if (total <= 0) {
      return 50;
    }

    final points = (statistics.homeWins * 3) + statistics.homeDraws;

    final maximum = total * 3;

    return ((points / maximum) * 100).round().clamp(0, 100);
  }

  // ============================================================
  // RENDIMENTO TRASFERTA
  // ============================================================

  static int _calculateAwayPerformance(TeamStatistics statistics) {
    final total =
        statistics.awayWins + statistics.awayDraws + statistics.awayLosses;

    if (total <= 0) {
      return 50;
    }

    final points = (statistics.awayWins * 3) + statistics.awayDraws;

    final maximum = total * 3;

    return ((points / maximum) * 100).round().clamp(0, 100);
  }

  // ============================================================
  // MOTIVAZIONE
  // ============================================================

  static int _calculateMotivation(TeamStatistics statistics) {
    if (statistics.matchesPlayed <= 0) {
      return 50;
    }

    final goalDifference = statistics.goalDifference;

    final score = 50 + (goalDifference * 3);

    return score.round().clamp(0, 100);
  }
}
