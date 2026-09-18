import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'smartbet_ai_service.dart';

class ScorerOdd {
  final double odd;
  final String bookmaker;

  const ScorerOdd({required this.odd, required this.bookmaker});
}

class ScorerCandidate {
  final MatchModel match;
  final int playerId;
  final String playerName;
  final String teamName;
  final String position;
  final double probability;
  final double braceProbability;
  final double rankScore;
  final int seasonGoals;
  final double goalsPer90;
  final double shotsOnTargetPer90;
  final int appearances;
  final int minutes;
  final bool officialLineupKnown;
  final bool confirmedStarter;
  final double starterRate;
  final double teamExpectedGoals;
  final double? rating;
  final ScorerOdd? odd;

  const ScorerCandidate({
    required this.match,
    required this.playerId,
    required this.playerName,
    required this.teamName,
    required this.position,
    required this.probability,
    required this.braceProbability,
    required this.rankScore,
    required this.seasonGoals,
    required this.goalsPer90,
    required this.shotsOnTargetPer90,
    required this.appearances,
    required this.minutes,
    required this.officialLineupKnown,
    required this.confirmedStarter,
    required this.starterRate,
    required this.teamExpectedGoals,
    required this.rating,
    required this.odd,
  });

  String get availabilityLabel {
    if (officialLineupKnown) {
      return confirmedStarter ? 'Titolare confermato' : 'Non titolare';
    }

    if (starterRate >= 0.72) {
      return 'Titolare abituale';
    }

    if (starterRate >= 0.48) {
      return 'Impiego frequente';
    }

    return 'Impiego da verificare';
  }
}

class ScorerCandidateService {
  ScorerCandidateService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Set<int> _scorerBetIds = {92, 218, 231};

  void dispose() {
    _client.close();
  }

  Future<List<ScorerCandidate>> buildForMatch({
    required MatchModel match,
    required AnalysisResult analysis,
  }) async {
    if (match.fixtureId <= 0 ||
        match.homeTeamId <= 0 ||
        match.awayTeamId <= 0) {
      return const [];
    }

    final season = _seasonFor(match);

    final results = await Future.wait<dynamic>([
      _fetchTeamPlayers(teamId: match.homeTeamId, season: season),
      _fetchTeamPlayers(teamId: match.awayTeamId, season: season),
      _fetchLineup(match.fixtureId),
      _fetchInjuries(match.fixtureId),
      _fetchScorerOdds(match.fixtureId),
    ]);

    final homePlayers = results[0] as List<_PlayerStats>;
    final awayPlayers = results[1] as List<_PlayerStats>;
    final lineup = results[2] as _LineupAvailability;
    final injuredIds = results[3] as Set<int>;
    final scorerOdds = results[4] as List<_NamedScorerOdd>;

    final homeExpected = _teamExpectedGoals(analysis: analysis, home: true);

    final awayExpected = _teamExpectedGoals(analysis: analysis, home: false);

    final candidates = <ScorerCandidate>[
      ..._buildTeamCandidates(
        match: match,
        players: homePlayers,
        teamId: match.homeTeamId,
        teamName: match.homeTeam,
        teamExpectedGoals: homeExpected,
        lineup: lineup,
        injuredIds: injuredIds,
        scorerOdds: scorerOdds,
      ),
      ..._buildTeamCandidates(
        match: match,
        players: awayPlayers,
        teamId: match.awayTeamId,
        teamName: match.awayTeam,
        teamExpectedGoals: awayExpected,
        lineup: lineup,
        injuredIds: injuredIds,
        scorerOdds: scorerOdds,
      ),
    ];

    candidates.sort((a, b) => b.rankScore.compareTo(a.rankScore));

    return candidates.take(8).toList();
  }

  int _seasonFor(MatchModel match) {
    try {
      return DateTime.parse(match.date).toLocal().year;
    } catch (_) {
      return DateTime.now().year;
    }
  }

  double _teamExpectedGoals({
    required AnalysisResult analysis,
    required bool home,
  }) {
    final direct = home
        ? analysis.expectedHomeGoals
        : analysis.expectedAwayGoals;

    if (direct > 0) {
      return direct.clamp(0.35, 3.80).toDouble();
    }

    var total = 2.35;

    if (analysis.over25Probability >= 68) {
      total += 0.55;
    } else if (analysis.over25Probability >= 58) {
      total += 0.30;
    } else if (analysis.over25Probability <= 38) {
      total -= 0.30;
    }

    final homeAwayTotal = math.max(
      1.0,
      analysis.homeProbability + analysis.awayProbability.toDouble(),
    );

    var homeShare = analysis.homeProbability / homeAwayTotal;
    homeShare = (0.50 + (homeShare - 0.50) * 0.72).clamp(0.29, 0.71).toDouble();

    final value = home ? total * homeShare : total * (1.0 - homeShare);

    return value.clamp(0.35, 3.80).toDouble();
  }

  List<ScorerCandidate> _buildTeamCandidates({
    required MatchModel match,
    required List<_PlayerStats> players,
    required int teamId,
    required String teamName,
    required double teamExpectedGoals,
    required _LineupAvailability lineup,
    required Set<int> injuredIds,
    required List<_NamedScorerOdd> scorerOdds,
  }) {
    if (teamExpectedGoals < 0.65) {
      return const [];
    }

    final officialLineupKnown = lineup.teamsWithLineup.contains(teamId);
    final starters = lineup.startersByTeam[teamId] ?? const <int>{};
    final substitutes = lineup.substitutesByTeam[teamId] ?? const <int>{};

    final result = <ScorerCandidate>[];

    for (final player in players) {
      if (player.playerId <= 0 ||
          player.name.trim().isEmpty ||
          injuredIds.contains(player.playerId)) {
        continue;
      }

      final position = player.position.toLowerCase();

      if (position.contains('goalkeeper') ||
          position == 'g' ||
          position.contains('keeper')) {
        continue;
      }

      if (player.minutes < 90 || player.appearances < 2) {
        continue;
      }

      final isStarter = starters.contains(player.playerId);
      final isSubstitute = substitutes.contains(player.playerId);

      if (officialLineupKnown && !isStarter && !isSubstitute) {
        continue;
      }

      // Quando la formazione ufficiale è disponibile, la shortlist finale
      // privilegia fortemente i titolari. I panchinari restano possibili ma
      // ricevono una penalizzazione importante.
      final starterRate = player.appearances > 0
          ? (player.lineups / player.appearances).clamp(0.0, 1.0).toDouble()
          : 0.0;

      if (!officialLineupKnown &&
          starterRate < 0.30 &&
          player.goalsPer90 < 0.24) {
        continue;
      }

      final priorRate = _positionPrior(position);
      final sample90 = player.minutes / 90.0;

      // Shrinkage verso un prior di ruolo: evita che 1 gol in pochi minuti
      // produca probabilità irrealistiche.
      final shrunkGoalRate =
          (player.goals + priorRate * 4.0) / (sample90 + 4.0);

      final expectedMinutes = officialLineupKnown
          ? (isStarter ? 82.0 : 27.0)
          : (38.0 + starterRate * 46.0).clamp(38.0, 84.0).toDouble();

      final teamFactor = math
          .pow((teamExpectedGoals / 1.35).clamp(0.50, 2.10), 0.70)
          .toDouble()
          .clamp(0.62, 1.72)
          .toDouble();

      final shotFactor = (1.0 + (player.shotsOnTargetPer90 - 0.75) * 0.11)
          .clamp(0.84, 1.22)
          .toDouble();

      final penaltyFactor = player.penaltiesScored > 0 ? 1.08 : 1.0;

      var lambda =
          shrunkGoalRate *
          (expectedMinutes / 90.0) *
          teamFactor *
          shotFactor *
          penaltyFactor;

      if (officialLineupKnown && !isStarter) {
        lambda *= 0.72;
      }

      lambda = lambda.clamp(0.01, 0.95).toDouble();

      final probability = 1.0 - math.exp(-lambda);

      // Probabilità di segnare almeno 2 gol nello stesso match.
      // Se X ~ Poisson(lambda):
      // P(X >= 2) = 1 - P(0) - P(1)
      //           = 1 - e^-lambda * (1 + lambda)
      final braceProbability = 1.0 - math.exp(-lambda) * (1.0 + lambda);

      if (probability < 0.10) {
        continue;
      }

      final ratingBonus = player.rating == null
          ? 0.0
          : ((player.rating! - 6.5) * 2.0).clamp(-1.0, 3.0).toDouble();

      final lineupBonus = officialLineupKnown
          ? (isStarter ? 9.0 : -5.0)
          : starterRate * 5.0;

      final sampleBonus =
          (player.minutes / 900.0).clamp(0.0, 1.0).toDouble() * 3.0;

      final rankScore =
          probability * 100.0 + lineupBonus + ratingBonus + sampleBonus;

      result.add(
        ScorerCandidate(
          match: match,
          playerId: player.playerId,
          playerName: player.name,
          teamName: teamName,
          position: player.position,
          probability: probability,
          braceProbability: braceProbability.clamp(0.0, 1.0).toDouble(),
          rankScore: rankScore,
          seasonGoals: player.goals.round(),
          goalsPer90: player.goalsPer90,
          shotsOnTargetPer90: player.shotsOnTargetPer90,
          appearances: player.appearances.round(),
          minutes: player.minutes.round(),
          officialLineupKnown: officialLineupKnown,
          confirmedStarter: isStarter,
          starterRate: starterRate,
          teamExpectedGoals: teamExpectedGoals,
          rating: player.rating,
          odd: _oddForPlayer(player.name, scorerOdds),
        ),
      );
    }

    result.sort((a, b) => b.rankScore.compareTo(a.rankScore));

    // Evitiamo che una singola squadra monopolizzi tutta la classifica.
    return result.take(4).toList();
  }

  double _positionPrior(String position) {
    if (position.contains('attacker') ||
        position.contains('forward') ||
        position == 'f') {
      return 0.30;
    }

    if (position.contains('midfielder') ||
        position.contains('midfield') ||
        position == 'm') {
      return 0.13;
    }

    if (position.contains('defender') ||
        position.contains('defence') ||
        position == 'd') {
      return 0.055;
    }

    return 0.12;
  }

  Future<List<_PlayerStats>> _fetchTeamPlayers({
    required int teamId,
    required int season,
  }) async {
    final firstPage = await _getPlayersPage(
      teamId: teamId,
      season: season,
      page: 1,
    );

    if (firstPage.items.isEmpty) {
      return const [];
    }

    final all = <Map<String, dynamic>>[...firstPage.items];

    final maxPage = math.min(firstPage.totalPages, 3);

    for (var page = 2; page <= maxPage; page++) {
      final next = await _getPlayersPage(
        teamId: teamId,
        season: season,
        page: page,
      );

      all.addAll(next.items);
    }

    return all
        .map((item) => _parsePlayer(item, teamId))
        .whereType<_PlayerStats>()
        .toList();
  }

  Future<_PlayersPage> _getPlayersPage({
    required int teamId,
    required int season,
    required int page,
  }) async {
    final uri =
        Uri.parse(
          '${SmartBetAiService.backendUrl}/football/api/players',
        ).replace(
          queryParameters: {
            'team': '$teamId',
            'season': '$season',
            'page': '$page',
          },
        );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 18));

      if (response.statusCode != 200) {
        return const _PlayersPage(items: [], totalPages: 1);
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return const _PlayersPage(items: [], totalPages: 1);
      }

      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        return const _PlayersPage(items: [], totalPages: 1);
      }

      final raw = decoded['response'];
      final items = raw is List
          ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];

      var totalPages = 1;
      final paging = decoded['paging'];

      if (paging is Map) {
        totalPages = _toInt(paging['total']).clamp(1, 20).toInt();
      }

      return _PlayersPage(items: items, totalPages: totalPages);
    } catch (_) {
      return const _PlayersPage(items: [], totalPages: 1);
    }
  }

  _PlayerStats? _parsePlayer(Map<String, dynamic> item, int teamId) {
    final player = item['player'];

    if (player is! Map) {
      return null;
    }

    final playerId = _toInt(player['id']);
    final name = player['name']?.toString().trim() ?? '';

    if (playerId <= 0 || name.isEmpty) {
      return null;
    }

    final stats = item['statistics'];

    if (stats is! List || stats.isEmpty) {
      return null;
    }

    double appearances = 0;
    double lineups = 0;
    double minutes = 0;
    double goals = 0;
    double shotsTotal = 0;
    double shotsOn = 0;
    double penaltiesScored = 0;
    double weightedRating = 0;
    double ratingMinutes = 0;
    String position = '';

    for (final raw in stats) {
      if (raw is! Map) {
        continue;
      }

      final team = raw['team'];

      if (team is Map && _toInt(team['id']) != teamId) {
        continue;
      }

      final games = raw['games'];
      final shots = raw['shots'];
      final goalsData = raw['goals'];
      final penalty = raw['penalty'];

      final statMinutes = games is Map ? _toDouble(games['minutes']) : 0.0;

      appearances += games is Map ? _toDouble(games['appearences']) : 0.0;
      lineups += games is Map ? _toDouble(games['lineups']) : 0.0;
      minutes += statMinutes;

      goals += goalsData is Map ? _toDouble(goalsData['total']) : 0.0;

      shotsTotal += shots is Map ? _toDouble(shots['total']) : 0.0;
      shotsOn += shots is Map ? _toDouble(shots['on']) : 0.0;

      penaltiesScored += penalty is Map ? _toDouble(penalty['scored']) : 0.0;

      if (games is Map) {
        final rawPosition = games['position']?.toString().trim() ?? '';
        if (position.isEmpty && rawPosition.isNotEmpty) {
          position = rawPosition;
        }

        final parsedRating = _nullableDouble(games['rating']);
        if (parsedRating != null && statMinutes > 0) {
          weightedRating += parsedRating * statMinutes;
          ratingMinutes += statMinutes;
        }
      }
    }

    if (minutes <= 0 || appearances <= 0) {
      return null;
    }

    final per90Divisor = minutes / 90.0;

    return _PlayerStats(
      playerId: playerId,
      name: name,
      position: position,
      appearances: appearances,
      lineups: lineups,
      minutes: minutes,
      goals: goals,
      shotsTotal: shotsTotal,
      shotsOnTarget: shotsOn,
      penaltiesScored: penaltiesScored,
      goalsPer90: per90Divisor > 0 ? goals / per90Divisor : 0.0,
      shotsOnTargetPer90: per90Divisor > 0 ? shotsOn / per90Divisor : 0.0,
      rating: ratingMinutes > 0 ? weightedRating / ratingMinutes : null,
    );
  }

  Future<_LineupAvailability> _fetchLineup(int fixtureId) async {
    final uri = Uri.parse(
      '${SmartBetAiService.backendUrl}/football/api/fixtures/lineups',
    ).replace(queryParameters: {'fixture': '$fixtureId'});

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return const _LineupAvailability();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const _LineupAvailability();
      }

      final raw = decoded['response'];
      if (raw is! List || raw.isEmpty) {
        return const _LineupAvailability();
      }

      final startersByTeam = <int, Set<int>>{};
      final substitutesByTeam = <int, Set<int>>{};
      final teamsWithLineup = <int>{};

      for (final entry in raw) {
        if (entry is! Map) continue;

        final team = entry['team'];
        final teamId = team is Map ? _toInt(team['id']) : 0;

        if (teamId <= 0) continue;

        final starters = _playerIdsFromLineupList(entry['startXI']);
        final substitutes = _playerIdsFromLineupList(entry['substitutes']);

        if (starters.isNotEmpty) {
          startersByTeam[teamId] = starters;
          substitutesByTeam[teamId] = substitutes;
          teamsWithLineup.add(teamId);
        }
      }

      return _LineupAvailability(
        startersByTeam: startersByTeam,
        substitutesByTeam: substitutesByTeam,
        teamsWithLineup: teamsWithLineup,
      );
    } catch (_) {
      return const _LineupAvailability();
    }
  }

  Set<int> _playerIdsFromLineupList(dynamic raw) {
    if (raw is! List) {
      return <int>{};
    }

    final result = <int>{};

    for (final item in raw) {
      if (item is! Map) continue;
      final player = item['player'];
      if (player is! Map) continue;

      final id = _toInt(player['id']);
      if (id > 0) {
        result.add(id);
      }
    }

    return result;
  }

  Future<Set<int>> _fetchInjuries(int fixtureId) async {
    final uri = Uri.parse(
      '${SmartBetAiService.backendUrl}/football/api/injuries',
    ).replace(queryParameters: {'fixture': '$fixtureId'});

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return <int>{};
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return <int>{};
      }

      final raw = decoded['response'];
      if (raw is! List) {
        return <int>{};
      }

      final result = <int>{};

      for (final item in raw) {
        if (item is! Map) continue;
        final player = item['player'];
        if (player is! Map) continue;

        final id = _toInt(player['id']);
        if (id > 0) {
          result.add(id);
        }
      }

      return result;
    } catch (_) {
      return <int>{};
    }
  }

  Future<List<_NamedScorerOdd>> _fetchScorerOdds(int fixtureId) async {
    final uri = Uri.parse(
      '${SmartBetAiService.backendUrl}/football/odds',
    ).replace(queryParameters: {'fixture': '$fixtureId'});

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }

      final rawResponse = decoded['response'];
      if (rawResponse is! List) {
        return const [];
      }

      final best = <String, _NamedScorerOdd>{};

      for (final responseItem in rawResponse) {
        if (responseItem is! Map) continue;

        final bookmakers = responseItem['bookmakers'];
        if (bookmakers is! List) continue;

        for (final rawBookmaker in bookmakers) {
          if (rawBookmaker is! Map) continue;

          final bookmaker = rawBookmaker['name']?.toString().trim() ?? '';
          final bets = rawBookmaker['bets'];

          if (bets is! List) continue;

          for (final rawBet in bets) {
            if (rawBet is! Map) continue;

            final betId = _toInt(rawBet['id']);
            final betName = rawBet['name']?.toString().toLowerCase() ?? '';

            final isScorerMarket =
                _scorerBetIds.contains(betId) ||
                betName.contains('anytime goal scorer');

            if (!isScorerMarket) {
              continue;
            }

            final values = rawBet['values'];
            if (values is! List) continue;

            for (final rawValue in values) {
              if (rawValue is! Map) continue;

              final playerName = rawValue['value']?.toString().trim() ?? '';
              final odd = _toDouble(rawValue['odd']);

              if (playerName.isEmpty || odd <= 1.0) {
                continue;
              }

              final key = _normalizeName(playerName);
              if (key.isEmpty) continue;

              final current = best[key];

              if (current == null || odd > current.odd) {
                best[key] = _NamedScorerOdd(
                  playerName: playerName,
                  normalizedName: key,
                  odd: odd,
                  bookmaker: bookmaker,
                );
              }
            }
          }
        }
      }

      return best.values.toList();
    } catch (_) {
      return const [];
    }
  }

  ScorerOdd? _oddForPlayer(String playerName, List<_NamedScorerOdd> odds) {
    final wanted = _normalizeName(playerName);

    if (wanted.isEmpty) {
      return null;
    }

    _NamedScorerOdd? best;

    for (final item in odds) {
      final matches =
          item.normalizedName == wanted ||
          item.normalizedName.contains(wanted) ||
          wanted.contains(item.normalizedName);

      if (!matches) {
        continue;
      }

      if (best == null || item.odd > best.odd) {
        best = item;
      }
    }

    if (best == null) {
      return null;
    }

    return ScorerOdd(odd: best.odd, bookmaker: best.bookmaker);
  }

  String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9à-ÿ ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class _PlayersPage {
  final List<Map<String, dynamic>> items;
  final int totalPages;

  const _PlayersPage({required this.items, required this.totalPages});
}

class _PlayerStats {
  final int playerId;
  final String name;
  final String position;
  final double appearances;
  final double lineups;
  final double minutes;
  final double goals;
  final double shotsTotal;
  final double shotsOnTarget;
  final double penaltiesScored;
  final double goalsPer90;
  final double shotsOnTargetPer90;
  final double? rating;

  const _PlayerStats({
    required this.playerId,
    required this.name,
    required this.position,
    required this.appearances,
    required this.lineups,
    required this.minutes,
    required this.goals,
    required this.shotsTotal,
    required this.shotsOnTarget,
    required this.penaltiesScored,
    required this.goalsPer90,
    required this.shotsOnTargetPer90,
    required this.rating,
  });
}

class _LineupAvailability {
  final Map<int, Set<int>> startersByTeam;
  final Map<int, Set<int>> substitutesByTeam;
  final Set<int> teamsWithLineup;

  const _LineupAvailability({
    this.startersByTeam = const {},
    this.substitutesByTeam = const {},
    this.teamsWithLineup = const {},
  });
}

class _NamedScorerOdd {
  final String playerName;
  final String normalizedName;
  final double odd;
  final String bookmaker;

  const _NamedScorerOdd({
    required this.playerName,
    required this.normalizedName,
    required this.odd,
    required this.bookmaker,
  });
}
