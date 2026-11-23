import 'goalvdline_extra_markets_service.dart';

enum GoalVdLineExtraSettlement { correct, wrong, unsupported }

/// Final observed inputs. No predicted or bookmaker values can appear here.
class GoalVdLineVerifiedExtraOutcome {
  final int? homeAtHalfTime;
  final int? awayAtHalfTime;
  final int? homeAtFullTime;
  final int? awayAtFullTime;
  final int? totalCorners;
  final int? totalShotsOnTarget;

  const GoalVdLineVerifiedExtraOutcome({
    this.homeAtHalfTime,
    this.awayAtHalfTime,
    this.homeAtFullTime,
    this.awayAtFullTime,
    this.totalCorners,
    this.totalShotsOnTarget,
  });
}

/// This evaluator is intentionally separate from the FT-only learning
/// evaluator, which MUST return unsupported for these markets.
class GoalVdLineExtraMarketResultService {
  const GoalVdLineExtraMarketResultService();

  GoalVdLineExtraSettlement evaluate({
    required String market,
    required GoalVdLineVerifiedExtraOutcome verified,
  }) {
    final name = market.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (!GoalVdLineExtraMarketsService.isExtraMarket(name)) {
      return GoalVdLineExtraSettlement.unsupported;
    }
    final isHalf = name.startsWith('1T ') || name.startsWith('2T ');
    if (isHalf) {
      final homeHt = verified.homeAtHalfTime;
      final awayHt = verified.awayAtHalfTime;
      final homeFt = verified.homeAtFullTime;
      final awayFt = verified.awayAtFullTime;
      if (homeHt == null || awayHt == null || homeHt < 0 || awayHt < 0) {
        return GoalVdLineExtraSettlement.unsupported;
      }
      var home = homeHt;
      var away = awayHt;
      if (name.startsWith('2T ')) {
        if (homeFt == null || awayFt == null || homeFt < homeHt ||
            awayFt < awayHt) return GoalVdLineExtraSettlement.unsupported;
        home = homeFt - homeHt;
        away = awayFt - awayHt;
      }
      final pick = name.substring(3);
      final hit = switch (pick) {
        '1' => home > away,
        'X' => home == away,
        '2' => away > home,
        _ => null,
      };
      return hit == null
          ? GoalVdLineExtraSettlement.unsupported
          : hit ? GoalVdLineExtraSettlement.correct
              : GoalVdLineExtraSettlement.wrong;
    }
    final total = name.startsWith('CORNER ')
        ? verified.totalCorners
        : verified.totalShotsOnTarget;
    if (total == null || total < 0 || total > 100) {
      return GoalVdLineExtraSettlement.unsupported;
    }
    final parts = name.split(' ');
    final line = double.tryParse(parts.last);
    if (line == null) return GoalVdLineExtraSettlement.unsupported;
    final hit = parts[parts.length - 2] == 'OVER'
        ? total > line : total < line;
    return hit ? GoalVdLineExtraSettlement.correct
        : GoalVdLineExtraSettlement.wrong;
  }

  /// Parse only finished fixture score envelopes. An awarded/abandoned
  /// fixture, extra-time score without regulation FT, or missing HT fails
  /// closed. Team statistics are an optional *distinct* verified payload.
  GoalVdLineVerifiedExtraOutcome? fromApiFixture(
    Map<String, dynamic> payload, {
    List<dynamic>? teamStatistics,
  }) {
    final fixture = payload['fixture'];
    if (fixture is! Map) return null;
    final status = fixture['status'];
    if (status is! Map) return null;
    final short = status['short']?.toString().toUpperCase();
    if (short != 'FT' && short != 'AET' && short != 'PEN') return null;

    final score = payload['score'];
    final scoreMap = score is Map ? score : const {};
    final halftime = scoreMap['halftime'];
    final fulltime = scoreMap['fulltime'];
    final ht = halftime is Map ? halftime : const {};
    final ft = fulltime is Map ? fulltime : const {};
    final fallbackGoals = payload['goals'];
    final fallback = short == 'FT' && fallbackGoals is Map
        ? fallbackGoals : const {};

    final hft = _asScore(ft['home'] ?? fallback['home']);
    final aft = _asScore(ft['away'] ?? fallback['away']);
    final hht = _asScore(ht['home']);
    final aht = _asScore(ht['away']);

    // Need a trustworthy FT score even for corner/shot verification.
    if (hft == null || aft == null) return null;

    final stats = teamStatistics ?? payload['statistics'];
    final corners = _sumTeamStat(stats, 'Corner Kicks');
    final shots = _sumTeamStat(stats, 'Shots on Goal');

    return GoalVdLineVerifiedExtraOutcome(
      homeAtHalfTime: hht,
      awayAtHalfTime: aht,
      homeAtFullTime: hft,
      awayAtFullTime: aft,
      totalCorners: corners,
      totalShotsOnTarget: shots,
    );
  }

  int? _asScore(Object? value) {
    if (value is int && value >= 0 && value <= 100) return value;
    if (value is num && value.isFinite &&
        value == value.roundToDouble() && value >= 0 && value <= 100) {
      return value.toInt();
    }
    return null;
  }

  int? _sumTeamStat(Object? response, String type) {
    if (response is! List || response.length != 2) return null;
    final ids = <String>{};
    var sum = 0;
    for (final row in response) {
      if (row is! Map) return null;
      final team = row['team'];
      if (team is! Map || team['id'] == null) return null;
      final id = team['id'].toString();
      if (!ids.add(id)) return null;
      final statistics = row['statistics'];
      if (statistics is! List) return null;
      int? count;
      for (final item in statistics) {
        if (item is! Map || item['type']?.toString() != type) continue;
        if (count != null) return null; // ambiguous duplicate provider row
        count = _asScore(item['value']);
      }
      if (count == null) return null;
      sum += count;
    }
    return sum <= 100 ? sum : null;
  }
}
