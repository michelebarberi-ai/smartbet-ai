import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/odds_service.dart';
import '../services/italy_schedule_filter.dart';

class CreateAiCouponScreen extends StatefulWidget {
  const CreateAiCouponScreen({super.key});

  @override
  State<CreateAiCouponScreen> createState() => _CreateAiCouponScreenState();
}

enum _CouponProfile { premium, balanced, value }

enum _CouponPeriod { today, weekend, next3Days, custom }

class _ComboChance {
  final String label;
  final int probability;

  const _ComboChance({required this.label, required this.probability});
}

class _PreCandidate {
  final MatchModel match;
  final AnalysisResult analysis;
  final int bestProbability;

  const _PreCandidate({
    required this.match,
    required this.analysis,
    required this.bestProbability,
  });
}

class _CouponPick {
  final MatchModel match;
  final AnalysisResult analysis;
  final String market;
  final int probability;
  final double? odd;
  final String bookmaker;
  final double edge;
  final double expectedValue;
  final double rankScore;
  final bool adaptive;

  const _CouponPick({
    required this.match,
    required this.analysis,
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
    required this.edge,
    required this.expectedValue,
    required this.rankScore,
    required this.adaptive,
  });
}

class _CreateAiCouponScreenState extends State<CreateAiCouponScreen> {
  final OddsService _oddsService = OddsService();

  _CouponProfile _profile = _CouponProfile.premium;

  _CouponPeriod _period = _CouponPeriod.today;
  DateTimeRange? _customPeriod;
  int _count = 5;

  bool _loading = false;
  bool _italyScheduleOnly = true;
  String _phase = '';

  int _processed = 0;
  int _total = 0;
  int _errors = 0;
  int _oddsProcessed = 0;
  int _oddsTotal = 0;

  String? _error;
  String? _notice;

  final List<_CouponPick> _results = [];

  static const double _minimumOdd = 1.15;

  static const List<String> _marketOrder = [
    '1',
    'X',
    '2',
    '1X',
    'X2',
    '12',
    'OVER 1.5',
    'UNDER 1.5',
    'OVER 2.5',
    'UNDER 2.5',
    'GOAL',
    'NO GOAL',
  ];

  @override
  void dispose() {
    _oddsService.dispose();
    super.dispose();
  }

  // ============================================================
  // PROFILI
  // ============================================================

  String get _profileName {
    switch (_profile) {
      case _CouponProfile.premium:
        return 'PREMIUM';
      case _CouponProfile.balanced:
        return 'BILANCIATA';
      case _CouponProfile.value:
        return 'VALUE';
    }
  }

  String get _profileSubtitle {
    switch (_profile) {
      case _CouponProfile.premium:
        return 'Più affidabile';
      case _CouponProfile.balanced:
        return 'Equilibrio quota / probabilità';
      case _CouponProfile.value:
        return 'Miglior valore statistico';
    }
  }

  String get _profileDescription {
    switch (_profile) {
      case _CouponProfile.premium:
        return 'Privilegia probabilità elevate e Smart Score solidi, '
            'scartando le quote troppo basse. Obiettivo: alta affidabilità; se necessario SmartBet usa criteri adattivi.';
      case _CouponProfile.balanced:
        return 'Cerca un compromesso tra affidabilità e quota, evitando sia '
            'selezioni troppo conservative sia mercati eccessivamente rischiosi.';
      case _CouponProfile.value:
        return 'Cerca quote che offrano valore rispetto alla probabilità '
            'stimata da SmartBet. È il profilo con maggiore variabilità.';
    }
  }

  // ============================================================
  // PROBABILITÀ DEI MERCATI
  // ============================================================

  Map<String, int> _markets(AnalysisResult r) {
    return {
      '1': r.homeProbability,
      'X': r.drawProbability,
      '2': r.awayProbability,
      '1X': (r.homeProbability + r.drawProbability).clamp(0, 100),
      'X2': (r.drawProbability + r.awayProbability).clamp(0, 100),
      '12': (r.homeProbability + r.awayProbability).clamp(0, 100),
      'OVER 1.5': r.over15Probability,
      'UNDER 1.5': r.under15Probability,
      'OVER 2.5': r.over25Probability,
      'UNDER 2.5': r.under25Probability,
      'GOAL': r.goalProbability,
      'NO GOAL': r.noGoalProbability,
    };
  }

  int _bestStatisticalProbability(AnalysisResult analysis) {
    var best = 0;

    for (final value in _markets(analysis).values) {
      if (value > best) {
        best = value;
      }
    }

    final combos = _comboChances(analysis);

    if (combos.isNotEmpty && combos.first.probability > best) {
      best = combos.first.probability;
    }

    return best;
  }

  double _poissonProbability(double lambda, int goals) {
    if (lambda <= 0 || goals < 0) {
      return 0.0;
    }

    var factorial = 1;
    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.pow(lambda, goals).toDouble() * math.exp(-lambda) / factorial;
  }

  List<_ComboChance> _comboChances(AnalysisResult result) {
    final homeLambda = result.expectedHomeGoals;
    final awayLambda = result.expectedAwayGoals;

    if (homeLambda <= 0 || awayLambda <= 0) {
      return const [];
    }

    const maxGoals = 8;
    final scores = <({int home, int away, double probability})>[];
    var totalMass = 0.0;

    for (var home = 0; home <= maxGoals; home++) {
      final homeProbability = _poissonProbability(homeLambda, home);

      for (var away = 0; away <= maxGoals; away++) {
        final awayProbability = _poissonProbability(awayLambda, away);
        final probability = homeProbability * awayProbability;

        totalMass += probability;

        scores.add((home: home, away: away, probability: probability));
      }
    }

    if (totalMass <= 0) {
      return const [];
    }

    int probabilityWhere(bool Function(int home, int away) condition) {
      var probability = 0.0;

      for (final score in scores) {
        if (condition(score.home, score.away)) {
          probability += score.probability;
        }
      }

      return ((probability / totalMass) * 100).round().clamp(0, 100);
    }

    final combos = <_ComboChance>[
      _ComboChance(
        label: '1X + O1.5',
        probability: probabilityWhere(
          (home, away) => home >= away && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: 'X2 + O1.5',
        probability: probabilityWhere(
          (home, away) => away >= home && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '1 + O1.5',
        probability: probabilityWhere(
          (home, away) => home > away && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '2 + O1.5',
        probability: probabilityWhere(
          (home, away) => away > home && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '1X + U3.5',
        probability: probabilityWhere(
          (home, away) => home >= away && home + away <= 3,
        ),
      ),
      _ComboChance(
        label: 'X2 + U3.5',
        probability: probabilityWhere(
          (home, away) => away >= home && home + away <= 3,
        ),
      ),
      _ComboChance(
        label: '1 + GOAL',
        probability: probabilityWhere(
          (home, away) => home > away && home > 0 && away > 0,
        ),
      ),
      _ComboChance(
        label: '2 + GOAL',
        probability: probabilityWhere(
          (home, away) => away > home && home > 0 && away > 0,
        ),
      ),
      _ComboChance(
        label: '1 + NO GOAL',
        probability: probabilityWhere(
          (home, away) => home > away && (home == 0 || away == 0),
        ),
      ),
      _ComboChance(
        label: '2 + NO GOAL',
        probability: probabilityWhere(
          (home, away) => away > home && (home == 0 || away == 0),
        ),
      ),
      _ComboChance(
        label: 'GOAL + O2.5',
        probability: probabilityWhere(
          (home, away) => home > 0 && away > 0 && home + away >= 3,
        ),
      ),
      _ComboChance(
        label: 'NO GOAL + U2.5',
        probability: probabilityWhere(
          (home, away) => (home == 0 || away == 0) && home + away <= 2,
        ),
      ),
    ];

    final reliable = combos.where((combo) => combo.probability >= 30).toList();

    reliable.sort((a, b) => b.probability.compareTo(a.probability));

    return reliable;
  }

  double _comboRankScore({required int probability, required int smartScore}) {
    switch (_profile) {
      case _CouponProfile.premium:
        return probability * 0.78 + smartScore * 0.22;

      case _CouponProfile.balanced:
        return probability * 0.65 + smartScore * 0.35;

      case _CouponProfile.value:
        return probability * 0.60 + smartScore * 0.40;
    }
  }

  bool _comboPassesPrimary({
    required int probability,
    required int smartScore,
  }) {
    switch (_profile) {
      case _CouponProfile.premium:
        return probability >= 65 && smartScore >= 50;

      case _CouponProfile.balanced:
        return probability >= 55 && smartScore >= 45;

      case _CouponProfile.value:
        return probability >= 45 && smartScore >= 40;
    }
  }

  bool _comboPassesAdaptive({
    required int probability,
    required int smartScore,
  }) {
    switch (_profile) {
      case _CouponProfile.premium:
        return probability >= 55 && smartScore >= 40;

      case _CouponProfile.balanced:
        return probability >= 45 && smartScore >= 35;

      case _CouponProfile.value:
        return probability >= 35 && smartScore >= 30;
    }
  }

  // ============================================================
  // FILTRI PROFILO
  // ============================================================

  bool _passesPrimary({
    required int probability,
    required int smartScore,
    required double odd,
    required double edge,
    required double expectedValue,
  }) {
    final p = probability / 100.0;

    switch (_profile) {
      case _CouponProfile.premium:
        return p >= 0.65 && smartScore >= 50 && odd >= 1.20 && odd <= 2.40;

      case _CouponProfile.balanced:
        return p >= 0.55 &&
            smartScore >= 45 &&
            odd >= 1.25 &&
            odd <= 3.50 &&
            expectedValue >= -0.08;

      case _CouponProfile.value:
        return p >= 0.45 &&
            smartScore >= 40 &&
            odd >= 1.35 &&
            odd <= 6.00 &&
            edge >= 0 &&
            expectedValue >= 0;
    }
  }

  bool _passesAdaptive({
    required int probability,
    required int smartScore,
    required double odd,
    required double edge,
    required double expectedValue,
  }) {
    final p = probability / 100.0;

    switch (_profile) {
      case _CouponProfile.premium:
        return p >= 0.55 && smartScore >= 40 && odd >= 1.15 && odd <= 3.00;

      case _CouponProfile.balanced:
        return p >= 0.45 &&
            smartScore >= 35 &&
            odd >= 1.15 &&
            odd <= 4.00 &&
            expectedValue >= -0.15;

      case _CouponProfile.value:
        return p >= 0.35 &&
            smartScore >= 30 &&
            odd >= 1.15 &&
            odd <= 8.00 &&
            expectedValue >= -0.10;
    }
  }

  double _rankScore({
    required int probability,
    required int smartScore,
    required double odd,
    required double edge,
    required double expectedValue,
  }) {
    final probabilityScore = probability.toDouble();
    final smartScoreValue = smartScore.toDouble();
    final edgePoints = edge * 100.0;
    final evPoints = expectedValue * 100.0;

    switch (_profile) {
      case _CouponProfile.premium:
        return probabilityScore * 0.68 +
            smartScoreValue * 0.22 +
            evPoints.clamp(-10.0, 15.0).toDouble() * 0.10;

      case _CouponProfile.balanced:
        return probabilityScore * 0.50 +
            smartScoreValue * 0.18 +
            edgePoints.clamp(-10.0, 20.0).toDouble() * 0.12 +
            evPoints.clamp(-15.0, 30.0).toDouble() * 0.20;

      case _CouponProfile.value:
        return probabilityScore * 0.22 +
            smartScoreValue * 0.08 +
            edgePoints.clamp(-10.0, 30.0).toDouble() * 0.25 +
            evPoints.clamp(-20.0, 60.0).toDouble() * 0.45;
    }
  }

  _CouponPick? _bestPickForMatch({
    required _PreCandidate preliminary,
    required FixtureMarketOdds? odds,
  }) {
    final probabilities = _markets(preliminary.analysis);

    final primary = <_CouponPick>[];
    final adaptive = <_CouponPick>[];
    final completion = <_CouponPick>[];

    for (final market in _marketOrder) {
      final probability = probabilities[market] ?? 0;
      final bestOdd = odds?.oddFor(market);

      if (probability <= 0 || bestOdd == null || bestOdd.odd < _minimumOdd) {
        continue;
      }

      final p = probability / 100.0;
      final impliedProbability = 1.0 / bestOdd.odd;
      final edge = p - impliedProbability;
      final expectedValue = (p * bestOdd.odd) - 1.0;

      final score = _rankScore(
        probability: probability,
        smartScore: preliminary.analysis.smartScore,
        odd: bestOdd.odd,
        edge: edge,
        expectedValue: expectedValue,
      );

      final pick = _CouponPick(
        match: preliminary.match,
        analysis: preliminary.analysis,
        market: market,
        probability: probability,
        odd: bestOdd.odd,
        bookmaker: bestOdd.bookmakerName,
        edge: edge,
        expectedValue: expectedValue,
        rankScore: score,
        adaptive: false,
      );

      if (_passesPrimary(
        probability: probability,
        smartScore: preliminary.analysis.smartScore,
        odd: bestOdd.odd,
        edge: edge,
        expectedValue: expectedValue,
      )) {
        primary.add(pick);
        continue;
      }

      if (_passesAdaptive(
        probability: probability,
        smartScore: preliminary.analysis.smartScore,
        odd: bestOdd.odd,
        edge: edge,
        expectedValue: expectedValue,
      )) {
        adaptive.add(
          _CouponPick(
            match: preliminary.match,
            analysis: preliminary.analysis,
            market: market,
            probability: probability,
            odd: bestOdd.odd,
            bookmaker: bestOdd.bookmakerName,
            edge: edge,
            expectedValue: expectedValue,
            rankScore: score,
            adaptive: true,
          ),
        );
        continue;
      }

      // Ultima possibilità:
      // il mercato è comunque valido perché ha quota >= 1.15.
      completion.add(
        _CouponPick(
          match: preliminary.match,
          analysis: preliminary.analysis,
          market: market,
          probability: probability,
          odd: bestOdd.odd,
          bookmaker: bestOdd.bookmakerName,
          edge: edge,
          expectedValue: expectedValue,
          rankScore: score,
          adaptive: true,
        ),
      );
    }

    final combos = _comboChances(preliminary.analysis);

    if (combos.isNotEmpty) {
      final bestCombo = combos.first;
      final probability = bestCombo.probability;
      final smartScore = preliminary.analysis.smartScore;

      final comboPick = _CouponPick(
        match: preliminary.match,
        analysis: preliminary.analysis,
        market: bestCombo.label,
        probability: probability,
        odd: null,
        bookmaker: '',
        edge: 0,
        expectedValue: 0,
        rankScore: _comboRankScore(
          probability: probability,
          smartScore: smartScore,
        ),
        adaptive: false,
      );

      if (_comboPassesPrimary(
        probability: probability,
        smartScore: smartScore,
      )) {
        primary.add(comboPick);
      } else if (_comboPassesAdaptive(
        probability: probability,
        smartScore: smartScore,
      )) {
        adaptive.add(
          _CouponPick(
            match: comboPick.match,
            analysis: comboPick.analysis,
            market: comboPick.market,
            probability: comboPick.probability,
            odd: null,
            bookmaker: '',
            edge: 0,
            expectedValue: 0,
            rankScore: comboPick.rankScore,
            adaptive: true,
          ),
        );
      }
    }

    int compare(_CouponPick a, _CouponPick b) {
      final score = b.rankScore.compareTo(a.rankScore);
      if (score != 0) return score;

      final probability = b.probability.compareTo(a.probability);

      if (probability != 0) {
        return probability;
      }

      return (b.odd ?? 0).compareTo(a.odd ?? 0);
    }

    primary.sort(compare);
    adaptive.sort(compare);
    completion.sort(compare);

    if (primary.isNotEmpty) {
      return primary.first;
    }

    if (adaptive.isNotEmpty) {
      return adaptive.first;
    }

    if (completion.isNotEmpty) {
      return completion.first;
    }

    return null;
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _shortDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  String get _periodLabel {
    switch (_period) {
      case _CouponPeriod.today:
        return 'Oggi';

      case _CouponPeriod.weekend:
        return '2 giorni';

      case _CouponPeriod.next3Days:
        return 'Prossimi 3 giorni';

      case _CouponPeriod.custom:
        final range = _customPeriod;

        if (range == null) {
          return 'Personalizzato';
        }

        return '${_shortDate(range.start)} - ${_shortDate(range.end)}';
    }
  }

  List<DateTime> _selectedDates() {
    final today = _dateOnly(DateTime.now());

    switch (_period) {
      case _CouponPeriod.today:
        return [today];

      case _CouponPeriod.weekend:
        return [today, today.add(const Duration(days: 1))];

      case _CouponPeriod.next3Days:
        return List<DateTime>.generate(
          3,
          (index) => today.add(Duration(days: index)),
        );

      case _CouponPeriod.custom:
        final range = _customPeriod;

        if (range == null) {
          return [today];
        }

        final start = _dateOnly(range.start);
        final end = _dateOnly(range.end);
        final days = end.difference(start).inDays + 1;

        return List<DateTime>.generate(
          days,
          (index) => start.add(Duration(days: index)),
        );
    }
  }

  Future<List<MatchModel>> _loadMatchesForSelectedPeriod() async {
    final dates = _selectedDates();
    final today = _dateOnly(DateTime.now());

    final batches = await Future.wait(
      dates.map((date) {
        if (_dateOnly(date) == today) {
          return MatchRepository.getTodayMatches();
        }

        return MatchRepository.getMatchesByDate(date);
      }),
    );

    final unique = <int, MatchModel>{};

    for (final batch in batches) {
      for (final match in batch) {
        unique[match.fixtureId] = match;
      }
    }

    final matches = unique.values.toList();

    matches.sort((a, b) {
      try {
        return DateTime.parse(a.date).compareTo(DateTime.parse(b.date));
      } catch (_) {
        return 0;
      }
    });

    return matches;
  }

  Future<void> _selectCustomPeriod() async {
    final today = _dateOnly(DateTime.now());

    final initialRange =
        _customPeriod ??
        DateTimeRange(start: today, end: today.add(const Duration(days: 2)));

    final selected = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 60)),
      initialDateRange: initialRange,
      helpText: 'Periodo schedina AI',
      saveText: 'CONFERMA',
    );

    if (selected == null || !mounted) {
      return;
    }

    final length =
        _dateOnly(selected.end).difference(_dateOnly(selected.start)).inDays +
        1;

    if (length > 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Per ora puoi selezionare un massimo di 7 giorni.'),
        ),
      );
      return;
    }

    setState(() {
      _period = _CouponPeriod.custom;
      _customPeriod = selected;
      _results.clear();
      _error = null;
      _notice = null;
    });
  }

  // ============================================================
  // PARTITA NON INIZIATA
  // ============================================================

  bool _isUpcoming(MatchModel match) {
    try {
      return DateTime.parse(match.date).toLocal().isAfter(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  // ============================================================
  // CREA SCHEDINA
  // ============================================================

  Future<void> _createCoupon() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _phase = 'odds';

      _processed = 0;
      _total = 0;

      _oddsProcessed = 0;
      _oddsTotal = 0;

      _errors = 0;

      _error = null;
      _notice = null;

      _results.clear();
    });

    try {
      // ========================================================
      // PARTITE DEL GIORNO
      // ========================================================

      final all = await _loadMatchesForSelectedPeriod();

      final matches = all
          .where(
            (m) =>
                m.hasTeamIds &&
                _isUpcoming(m) &&
                (!_italyScheduleOnly || ItalyScheduleFilter.allows(m)),
          )
          .toList();

      // Prima le competizioni / partite con peso AI maggiore.
      matches.sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

      if (!mounted) return;

      if (matches.isEmpty) {
        setState(() {
          _loading = false;
          _phase = '';

          _error = 'Non ci sono partite ancora da giocare disponibili oggi.';
        });

        return;
      }

      // ========================================================
      // SCANSIONE ADATTIVA
      // ========================================================
      //
      // Non analizziamo centinaia di partite tutte insieme.
      //
      // 1. Analizziamo un blocco.
      // 2. Controlliamo subito le quote.
      // 3. Conserviamo le selezioni valide.
      // 4. Se non siamo arrivati al target, passiamo
      //    al blocco successivo.
      //
      // ========================================================

      const blockSize = 18;

      // 120 è un limite di sicurezza molto ampio:
      // normalmente dovremmo fermarci molto prima.
      final maximumToScan = math.min(matches.length, 120);

      final qualified = <_CouponPick>[];

      // Raccogliamo più selezioni di quelle richieste,
      // poi scegliamo le migliori in base al profilo.
      //
      // Esempi:
      // 3 richieste  -> pool 8
      // 5 richieste  -> pool 10
      // 7+ richieste -> massimo 12
      final targetCandidatePool = math.min(20, _count + 5);

      setState(() {
        _total = maximumToScan;
        _oddsTotal = maximumToScan;
      });

      for (
        var start = 0;
        start < maximumToScan && qualified.length < targetCandidatePool;
        start += blockSize
      ) {
        final end = math.min(start + blockSize, maximumToScan);

        final batch = matches.sublist(start, end);

        // ======================================================
        // PRE-ANALISI DEL BLOCCO
        // ======================================================

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final result = await SmartCore.analyze(match);

              final probability = _bestStatisticalProbability(result);

              if (probability <= 0) {
                return null;
              }

              return _PreCandidate(
                match: match,
                analysis: result,
                bestProbability: probability,
              );
            } catch (e) {
              return null;
            }
          }),
        );

        final candidates = analyzed.whereType<_PreCandidate>().toList();

        candidates.sort((a, b) {
          final probability = b.bestProbability.compareTo(a.bestProbability);

          if (probability != 0) {
            return probability;
          }

          final smart = b.analysis.smartScore.compareTo(a.analysis.smartScore);

          if (smart != 0) {
            return smart;
          }

          return b.match.aiWeight.compareTo(a.match.aiWeight);
        });

        if (!mounted) return;

        setState(() {
          _processed = end;
          _oddsProcessed = end;
        });

        // ======================================================
        // QUOTE SUBITO DOPO LA PRE-ANALISI
        // ======================================================

        for (final candidate in candidates) {
          if (!mounted) return;

          try {
            final odds = await _oddsService.getFixtureMarketOdds(
              fixtureId: candidate.match.fixtureId,
            );

            final pick = _bestPickForMatch(preliminary: candidate, odds: odds);

            if (pick == null) {
              continue;
            }

            qualified.add(pick);

            if (!mounted) return;

            setState(() {
              _results
                ..clear()
                ..addAll(qualified.take(_count));
            });

            if (qualified.length >= targetCandidatePool) {
              break;
            }
          } catch (e) {
            _errors++;
          }
        }
      }

      // ========================================================
      // ORDINAMENTO FINALE
      // ========================================================

      qualified.sort((a, b) {
        if (a.adaptive != b.adaptive) {
          return a.adaptive ? 1 : -1;
        }

        final score = b.rankScore.compareTo(a.rankScore);

        if (score != 0) {
          return score;
        }

        final probability = b.probability.compareTo(a.probability);

        if (probability != 0) {
          return probability;
        }

        return b.analysis.smartScore.compareTo(a.analysis.smartScore);
      });

      final selected = qualified.take(_count).toList();

      final adaptiveCount = selected.where((e) => e.adaptive).length;

      if (!mounted) return;

      setState(() {
        _results
          ..clear()
          ..addAll(selected);

        _loading = false;
        _phase = '';

        if (_results.isEmpty) {
          _error =
              'SmartBet non ha trovato mercati con '
              'quote valide di almeno 1.15 nelle '
              'partite controllate.';
        } else if (_results.length < _count) {
          _notice =
              'Sono state trovate '
              '${_results.length} selezioni su '
              '$_count richieste. SmartBet ha '
              'controllato fino a '
              '$maximumToScan partite.';
        } else if (adaptiveCount > 0) {
          _notice =
              '$adaptiveCount selezioni sono state '
              'completate con criteri adattivi, '
              'mantenendo sempre quota minima 1.15.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _phase = '';
        _error = _friendlyError(e);
      });
    }
  }

  // ============================================================
  // ERRORI
  // ============================================================

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset')) {
      return 'Impossibile collegarsi al servizio dati. '
          'Controlla la connessione e riprova.';
    }

    if (text.contains('timeout')) {
      return 'Il servizio sta impiegando troppo tempo. Riprova tra poco.';
    }

    if (text.contains('429') || text.contains('rate limit')) {
      return 'Il servizio è temporaneamente occupato. Riprova tra poco.';
    }

    return 'Si è verificato un problema durante la creazione della schedina.';
  }

  // ============================================================
  // RIEPILOGO
  // ============================================================

  double get _averageProbability {
    if (_results.isEmpty) return 0;

    return _results.map((e) => e.probability).reduce((a, b) => a + b) /
        _results.length;
  }

  double get _averageSmartScore {
    if (_results.isEmpty) return 0;

    return _results.map((e) => e.analysis.smartScore).reduce((a, b) => a + b) /
        _results.length;
  }

  double get _combinedProbability {
    if (_results.isEmpty) return 0;

    var value = 1.0;

    for (final item in _results) {
      value *= item.probability / 100.0;
    }

    return value;
  }

  double? get _totalOdd {
    if (_results.isEmpty) return null;

    var value = 1.0;

    for (final item in _results) {
      final odd = item.odd;

      if (odd == null) {
        return null;
      }

      value *= odd;
    }

    return value;
  }

  String get _riskLabel {
    final combined = _combinedProbability;
    final totalOdd = _totalOdd ?? 0;

    // VALUE: profilo più aggressivo.
    if (_profileName == 'VALUE') {
      if (_results.length >= 8 || totalOdd >= 20.0 || combined < 0.05) {
        return 'Alto';
      }

      if (_results.length >= 6 || totalOdd >= 8.0 || combined < 0.15) {
        return 'Medio-Alto';
      }

      if (totalOdd >= 4.0 || combined < 0.30) {
        return 'Medio';
      }

      return 'Contenuto';
    }

    // BILANCIATA: tiene conto anche della quota totale.
    if (_profileName == 'BILANCIATA') {
      if (_results.length >= 8 || totalOdd >= 15.0 || combined < 0.08) {
        return 'Alto';
      }

      if (_results.length >= 6 || totalOdd >= 10.0 || combined < 0.18) {
        return 'Medio-Alto';
      }

      if (totalOdd >= 5.0 || combined < 0.35) {
        return 'Medio';
      }

      return 'Contenuto';
    }

    // PREMIUM: resta orientata all'affidabilità.
    if (_results.length >= 8 || combined < 0.05) {
      return 'Alto';
    }

    if (_results.length >= 6 || combined < 0.12) {
      return 'Medio-Alto';
    }

    if (combined < 0.25) {
      return 'Medio';
    }

    return 'Contenuto';
  }

  // ============================================================
  // CONDIVIDI
  // ============================================================

  Future<void> _share() async {
    if (_results.isEmpty) return;

    final text = StringBuffer()
      ..writeln('SMARTBET AI — SCHEDINA $_profileName')
      ..writeln()
      ..writeln('${_results.length} partite')
      ..writeln(
        _totalOdd == null
            ? 'Quota totale: non disponibile (Combo Chance senza quota reale)'
            : 'Quota totale: ${_totalOdd!.toStringAsFixed(2)}',
      )
      ..writeln('Probabilità media: ${_averageProbability.toStringAsFixed(1)}%')
      ..writeln('Smart Score medio: ${_averageSmartScore.toStringAsFixed(1)}')
      ..writeln(
        'Probabilità combinata teorica: '
        '${(_combinedProbability * 100).toStringAsFixed(2)}%',
      )
      ..writeln('Rischio: $_riskLabel')
      ..writeln();

    for (var i = 0; i < _results.length; i++) {
      final item = _results[i];

      text
        ..writeln('${i + 1}. ${item.match.homeTeam} - ${item.match.awayTeam}')
        ..writeln(
          item.odd == null
              ? '   ${item.market} — ${item.probability}% '
                    '(quota combo non disponibile)'
              : '   ${item.market} @ ${item.odd!.toStringAsFixed(2)} '
                    '— ${item.probability}%',
        );

      if (item.bookmaker.trim().isNotEmpty) {
        text.writeln('   ${item.bookmaker}');
      }
    }

    text
      ..writeln()
      ..writeln(
        'Analisi statistica a scopo informativo. Gioca responsabilmente.',
      );

    await SharePlus.instance.share(
      ShareParams(
        text: text.toString(),
        subject: 'SmartBet AI — Schedina $_profileName',
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  Color _probabilityColor(int value) {
    if (value >= 75) return Colors.greenAccent;
    if (value >= 65) return Colors.orangeAccent;
    return Colors.white70;
  }

  Color _evColor(double value) {
    if (value >= 0.05) return Colors.greenAccent;
    if (value >= 0) return Colors.orangeAccent;
    return Colors.white54;
  }

  Widget _profileSelector() {
    Widget chip(_CouponProfile profile, String label) {
      final selected = _profile == profile;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(
            label: SizedBox(
              width: double.infinity,
              child: Text(label, textAlign: TextAlign.center),
            ),
            selected: selected,
            showCheckmark: false,
            selectedColor: const Color(0xFF00C853),
            backgroundColor: const Color(0xFF1F2937),
            side: BorderSide(
              color: selected ? const Color(0xFF00C853) : Colors.white12,
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            onSelected: _loading
                ? null
                : (_) {
                    setState(() {
                      _profile = profile;
                      _results.clear();
                      _error = null;
                      _notice = null;
                    });
                  },
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_CouponProfile.premium, 'PREMIUM'),
        chip(_CouponProfile.balanced, 'BILANCIATA'),
        chip(_CouponProfile.value, 'VALUE'),
      ],
    );
  }

  Widget _periodSelector() {
    Widget chip(_CouponPeriod period, String label) {
      final selected = _period == period;

      return ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: const Color(0xFF00C853),
        backgroundColor: const Color(0xFF1F2937),
        side: BorderSide(
          color: selected ? const Color(0xFF00C853) : Colors.white12,
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        onSelected: _loading
            ? null
            : (_) async {
                if (period == _CouponPeriod.custom) {
                  await _selectCustomPeriod();
                  return;
                }

                setState(() {
                  _period = period;
                  _results.clear();
                  _error = null;
                  _notice = null;
                });
              },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Periodo partite',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(_CouponPeriod.today, 'OGGI'),
            chip(_CouponPeriod.weekend, '2 GIORNI'),
            chip(_CouponPeriod.next3Days, '3 GIORNI'),
            chip(_CouponPeriod.custom, 'PERSONALIZZATO'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Periodo selezionato: $_periodLabel',
          style: const TextStyle(
            color: Color(0xFF00C853),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    if (!_loading) return const SizedBox.shrink();

    final oddsPhase = _phase == 'odds';
    final current = oddsPhase ? _oddsProcessed : _processed;
    final total = oddsPhase ? _oddsTotal : _total;

    final value = total > 0
        ? (current / total).clamp(0.0, 1.0).toDouble()
        : null;

    return Column(
      children: [
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: value,
          minHeight: 7,
          borderRadius: BorderRadius.circular(20),
        ),
        const SizedBox(height: 8),
        Text(
          oddsPhase
              ? 'Controllo quote e profilo: $current / $total'
              : 'Pre-analisi statistica: $current / $total',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          oddsPhase
              ? 'Le probabilità sono già state calcolate: le quote servono solo al filtro finale.'
              : 'Ricerca delle candidate statisticamente più forti.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white30, fontSize: 9),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Crea Schedina AI'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C853), Color(0xFF00A896)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_motion, color: Colors.white, size: 30),
                SizedBox(height: 10),
                Text(
                  'LA MIA SCHEDINA AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'SmartBet calcola prima le probabilità e successivamente '
                  'usa le quote reali per costruire il profilo scelto.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Profilo schedina',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _profileSelector(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_profileName — $_profileSubtitle',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _profileDescription,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _periodSelector(),

          const SizedBox(height: 18),

          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: SwitchListTile(
              value: _italyScheduleOnly,
              activeThumbColor: const Color(0xFF00C853),
              title: const Text(
                'Palinsesto Italia',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _italyScheduleOnly
                    ? 'Competizioni principali più vicine ai palinsesti dei bookmaker italiani.'
                    : 'Tutte le competizioni disponibili.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _italyScheduleOnly = value;
                        _results.clear();
                        _error = null;
                        _notice = null;
                      });
                    },
            ),
          ),

          const SizedBox(height: 22),
          const Text(
            'Quante partite?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_count partite',
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          Slider(
            value: _count.toDouble(),
            min: 3,
            max: 15,
            divisions: 7,
            label: '$_count',
            onChanged: _loading
                ? null
                : (value) {
                    setState(() {
                      _count = value.round();
                      _results.clear();
                      _error = null;
                      _notice = null;
                    });
                  },
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _loading ? null : _createCoupon,
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _loading ? 'ANALISI IN CORSO...' : 'CREA LA MIA SCHEDINA AI',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF00C853),
            ),
          ),
          _progress(),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent, height: 1.4),
              ),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                _notice!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Schedina $_profileName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _summary(),
            const SizedBox(height: 15),
            ...List.generate(
              _results.length,
              (index) => _resultCard(_results[index], index + 1),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('CONDIVIDI SCHEDINA'),
            ),
          ],
          if (!_loading && _errors > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$_errors partite non analizzate per dati insufficienti '
              'o errore temporaneo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Le probabilità sono stime statistiche e non garantiscono '
            'l’esito delle partite. Le quote sono utilizzate dopo il '
            'calcolo probabilistico per selezionare il profilo della schedina.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _summaryRow('Partite', '${_results.length}'),
          _summaryRow(
            'Quota totale',
            _totalOdd == null ? 'N/D' : _totalOdd!.toStringAsFixed(2),
          ),
          _summaryRow(
            'Probabilità media',
            '${_averageProbability.toStringAsFixed(1)}%',
          ),
          _summaryRow(
            'Smart Score medio',
            _averageSmartScore.toStringAsFixed(1),
          ),
          _summaryRow(
            'Probabilità combinata',
            '${(_combinedProbability * 100).toStringAsFixed(2)}%',
          ),
          _summaryRow('Rischio', _riskLabel),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(_CouponPick item, int position) {
    final probabilityColor = _probabilityColor(item.probability);
    final evPercent = item.expectedValue * 100.0;
    final edgePoints = item.edge * 100.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.adaptive
              ? Colors.orangeAccent.withValues(alpha: 0.30)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$position. ${item.match.homeTeam} - ${item.match.awayTeam}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (item.adaptive)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'ADATTIVA',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            item.match.country.trim().isEmpty
                ? item.match.league
                : '${item.match.country} • ${item.match.league}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SCELTA AI',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.market,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'PROBABILITÀ',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.probability}%',
                    style: TextStyle(
                      color: probabilityColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.show_chart,
                  color: Colors.orangeAccent,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(
                  item.odd == null
                      ? 'Quota combo N/D'
                      : '@ ${item.odd!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.bookmaker,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Smart Score: ${item.analysis.smartScore}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              Text(
                'Edge ${edgePoints >= 0 ? '+' : ''}${edgePoints.toStringAsFixed(1)} p.p.',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(width: 10),
              Text(
                'EV ${evPercent >= 0 ? '+' : ''}${evPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _evColor(item.expectedValue),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
