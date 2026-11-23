import 'package:flutter/foundation.dart';

import 'football_api_service.dart';
import 'personal_coupon_store.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

enum PersonalPickReviewStatus {
  pending,
  correct,
  wrong,
  unsupported,
  disputed,
}

class PersonalPickReview {
  final PersonalPickReviewStatus status;
  final PersonalVerifiedScore? score;

  const PersonalPickReview(this.status, this.score);
}

class PersonalCouponReviewSummary {
  final int correct;
  final int wrong;
  final int pending;
  final int unsupported;
  final int disputed;

  const PersonalCouponReviewSummary({
    required this.correct,
    required this.wrong,
    required this.pending,
    required this.unsupported,
    required this.disputed,
  });

  int get verified => correct + wrong;
  int get total => verified + pending + unsupported + disputed;
}

class PersonalCouponRefreshReport {
  final Map<String, PersonalVerifiedScore> scores;
  final int daysQueried;
  final int apiErrors;
  final int fixturesEligible;
  final int fixturesNotFinal;
  final int missingKickoff;

  const PersonalCouponRefreshReport({
    required this.scores,
    required this.daysQueried,
    required this.apiErrors,
    required this.fixturesEligible,
    required this.fixturesNotFinal,
    required this.missingKickoff,
  });
}

/// Private, read-only match assessment. An actual final score is required.
/// Missing/unsettleable markets are NEVER classified as losing predictions.
class PersonalCouponReviewService {
  const PersonalCouponReviewService();

  static String _key(PersonalSelection pick) =>
      '${pick.fixtureId.trim()}|${pick.currentMarket.trim().toUpperCase()}';

  /// Count presence across distinct named slips, not raw occurrences.
  Map<String, int> repeatedSelections(Iterable<PersonalCoupon> coupons) {
    final result = <String, int>{};
    for (final coupon in coupons) {
      for (final key in coupon.selections.map(_key).toSet()) {
        result[key] = (result[key] ?? 0) + 1;
      }
    }
    return result;
  }

  int repeatedInCoupons(
    PersonalSelection pick, Map<String, int> counts,
  ) => counts[_key(pick)] ?? 0;

  PersonalVerifiedScore? verifiedScore(
    PersonalSelection selection,
    Iterable<SmartBetAnalysisRecord> records,
  ) {
    final home = selection.verifiedHomeGoals;
    final away = selection.verifiedAwayGoals;
    final verifiedAt = selection.scoreVerifiedAt;
    if (home != null && away != null && home >= 0 && away >= 0 &&
        verifiedAt != null) {
      return PersonalVerifiedScore(
        homeGoals: home, awayGoals: away, verifiedAt: verifiedAt,
      );
    }

    // Use only locally archived *verified* results. Do not interpret a
    // retrospective prediction or an unconfirmed score as a real outcome.
    final fixtureId = int.tryParse(selection.fixtureId);
    if (fixtureId == null || fixtureId <= 0) return null;
    final found = records.where((record) =>
        record.fixtureId == fixtureId &&
        record.actualHomeGoals != null &&
        record.actualAwayGoals != null &&
        record.actualHomeGoals! >= 0 &&
        record.actualAwayGoals! >= 0 &&
        record.outcomeKnownBy != null &&
        record.outcomeKnownBy!.isAfter(record.matchDate) &&
        record.status != SmartBetAnalysisStatus.pending).toList();

    if (found.isEmpty) return null;
    final first = found.first;
    if (found.any((r) => r.actualHomeGoals != first.actualHomeGoals ||
        r.actualAwayGoals != first.actualAwayGoals)) return null;

    return PersonalVerifiedScore(
      homeGoals: first.actualHomeGoals!,
      awayGoals: first.actualAwayGoals!,
      verifiedAt: first.outcomeKnownBy!,
    );
  }

  PersonalPickReview review(
    PersonalSelection selection,
    Iterable<SmartBetAnalysisRecord> records,
  ) {
    final score = verifiedScore(selection, records);
    if (score == null) {
      return const PersonalPickReview(PersonalPickReviewStatus.pending, null);
    }
    final result = SmartBetAnalysisMarketSettlement.evaluate(
      market: selection.currentMarket,
      homeGoals: score.homeGoals,
      awayGoals: score.awayGoals,
    );
    switch (result) {
      case SmartBetAnalysisSettlement.correct:
        return PersonalPickReview(PersonalPickReviewStatus.correct, score);
      case SmartBetAnalysisSettlement.wrong:
        return PersonalPickReview(PersonalPickReviewStatus.wrong, score);
      case SmartBetAnalysisSettlement.unsupported:
        return PersonalPickReview(PersonalPickReviewStatus.unsupported, score);
    }
  }

  PersonalCouponReviewSummary summarize(
    PersonalCoupon coupon, Iterable<SmartBetAnalysisRecord> records,
  ) {
    var correct = 0;
    var wrong = 0;
    var pending = 0;
    var unsupported = 0;
    var disputed = 0;
    for (final selection in coupon.selections) {
      switch (review(selection, records).status) {
        case PersonalPickReviewStatus.correct:
          correct++;
        case PersonalPickReviewStatus.wrong:
          wrong++;
        case PersonalPickReviewStatus.pending:
          pending++;
        case PersonalPickReviewStatus.unsupported:
          unsupported++;
        case PersonalPickReviewStatus.disputed:
          disputed++;
      }
    }
    return PersonalCouponReviewSummary(
      correct: correct, wrong: wrong, pending: pending,
      unsupported: unsupported, disputed: disputed,
    );
  }

  /// Explicit user-triggered refresh only. One backend request per date,
  /// at most [maxDays] dates, no AI requests and no background polling.
  Future<PersonalCouponRefreshReport> fetchFinished({
    required Iterable<PersonalSelection> selections,
    required Iterable<SmartBetAnalysisRecord> history,
    Future<List<dynamic>> Function(DateTime date)? fetchByDate,
    DateTime? now,
    int maxDays = 5,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final fetch = fetchByDate ?? FootballApiService().getMatchesByDate;
    final historic = history.toList(growable: false);
    final eligible = <String, PersonalSelection>{};
    var missingKickoff = 0;

    for (final selection in selections) {
      if (verifiedScore(selection, historic) != null) continue;
      final kickoff = selection.kickoffAt ?? _historyKickoff(
        selection.fixtureId, historic,
      );
      if (kickoff == null) {
        missingKickoff++;
        continue;
      }
      if (current.difference(kickoff.toUtc()) < const Duration(hours: 4)) {
        continue;
      }
      eligible[selection.fixtureId] = selection;
    }

    final byDate = <String, Set<String>>{};
    final localDates = <String, DateTime>{};
    for (final selection in eligible.values) {
      final kickoff = selection.kickoffAt ?? _historyKickoff(
        selection.fixtureId, historic,
      );
      if (kickoff == null) continue;
      final local = kickoff.toLocal();
      final date = DateTime(local.year, local.month, local.day);
      final key = '${date.year}-${date.month}-${date.day}';
      (byDate[key] ??= <String>{}).add(selection.fixtureId);
      localDates[key] = date;
    }
    final keys = byDate.keys.toList()
      ..sort((a, b) => localDates[b]!.compareTo(localDates[a]!));

    final resolved = <String, PersonalVerifiedScore>{};
    var errors = 0;
    var days = 0;
    var notFinal = 0;
    for (final key in keys.take(maxDays)) {
      List<dynamic> fixtures;
      try {
        fixtures = await fetch(localDates[key]!);
        days++;
      } catch (error) {
        debugPrint('Personal coupon result fetch failed: $error');
        errors++;
        continue;
      }
      final expected = byDate[key]!;
      final seen = <String>{};
      for (final dynamic item in fixtures) {
        if (item is! Map) continue;
        final fixture = item['fixture'];
        if (fixture is! Map) continue;
        final fixtureId = fixture['id']?.toString() ?? '';
        if (!expected.contains(fixtureId) || !seen.add(fixtureId)) continue;
        final score = _verifiedFinalScore(item, current);
        if (score == null) {
          notFinal++;
          continue;
        }
        resolved[fixtureId] = score;
      }
      notFinal += expected.difference(seen).length;
    }
    return PersonalCouponRefreshReport(
      scores: resolved, daysQueried: days, apiErrors: errors,
      fixturesEligible: eligible.length,
      fixturesNotFinal: notFinal,
      missingKickoff: missingKickoff,
    );
  }

  DateTime? _historyKickoff(
    String id, Iterable<SmartBetAnalysisRecord> records,
  ) {
    for (final record in records) {
      if (record.fixtureId.toString() == id) return record.matchDate;
    }
    return null;
  }

  PersonalVerifiedScore? _verifiedFinalScore(
    Map fixtureResponse, DateTime checkedAt,
  ) {
    final fixture = fixtureResponse['fixture'];
    if (fixture is! Map) return null;
    final status = fixture['status'];
    if (status is! Map) return null;
    final state = status['short']?.toString().toUpperCase();
    // Avoid automatic settlement on awarded/void/postponed fixtures.
    if (state != 'FT' && state != 'AET' && state != 'PEN') return null;

    Map? goals;
    if (state == 'AET' || state == 'PEN') {
      final score = fixtureResponse['score'];
      if (score is Map && score['fulltime'] is Map) {
        goals = score['fulltime'] as Map;
      }
    } else if (fixtureResponse['goals'] is Map) {
      goals = fixtureResponse['goals'] as Map;
    }
    if (goals == null) return null;

    final home = _score(goals['home']);
    final away = _score(goals['away']);
    if (home == null || away == null || home < 0 || away < 0) return null;
    return PersonalVerifiedScore(
      homeGoals: home, awayGoals: away, verifiedAt: checkedAt,
    );
  }

  int? _score(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
