import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/odds_service.dart';
import '../services/smartbet_market_probability_service.dart';
import '../services/smartbet_reliability_service.dart';
import '../services/italy_schedule_filter.dart';
import '../services/smartbet_ai_service.dart';
import '../services/smartbet_analysis_cache.dart';
import '../services/smartbet_local_auditor.dart';
import '../services/dual_engine_analysis_service.dart';
import '../widgets/dual_engine_summary.dart';
import '../widgets/team_stats_expansion.dart';
import '../widgets/competition_filter_sheet.dart';

class CreateAiCouponScreen extends StatefulWidget {
  const CreateAiCouponScreen({super.key});

  @override
  State<CreateAiCouponScreen> createState() => _CreateAiCouponScreenState();
}

enum _CouponProfile { complete, balanced, rapid }

enum _CouponMode { automatic, manual }

enum _CouponPeriod { today, weekend, next3Days, custom }

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
  final String auditorStatus;
  final DualEngineAnalysis? dualAnalysis;

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
    this.auditorStatus = 'NON VERIFICATO',
    this.dualAnalysis,
  });

  int? get reliabilityScore => SmartBetReliabilityService.score(
    analysis: analysis,
    market: market,
    probability: probability,
  );

  _CouponPick withDualAnalysis(DualEngineAnalysis value) {
    return _CouponPick(
      match: match,
      analysis: analysis,
      market: market,
      probability: probability,
      odd: odd,
      bookmaker: bookmaker,
      edge: edge,
      expectedValue: expectedValue,
      rankScore: rankScore,
      adaptive: adaptive,
      auditorStatus: auditorStatus,
      dualAnalysis: value,
    );
  }
}

class _PortfolioShadow {
  final String name;
  final List<_CouponPick> picks;

  const _PortfolioShadow({required this.name, required this.picks});
}

class _CreateAiCouponScreenState extends State<CreateAiCouponScreen> {
  final OddsService _oddsService = OddsService();
  final SmartBetAiService _aiService = SmartBetAiService();
  final SmartBetAnalysisCache _analysisCache = SmartBetAnalysisCache.instance;
  final DualEngineAnalysisService _dualEngineService =
      DualEngineAnalysisService();

  // PATCH 02 — AUDITED SCHEDINA

  _CouponMode _mode = _CouponMode.automatic;
  _CouponProfile _profile = _CouponProfile.complete;

  _CouponPeriod _period = _CouponPeriod.today;
  DateTimeRange? _customPeriod;
  int _count = 5;

  bool _loading = false;
  bool _italyScheduleOnly = true;
  final Set<String> _selectedCompetitionKeys = <String>{};
  String _phase = '';

  int _processed = 0;
  int _total = 0;
  int _errors = 0;
  int _oddsProcessed = 0;
  int _oddsTotal = 0;

  String? _error;
  String? _notice;

  final List<_CouponPick> _results = [];

  // P3B — portfolio automatico attivo.
  //
  // _results continua a rappresentare la schedina attualmente
  // visualizzata, così summary/card/share possono essere riutilizzati.
  final List<_PortfolioShadow> _portfolioResults = [];
  int _selectedPortfolioIndex = 0;

  final Map<int, MatchModel> _manualSelectedMatches = <int, MatchModel>{};

  static const double _minimumOdd = 1.25;
  // PATCH 02F-A — CAMPIONATI + RECOVERY RAPIDA

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
    'OVER 3.5',
    'UNDER 3.5',
    'OVER 4.5',
    'UNDER 4.5',
    'CASA SEGNA',
    'OSPITE SEGNA',
    'GOAL + O2.5',
    'NO GOAL + U2.5',
  ];

  @override
  void dispose() {
    _oddsService.dispose();
    _aiService.dispose();
    _dualEngineService.dispose();
    super.dispose();
  }

  // ============================================================
  // PROFILI
  // ============================================================
  String get _profileName {
    switch (_profile) {
      case _CouponProfile.complete:
        return 'COMPLETA';
      case _CouponProfile.balanced:
        return 'BILANCIATA';
      case _CouponProfile.rapid:
        return 'RAPIDA ⚡';
    }
  }

  // ============================================================
  // PROBABILITÀ DEI MERCATI
  // ============================================================

  Map<String, int> _markets(AnalysisResult r) {
    final markets = <String, int>{
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

    for (final market in SmartBetMarketProbabilityService.extendedMarkets) {
      markets[market] = SmartBetMarketProbabilityService.probabilityFor(
        r,
        market,
      );
    }

    return markets;
  }

  int _bestStatisticalProbability(AnalysisResult analysis) {
    var best = 0;

    for (final value in _markets(analysis).values) {
      if (value > best) {
        best = value;
      }
    }

    return best;
  }

  // ============================================================
  // FILTRI PROFILO
  // ============================================================
  bool _passesPrimary({required int probability, required int smartScore}) {
    final p = probability / 100.0;

    switch (_profile) {
      case _CouponProfile.complete:
        return p >= 0.65 && smartScore >= 50;

      case _CouponProfile.balanced:
      case _CouponProfile.rapid:
        return p >= 0.55 && smartScore >= 45;
    }
  }

  bool _passesAdaptive({required int probability, required int smartScore}) {
    final p = probability / 100.0;

    switch (_profile) {
      case _CouponProfile.complete:
        return p >= 0.55 && smartScore >= 40;

      case _CouponProfile.balanced:
      case _CouponProfile.rapid:
        return p >= 0.45 && smartScore >= 35;
    }
  }

  double _rankScore({required int probability, required int smartScore}) {
    // Ranking sportivo puro.
    //
    // Nessuna quota, probabilità implicita, edge o expected value
    // può modificare la classifica delle selezioni.
    return (probability * 0.55) + (smartScore * 0.45);
  }

  List<({String market, int probability})> _sportsMarketCandidates(
    AnalysisResult analysis,
  ) {
    final probabilities = _markets(analysis);
    final candidates = <({String market, int probability, int order})>[];

    for (var index = 0; index < _marketOrder.length; index++) {
      final market = _marketOrder[index];
      final probability = probabilities[market] ?? 0;

      if (probability <= 0) continue;

      candidates.add((market: market, probability: probability, order: index));
    }

    // Classifica puramente sportiva.
    //
    // Prima la probabilità stimata dal modello.
    // _marketOrder interviene soltanto come spareggio deterministico.
    candidates.sort((a, b) {
      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) return probability;

      return a.order.compareTo(b.order);
    });

    return candidates
        .map(
          (candidate) =>
              (market: candidate.market, probability: candidate.probability),
        )
        .toList();
  }

  _CouponPick? _bestPickForMatch({
    required _PreCandidate preliminary,
    required FixtureMarketOdds? odds,
  }) {
    // Ordine dei mercati deciso ESCLUSIVAMENTE dai dati sportivi.
    final sportsCandidates = _sportsMarketCandidates(preliminary.analysis);

    if (sportsCandidates.isEmpty) {
      return null;
    }

    final smartScore = preliminary.analysis.smartScore;

    for (final candidate in sportsCandidates) {
      final market = candidate.market;
      final probability = candidate.probability;

      final primary = _passesPrimary(
        probability: probability,
        smartScore: smartScore,
      );

      final adaptive =
          !primary &&
          _passesAdaptive(probability: probability, smartScore: smartScore);

      if (!primary && !adaptive) {
        continue;
      }

      // Soltanto ora controlliamo se QUEL mercato, già ordinato
      // sportivamente, è utilizzabile nella schedina.
      final bestOdd = odds?.oddFor(market);

      if (bestOdd == null || bestOdd.odd < _minimumOdd) {
        continue;
      }

      // Value layer informativo.
      // Edge ed EV NON cambiano mercato né ranking.
      final p = probability / 100.0;
      final impliedProbability = 1.0 / bestOdd.odd;
      final edge = p - impliedProbability;
      final expectedValue = (p * bestOdd.odd) - 1.0;

      return _CouponPick(
        match: preliminary.match,
        analysis: preliminary.analysis,
        market: market,
        probability: probability,
        odd: bestOdd.odd,
        bookmaker: bestOdd.bookmakerName,
        edge: edge,
        expectedValue: expectedValue,
        rankScore: _rankScore(probability: probability, smartScore: smartScore),
        adaptive: adaptive,
      );
    }

    return null;
  }

  _CouponPick? _manualPickForMatch({
    required MatchModel match,
    required AnalysisResult analysis,
    required FixtureMarketOdds? odds,
  }) {
    // In modalità manuale la partita è scelta dall'utente.
    //
    // Mostriamo quindi sempre il mercato statisticamente migliore,
    // indipendentemente dalla disponibilità o dal livello della quota.
    final sportsCandidates = _sportsMarketCandidates(analysis);

    if (sportsCandidates.isEmpty) {
      return null;
    }

    final sportsChoice = sportsCandidates.first;
    final market = sportsChoice.market;
    final probability = sportsChoice.probability;

    final quote = odds?.oddFor(market);
    final odd = quote?.odd;

    final edge = odd == null || odd <= 0
        ? 0.0
        : (probability / 100.0) - (1.0 / odd);

    final expectedValue = odd == null || odd <= 0
        ? 0.0
        : ((probability / 100.0) * odd) - 1.0;

    return _CouponPick(
      match: match,
      analysis: analysis,
      market: market,
      probability: probability,
      odd: odd,
      bookmaker: quote?.bookmakerName ?? 'Quota non disponibile',
      edge: edge,
      expectedValue: expectedValue,
      rankScore: _rankScore(
        probability: probability,
        smartScore: analysis.smartScore,
      ),
      adaptive: false,
      auditorStatus: 'NON VERIFICATO',
    );
  }

  _CouponPick _manualAuditedPick(_CouponPick pick) {
    var status = 'NON VERIFICATO';

    final odd = pick.odd;

    if (odd != null && odd > 0) {
      final audit = SmartBetLocalAuditor.evaluate(
        analysis: pick.analysis,
        market: pick.market,
        probability: pick.probability,
        odd: odd,
      );

      if (audit.isBlocked || audit.blocksMarket(pick.market)) {
        status = 'SCONSIGLIATA';
      } else if (audit.isDoubt) {
        status = 'CON RISERVA';
      } else {
        status = 'CONFERMATA';
      }
    }

    return _CouponPick(
      match: pick.match,
      analysis: pick.analysis,
      market: pick.market,
      probability: pick.probability,
      odd: pick.odd,
      bookmaker: pick.bookmaker,
      edge: pick.edge,
      expectedValue: pick.expectedValue,
      rankScore: pick.rankScore,
      adaptive: pick.adaptive,
      auditorStatus: status,
      dualAnalysis: pick.dualAnalysis,
    );
  }

  bool _hasRealQuotedMarket(FixtureMarketOdds? odds) {
    if (odds == null) return false;

    for (final market in _marketOrder) {
      final quote = odds.oddFor(market);
      if (quote != null && quote.odd >= _minimumOdd) {
        return true;
      }
    }

    return false;
  }

  double _preliminaryRankScore(_PreCandidate candidate) {
    // Screening puramente sportivo.
    //
    // Le quote NON devono influenzare l'accesso all'analisi avanzata.
    // Combiniamo la probabilità del mercato statistico migliore con
    // l'affidabilità generale del quadro espressa dallo Smart Score.
    return (candidate.bestProbability * 0.55) +
        (candidate.analysis.smartScore * 0.45);
  }

  int _advancedShortlistSize(int available) {
    // v1.2.1 RELIABILITY
    //
    // La vecchia shortlist era troppo stretta:
    // 5 risultati  -> 6 analisi avanzate
    // 10 risultati -> 12
    // 15 risultati -> 17
    //
    // Manteniamo un limite per controllare i costi, ma lasciamo
    // all'analisi avanzata un vero pool tra cui scegliere.

    int desired;
    int hardCap;

    switch (_profile) {
      case _CouponProfile.complete:
        desired = math.max(18, (_count * 2) + 6);
        hardCap = 40;
        break;

      case _CouponProfile.balanced:
        desired = math.max(14, (_count * 2) + 2);
        hardCap = 32;
        break;

      case _CouponProfile.rapid:
        desired = math.max(10, _count + 5);
        hardCap = 20;
        break;
    }

    final capped = math.min(desired, hardCap);
    return math.min(available, capped);
  }

  int _presentationCompare(_CouponPick a, _CouponPick b) {
    final countryA = a.match.country.trim().toLowerCase();
    final countryB = b.match.country.trim().toLowerCase();
    final country = countryA.compareTo(countryB);
    if (country != 0) return country;

    final league = a.match.league.trim().toLowerCase().compareTo(
      b.match.league.trim().toLowerCase(),
    );
    if (league != 0) return league;

    final dateA = DateTime.tryParse(a.match.date);
    final dateB = DateTime.tryParse(b.match.date);
    if (dateA != null && dateB != null) return dateA.compareTo(dateB);

    return '${a.match.homeTeam}-${a.match.awayTeam}'.compareTo(
      '${b.match.homeTeam}-${b.match.awayTeam}',
    );
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
      helpText: 'Periodo schedina GoalVdLine',
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
      _selectedCompetitionKeys.clear();
      _manualSelectedMatches.clear();
      _results.clear();
      _portfolioResults.clear();
      _selectedPortfolioIndex = 0;
      _error = null;
      _notice = null;
    });
  }

  // ============================================================
  // PARTITA NON INIZIATA
  // ============================================================

  bool _isUpcoming(MatchModel match) {
    final status = match.statusShort.trim().toUpperCase();

    // Se l'API conosce lo stato, accettiamo soltanto fixture
    // non ancora iniziate.
    //
    // FT / LIVE / HT / 1H / 2H / PST / CANC / ABD ecc.
    // non devono mai arrivare alla pipeline predittiva.
    if (status.isNotEmpty && status != 'NS') {
      return false;
    }

    try {
      final kickoff = DateTime.parse(match.date).toLocal();
      return kickoff.isAfter(DateTime.now());
    } catch (_) {
      // Fail closed: una data non interpretabile non è sicura
      // per un'analisi pre-match.
      return false;
    }
  }

  // ============================================================
  // CREA SCHEDINA
  // ============================================================

  Future<void> _analyzeManualCoupon() async {
    if (_loading) return;

    final matches = _manualSelectedMatches.values.where(_isUpcoming).toList();

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona almeno una partita da analizzare.'),
        ),
      );
      return;
    }

    matches.sort((a, b) {
      final dateA = DateTime.tryParse(a.date);
      final dateB = DateTime.tryParse(b.date);

      if (dateA != null && dateB != null) {
        return dateA.compareTo(dateB);
      }

      return a.homeTeam.compareTo(b.homeTeam);
    });

    setState(() {
      _loading = true;
      _phase = 'manual';
      _processed = 0;
      _total = matches.length;
      _oddsProcessed = 0;
      _oddsTotal = 0;
      _errors = 0;
      _error = null;
      _notice = null;
      _results.clear();
      _portfolioResults.clear();
      _selectedPortfolioIndex = 0;
    });

    try {
      final analyzed = <_CouponPick>[];

      // SmartBet viene eseguito a piccoli batch.
      // DiegoAI viene poi aggiunto in sequenza.
      const batchSize = 3;

      for (var start = 0; start < matches.length; start += batchSize) {
        final end = math.min(start + batchSize, matches.length);

        final batch = matches.sublist(start, end);

        final smartBetBatch = await Future.wait(
          batch.map((match) async {
            try {
              final cachedResult = await _analysisCache.read(match.fixtureId);

              final AnalysisResult smartBet;

              if (cachedResult != null) {
                debugPrint(
                  'SMARTBET MANUAL COUPON CACHE HIT: '
                  '${match.fixtureId}',
                );

                smartBet = cachedResult;
              } else {
                debugPrint(
                  'SMARTBET MANUAL COUPON CACHE MISS: '
                  '${match.fixtureId}',
                );

                smartBet = await _aiService.analyzeMatch(
                  match,
                  runAudit: false,
                  automaticMode: true,
                );

                if (smartBet.smartScore > 0) {
                  await _analysisCache.write(match.fixtureId, smartBet);
                }
              }

              if (smartBet.smartScore <= 0) {
                return null;
              }

              FixtureMarketOdds? odds;

              try {
                odds = await _oddsService.getFixtureMarketOdds(
                  fixtureId: match.fixtureId,
                );
              } catch (_) {
                odds = null;
              }

              final pick = _manualPickForMatch(
                match: match,
                analysis: smartBet,
                odds: odds,
              );

              if (pick == null) {
                return null;
              }

              return _manualAuditedPick(pick);
            } catch (e) {
              debugPrint(
                'SMARTBET MANUAL COUPON ERROR '
                '${match.fixtureId}: $e',
              );
              return null;
            }
          }),
        );

        final successful = smartBetBatch.whereType<_CouponPick>().toList();

        _errors += batch.length - successful.length;

        // DiegoAI: una partita alla volta sul servizio condiviso.
        for (final pick in successful) {
          try {
            final dual = await _dualEngineService.attachDiego(
              match: pick.match,
              smartBet: pick.analysis,
              smartBetMarket: pick.market,
              smartBetProbability: pick.probability,
            );

            analyzed.add(pick.withDualAnalysis(dual));
          } catch (_) {
            // Anche se Diego non fosse disponibile,
            // conserviamo comunque il risultato SmartBet.
            analyzed.add(pick);
          }
        }

        final live = List<_CouponPick>.from(analyzed)
          ..sort(_presentationCompare);

        if (!mounted) return;

        setState(() {
          _processed = end;
          _results
            ..clear()
            ..addAll(live);
        });
      }

      analyzed.sort(_presentationCompare);

      if (!mounted) return;

      final discouraged = analyzed
          .where((item) => item.auditorStatus == 'SCONSIGLIATA')
          .length;

      final reserved = analyzed
          .where((item) => item.auditorStatus == 'CON RISERVA')
          .length;

      setState(() {
        _results
          ..clear()
          ..addAll(analyzed);

        _loading = false;
        _phase = '';

        if (_results.isEmpty) {
          _error = 'Non è stato possibile analizzare le partite selezionate.';
          return;
        }

        final notes = <String>[];

        if (_errors > 0) {
          notes.add('$_errors partite non hanno prodotto dati sufficienti');
        }

        if (discouraged > 0) {
          notes.add('$discouraged selezioni sono sconsigliate dall’Auditor');
        }

        if (reserved > 0) {
          notes.add('$reserved selezioni sono con riserva');
        }

        if (notes.isNotEmpty) {
          _notice = '${notes.join(' • ')}.';
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

  Future<void> _createCoupon() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _phase = 'preliminary';
      _processed = 0;
      _total = 0;
      _oddsProcessed = 0;
      _oddsTotal = 0;
      _errors = 0;
      _error = null;
      _notice = null;
      _results.clear();
      _portfolioResults.clear();
      _selectedPortfolioIndex = 0;
    });

    try {
      final all = await _loadMatchesForSelectedPeriod();
      final matches = all
          .where(
            (m) =>
                m.hasTeamIds &&
                _isUpcoming(m) &&
                (!_italyScheduleOnly || ItalyScheduleFilter.allows(m)) &&
                (_selectedCompetitionKeys.isEmpty ||
                    _selectedCompetitionKeys.contains(
                      CompetitionFilterSheet.keyFor(m),
                    )),
          )
          .toList();

      if (!mounted) return;

      if (matches.isEmpty) {
        setState(() {
          _loading = false;
          _phase = '';
          _error =
              'Non ci sono partite ancora da giocare disponibili nel periodo selezionato.';
        });
        return;
      }

      // Fase 1: pre-analisi locale economica. Nessuna analisi SmartBet avanzata qui.
      final maximumToScan = matches.length;
      final preliminaryBatchSize = _profile == _CouponProfile.rapid ? 10 : 6;
      final preliminary = <_PreCandidate>[];

      setState(() {
        _total = maximumToScan;
      });

      for (
        var start = 0;
        start < maximumToScan;
        start += preliminaryBatchSize
      ) {
        final end = math.min(start + preliminaryBatchSize, maximumToScan);
        final batch = matches.sublist(start, end);

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final result = await SmartCore.analyze(match);
              final probability = _bestStatisticalProbability(result);
              if (probability <= 0) return null;

              return _PreCandidate(
                match: match,
                analysis: result,
                bestProbability: probability,
              );
            } catch (_) {
              return null;
            }
          }),
        );

        final valid = analyzed.whereType<_PreCandidate>();
        preliminary.addAll(valid);

        // Ogni partita fallita deve essere conteggiata una sola volta.
        _errors += analyzed.length - valid.length;

        if (!mounted) return;
        setState(() {
          _processed = end;
        });
      }

      preliminary.sort((a, b) {
        final rank = _preliminaryRankScore(
          b,
        ).compareTo(_preliminaryRankScore(a));

        if (rank != 0) return rank;

        final probability = b.bestProbability.compareTo(a.bestProbability);
        if (probability != 0) return probability;

        final smart = b.analysis.smartScore.compareTo(a.analysis.smartScore);
        if (smart != 0) return smart;

        // Il peso del campionato resta soltanto un ultimo spareggio.
        // Non decide più quali partite vengono analizzate.
        return b.match.aiWeight.compareTo(a.match.aiWeight);
      });

      if (preliminary.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _phase = '';
          _error =
              'GoalVdLine non ha trovato partite con dati statistici sufficienti.';
        });
        return;
      }

      // Fase 2: shortlist sportiva PRIMA delle quote.
      //
      // Le candidate che accedono all'analisi avanzata vengono scelte
      // esclusivamente dal ranking statistico preliminare.
      // La disponibilità o il valore della quota NON può più impedirne
      // l'accesso all'analisi AI.
      final advancedCount = _advancedShortlistSize(preliminary.length);

      final advancedShortlist = preliminary
          .take(math.min(advancedCount, preliminary.length))
          .toList();

      final reservePreliminary = preliminary
          .skip(advancedShortlist.length)
          .toList();

      final quoteCache = <int, FixtureMarketOdds?>{};

      final audited = <_PreCandidate>[];
      var auditRejected = 0;
      var localAdvancedFallback = false;

      final aiBatchSize = _profile == _CouponProfile.rapid ? 4 : 2;

      if (!mounted) return;
      setState(() {
        _phase = 'advanced';
        _oddsProcessed = 0;
        _oddsTotal = advancedShortlist.length;
      });

      var completedAdvanced = 0;

      for (
        var start = 0;
        start < advancedShortlist.length;
        start += aiBatchSize
      ) {
        final end = math.min(start + aiBatchSize, advancedShortlist.length);
        final batch = advancedShortlist.sublist(start, end);

        final advanced = await Future.wait(
          batch.map((candidate) async {
            try {
              final cachedResult = await _analysisCache.read(
                candidate.match.fixtureId,
              );

              final AnalysisResult result;

              if (cachedResult != null) {
                debugPrint(
                  'SMARTBET COUPON CACHE HIT: '
                  '${candidate.match.fixtureId}',
                );

                result = cachedResult;
              } else {
                debugPrint(
                  'SMARTBET COUPON CACHE MISS: '
                  '${candidate.match.fixtureId}',
                );

                result = await _aiService.analyzeMatch(
                  candidate.match,
                  runAudit: false,
                  automaticMode: true,
                );

                if (result.smartScore > 0) {
                  await _analysisCache.write(candidate.match.fixtureId, result);
                }
              }

              if (result.smartScore <= 0) {
                _errors++;
                return null;
              }

              return _PreCandidate(
                match: candidate.match,
                analysis: result,
                bestProbability: _bestStatisticalProbability(result),
              );
            } catch (_) {
              return null;
            } finally {
              completedAdvanced++;
              if (mounted) {
                setState(() {
                  _oddsProcessed = math.min(completedAdvanced, _oddsTotal);
                });
              }
            }
          }),
        );

        audited.addAll(advanced.whereType<_PreCandidate>());
        if (!mounted) return;
      }

      if (audited.isEmpty) {
        // Le candidate hanno già superato:
        // - presenza ID
        // - SmartCore locale
        // - controllo statistico
        // - presenza quote reali
        //
        // Se il servizio AI avanzato fallisce temporaneamente,
        // NON buttiamo via candidate già valide.
        //
        // Continuiamo con l'analisi locale e lasciamo comunque
        // all'Auditor finale il controllo di qualità.
        localAdvancedFallback = true;

        audited.addAll(advancedShortlist);

        if (!mounted) return;

        setState(() {
          _notice =
              'Analisi avanzata temporaneamente non disponibile. '
              'GoalVdLine continua con analisi statistica locale, '
              'quote reali e controlli di qualità.';
        });
      }

      audited.sort((a, b) {
        final probability = b.bestProbability.compareTo(a.bestProbability);
        if (probability != 0) return probability;
        return b.analysis.smartScore.compareTo(a.analysis.smartScore);
      });

      // Fase 4: quote soltanto DOPO l'analisi avanzata.
      //
      // Controlliamo tutte le candidate avanzate e una riserva limitata.
      // Le quote servono da questo punto in avanti per fattibilità/value,
      // non per decidere chi merita l'analisi avanzata.
      final reserveQuoteLimit = math.min(
        reservePreliminary.length,
        math.max(_count * 2, 10),
      );

      final reserveQuoteProbe = reservePreliminary
          .take(reserveQuoteLimit)
          .toList();

      final quoteCandidates = <_PreCandidate>[...audited, ...reserveQuoteProbe];

      final quoteBatchSize = _profile == _CouponProfile.rapid ? 8 : 6;

      if (!mounted) return;

      setState(() {
        _phase = 'odds';
        _oddsProcessed = 0;
        _oddsTotal = quoteCandidates.length;
      });

      for (
        var start = 0;
        start < quoteCandidates.length;
        start += quoteBatchSize
      ) {
        final end = math.min(start + quoteBatchSize, quoteCandidates.length);
        final batch = quoteCandidates.sublist(start, end);

        await Future.wait(
          batch.map((candidate) async {
            try {
              final odds = await _oddsService.getFixtureMarketOdds(
                fixtureId: candidate.match.fixtureId,
              );

              if (_hasRealQuotedMarket(odds)) {
                quoteCache[candidate.match.fixtureId] = odds;
              }
            } catch (_) {
              _errors++;
            }
          }),
        );

        if (!mounted) return;

        setState(() {
          _oddsProcessed = end;
        });
      }

      final reserveQuoted = reserveQuoteProbe
          .where(
            (candidate) => quoteCache.containsKey(candidate.match.fixtureId),
          )
          .toList();

      final hasAdvancedQuotedCandidate = audited.any(
        (candidate) => quoteCache.containsKey(candidate.match.fixtureId),
      );

      if (!hasAdvancedQuotedCandidate && reserveQuoted.isEmpty) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _phase = '';
          _error =
              'Nessuna candidata dispone di quote reali sufficienti '
              'per i mercati GoalVdLine.';
        });

        return;
      }

      final qualified = <_CouponPick>[];

      if (!mounted) return;
      setState(() {
        _phase = 'selection';
        _oddsProcessed = 0;
        _oddsTotal = audited.length;
      });

      for (var index = 0; index < audited.length; index++) {
        final candidate = audited[index];
        final pick = _bestPickForMatch(
          preliminary: candidate,
          odds: quoteCache[candidate.match.fixtureId],
        );

        if (pick != null) qualified.add(pick);

        if (!mounted) return;
        final liveSelected = _liveSelectionSnapshot(qualified);
        setState(() {
          _oddsProcessed = index + 1;
          _results
            ..clear()
            ..addAll(liveSelected);
        });
      }

      // Recovery quote-first: solo riserve già quotate.
      if (qualified.length < _count && reserveQuoted.isNotEmpty) {
        if (!mounted) return;

        setState(() {
          _phase = 'recovery';
          _oddsProcessed = 0;
          _oddsTotal = reserveQuoted.length;
        });

        final recoveryBatchSize = _profile == _CouponProfile.rapid ? 4 : 2;

        for (
          var start = 0;
          start < reserveQuoted.length && qualified.length < _count;
          start += recoveryBatchSize
        ) {
          final end = math.min(start + recoveryBatchSize, reserveQuoted.length);
          final batch = reserveQuoted.sublist(start, end);

          final recovered = await Future.wait(
            batch.map((candidate) async {
              if (localAdvancedFallback) {
                return _bestPickForMatch(
                  preliminary: candidate,
                  odds: quoteCache[candidate.match.fixtureId],
                );
              }

              try {
                final cachedResult = await _analysisCache.read(
                  candidate.match.fixtureId,
                );

                final AnalysisResult result;

                if (cachedResult != null) {
                  debugPrint(
                    'SMARTBET COUPON RECOVERY CACHE HIT: '
                    '${candidate.match.fixtureId}',
                  );

                  result = cachedResult;
                } else {
                  debugPrint(
                    'SMARTBET COUPON RECOVERY CACHE MISS: '
                    '${candidate.match.fixtureId}',
                  );

                  result = await _aiService.analyzeMatch(
                    candidate.match,
                    runAudit: false,
                    automaticMode: true,
                  );

                  if (result.smartScore > 0) {
                    await _analysisCache.write(
                      candidate.match.fixtureId,
                      result,
                    );
                  }
                }

                if (result.smartScore <= 0) return null;

                final recoveryCandidate = _PreCandidate(
                  match: candidate.match,
                  analysis: result,
                  bestProbability: _bestStatisticalProbability(result),
                );

                return _bestPickForMatch(
                  preliminary: recoveryCandidate,
                  odds: quoteCache[candidate.match.fixtureId],
                );
              } catch (_) {
                _errors++;
                return null;
              }
            }),
          );

          for (final pick in recovered) {
            if (pick == null) continue;
            if (qualified.any(
              (existing) => existing.match.fixtureId == pick.match.fixtureId,
            )) {
              continue;
            }
            qualified.add(pick);
          }

          if (!mounted) return;
          final liveSelected = _liveSelectionSnapshot(qualified);
          setState(() {
            _oddsProcessed = end;
            _results
              ..clear()
              ..addAll(liveSelected);
          });
        }
      }

      // v1.2.1 — Ranking sportivo Reliability-first.
      //
      // Nessuna quota, edge o EV entra in questo ordinamento.
      // L'Auditor resta uno strato successivo di fattibilità.
      qualified.sort(_reliabilityRankingCompare);

      // v1.2.1 — confronto shadow:
      // mostra cosa cambierebbe ordinando per Reliability,
      // senza modificare la schedina reale.
      _logReliabilityRankingShadow(qualified);

      // Verifica locale finale di fattibilità:
      // controlla prima SOLO le vere finaliste.
      // Le riserve vengono auditate soltanto se una finalista viene bloccata.
      final feasible = <_CouponPick>[];

      // PORTFOLIO P2
      //
      // Non ci fermiamo più alle sole _count finaliste.
      // Auditiamo un pool più ampio da riutilizzare nella fase
      // successiva per costruire più schedine coordinate.
      //
      // 3 eventi  -> fino a 11 candidate validate
      // 5 eventi  -> fino a 13 candidate validate
      // 7 eventi  -> fino a 15 candidate validate
      // 10 eventi -> fino a 20 candidate validate
      // 15 eventi -> fino a 30 candidate validate
      //
      // Il valore viene comunque limitato alla quantità reale
      // di candidate qualificate disponibili.
      final portfolioAuditTarget = math.min(
        qualified.length,
        math.max(_count + 8, _count * 2),
      );

      final finalists = qualified.take(portfolioAuditTarget).toList();
      final reserves = qualified.skip(portfolioAuditTarget).toList();

      if (finalists.isNotEmpty) {
        if (!mounted) return;

        setState(() {
          _phase = 'audit';
          _oddsProcessed = 0;
          _oddsTotal = finalists.length;
        });

        final checkedFinalists = await Future.wait(
          finalists.map((pick) async {
            final audit = SmartBetLocalAuditor.evaluate(
              analysis: pick.analysis,
              market: pick.market,
              probability: pick.probability,
              odd: pick.odd ?? 0.0,
            );

            if (audit.isBlocked || audit.blocksMarket(pick.market)) {
              auditRejected++;
              return null;
            }

            return _CouponPick(
              match: pick.match,
              analysis: pick.analysis,
              market: pick.market,
              probability: pick.probability,
              odd: pick.odd,
              bookmaker: pick.bookmaker,
              edge: pick.edge,
              expectedValue: pick.expectedValue,
              rankScore: pick.rankScore,
              adaptive: pick.adaptive,
              auditorStatus: audit.isDoubt ? 'CON RISERVA' : 'CONFERMATA',
            );
          }),
        );

        feasible.addAll(checkedFinalists.whereType<_CouponPick>());

        if (!mounted) return;

        setState(() {
          _oddsProcessed = finalists.length;
        });

        var reserveIndex = 0;

        while (feasible.length < portfolioAuditTarget &&
            reserveIndex < reserves.length) {
          final pick = reserves[reserveIndex++];
          final audit = SmartBetLocalAuditor.evaluate(
            analysis: pick.analysis,
            market: pick.market,
            probability: pick.probability,
            odd: pick.odd ?? 0.0,
          );

          if (!mounted) return;

          setState(() {
            _oddsTotal = finalists.length + reserveIndex;
            _oddsProcessed = finalists.length + reserveIndex;
          });

          if (audit.isBlocked || audit.blocksMarket(pick.market)) {
            auditRejected++;
            continue;
          }

          feasible.add(
            _CouponPick(
              match: pick.match,
              analysis: pick.analysis,
              market: pick.market,
              probability: pick.probability,
              odd: pick.odd,
              bookmaker: pick.bookmaker,
              edge: pick.edge,
              expectedValue: pick.expectedValue,
              rankScore: pick.rankScore,
              adaptive: pick.adaptive,
              auditorStatus: audit.isDoubt ? 'CON RISERVA' : 'CONFERMATA',
            ),
          );
        }
      }

      debugPrint('');
      debugPrint('========================================');
      debugPrint('GOALVDLINE PORTFOLIO POOL — P2');
      debugPrint('========================================');
      debugPrint(
        'Richieste: $_count | '
        'Qualified: ${qualified.length} | '
        'Target audit: $portfolioAuditTarget | '
        'Validate: ${feasible.length}',
      );

      for (var index = 0; index < feasible.length; index++) {
        final item = feasible[index];

        debugPrint(
          '${index + 1}. '
          '${item.match.homeTeam} - ${item.match.awayTeam} '
          '| ${item.market} '
          '| P ${item.probability} '
          '| REL ${item.reliabilityScore ?? -1} '
          '| SCORE ${item.rankScore.toStringAsFixed(1)} '
          '| AUDIT ${item.auditorStatus}',
        );
      }

      debugPrint('========================================');

      // P3B — PORTFOLIO ATTIVO
      //
      // Le cinque schedine vengono costruite sullo stesso pool già
      // analizzato e auditato. Nessuna nuova analisi SmartBet viene
      // eseguita per creare le varianti.
      final portfolio = _buildPortfolioShadow(feasible);
      _logPortfolioShadow(portfolio);

      if (portfolio.isEmpty) {
        if (!mounted) return;

        setState(() {
          _portfolioResults.clear();
          _selectedPortfolioIndex = 0;
          _results.clear();
          _loading = false;
          _phase = '';
          _error =
              'GoalVdLine non ha trovato abbastanza selezioni valide '
              'per costruire il portfolio.';
        });

        return;
      }

      // ------------------------------------------------------------
      // DIEGO DEDUPLICATO
      // ------------------------------------------------------------
      //
      // Ogni fixture può comparire in più schedine.
      // Diego viene quindi calcolato una sola volta per partita,
      // poi lo stesso risultato viene riutilizzato in tutte le varianti.
      final uniqueByFixture = <int, _CouponPick>{};

      for (final coupon in portfolio) {
        for (final item in coupon.picks) {
          uniqueByFixture.putIfAbsent(item.match.fixtureId, () => item);
        }
      }

      debugPrint('');
      debugPrint('========================================');
      debugPrint('GOALVDLINE PORTFOLIO — DIEGO DEDUP');
      debugPrint('========================================');
      debugPrint(
        '5 schedine | '
        '${portfolio.expand((e) => e.picks).length} posti totali | '
        '${uniqueByFixture.length} fixture uniche da elaborare',
      );

      final enrichedByFixture = <int, _CouponPick>{};

      for (final item in uniqueByFixture.values) {
        try {
          final dual = await _dualEngineService.attachDiego(
            match: item.match,
            smartBet: item.analysis,
            smartBetMarket: item.market,
            smartBetProbability: item.probability,
          );

          enrichedByFixture[item.match.fixtureId] = item.withDualAnalysis(dual);
        } catch (e) {
          // SmartBet resta valido anche se Diego non è disponibile.
          debugPrint(
            'PORTFOLIO DIEGO ERROR '
            '${item.match.fixtureId}: $e',
          );

          enrichedByFixture[item.match.fixtureId] = item;
        }
      }

      final enrichedPortfolio = portfolio.map((coupon) {
        final picks = coupon.picks.map((item) {
          return enrichedByFixture[item.match.fixtureId] ?? item;
        }).toList()..sort(_presentationCompare);

        return _PortfolioShadow(name: coupon.name, picks: picks);
      }).toList();

      final firstPortfolio = enrichedPortfolio.first;

      // Manteniamo il Reliability log sulla prima schedina,
      // ora corrispondente alla CORE.
      _logReliabilityShadow(firstPortfolio.picks);

      final adaptiveCount = firstPortfolio.picks
          .where((e) => e.adaptive)
          .length;

      final incompletePortfolios = enrichedPortfolio
          .where((coupon) => coupon.picks.length < _count)
          .length;

      if (!mounted) return;

      setState(() {
        _portfolioResults
          ..clear()
          ..addAll(enrichedPortfolio);

        _selectedPortfolioIndex = 0;

        // _results è sempre la schedina attualmente visualizzata.
        _results
          ..clear()
          ..addAll(firstPortfolio.picks);

        _loading = false;
        _phase = '';

        if (_results.isEmpty) {
          _error = _aiService.aiServiceUnavailable
              ? _aiService.aiServiceUnavailableMessage
              : 'GoalVdLine non ha trovato selezioni con quota disponibile '
                    'di almeno 1.25 che abbiano superato i controlli di qualità.';
        } else if (incompletePortfolios > 0) {
          _notice =
              '$incompletePortfolios schedine del portfolio contengono meno '
              'di $_count eventi: GoalVdLine non forza selezioni deboli.'
              '${auditRejected > 0 ? ' L’Auditor ha escluso $auditRejected candidate.' : ''}';
        } else if (adaptiveCount > 0 || auditRejected > 0) {
          final parts = <String>[];

          if (adaptiveCount > 0) {
            parts.add('$adaptiveCount selezioni usano criteri adattivi');
          }

          if (auditRejected > 0) {
            parts.add('l’Auditor ha escluso $auditRejected candidate');
          }

          _notice =
              '${parts.join(' • ')}. '
              'Portfolio di ${_portfolioResults.length} schedine creato. '
              'Quota minima: 1.25.';
        } else {
          _notice =
              'Portfolio GoalVdLine creato: '
              '${_portfolioResults.length} schedine coordinate '
              'dalla stessa analisi.';
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

  int _reliabilityRankingCompare(_CouponPick a, _CouponPick b) {
    final reliabilityA = a.reliabilityScore;
    final reliabilityB = b.reliabilityScore;

    // Quando entrambi hanno Reliability reale, questa è il
    // criterio sportivo principale.
    if (reliabilityA != null && reliabilityB != null) {
      final reliability = reliabilityB.compareTo(reliabilityA);
      if (reliability != 0) return reliability;

      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) return probability;

      final smartScore = b.analysis.smartScore.compareTo(a.analysis.smartScore);
      if (smartScore != 0) return smartScore;

      final oldScore = b.rankScore.compareTo(a.rankScore);
      if (oldScore != 0) return oldScore;

      return a.match.fixtureId.compareTo(b.match.fixtureId);
    }

    // Una Reliability misurata viene preferita a una candidata
    // la cui affidabilità è N/D.
    if (reliabilityA != null) return -1;
    if (reliabilityB != null) return 1;

    // Se Reliability non è disponibile per entrambe, manteniamo
    // il comportamento precedente come fallback sicuro.
    final oldScore = b.rankScore.compareTo(a.rankScore);
    if (oldScore != 0) return oldScore;

    final probability = b.probability.compareTo(a.probability);
    if (probability != 0) return probability;

    final smartScore = b.analysis.smartScore.compareTo(a.analysis.smartScore);
    if (smartScore != 0) return smartScore;

    return a.match.fixtureId.compareTo(b.match.fixtureId);
  }

  List<_CouponPick> _portfolioVariantTake(
    Iterable<_CouponPick> source,
    int limit, {
    Iterable<_CouponPick> seed = const <_CouponPick>[],
    Set<int> avoidFixtures = const <int>{},
  }) {
    final result = <_CouponPick>[];
    final fixtures = <int>{};

    // Le CORE vengono inserite per prime.
    for (final item in seed) {
      if (result.length >= limit) break;

      if (fixtures.add(item.match.fixtureId)) {
        result.add(item);
      }
    }

    // Primo passaggio:
    // preferiamo partite non presenti nelle schedine da evitare.
    for (final item in source) {
      if (result.length >= limit) break;

      if (avoidFixtures.contains(item.match.fixtureId)) {
        continue;
      }

      if (fixtures.add(item.match.fixtureId)) {
        result.add(item);
      }
    }

    // Secondo passaggio:
    // se il pool realmente valido non basta, riutilizziamo candidate
    // già presenti altrove. Non introduciamo però nuove candidate deboli:
    // source è già stato filtrato prima della costruzione del portfolio.
    for (final item in source) {
      if (result.length >= limit) break;

      if (fixtures.add(item.match.fixtureId)) {
        result.add(item);
      }
    }

    return result;
  }

  int _portfolioReliability(_CouponPick item) {
    return item.reliabilityScore ??
        ((item.probability * 0.55) + (item.analysis.smartScore * 0.45)).round();
  }

  Set<int> _portfolioNonCoreFixtures(
    List<_CouponPick> coupon,
    Set<int> sharedCoreFixtures,
  ) {
    return coupon
        .where((item) => !sharedCoreFixtures.contains(item.match.fixtureId))
        .map((item) => item.match.fixtureId)
        .toSet();
  }

  List<_PortfolioShadow> _buildPortfolioShadow(List<_CouponPick> source) {
    if (source.isEmpty) {
      return const <_PortfolioShadow>[];
    }

    // PORTFOLIO P3A.1
    //
    // Diversificare non deve significare abbassare la qualità.
    // Le alternative con EV o edge negativi non vengono utilizzate
    // per riempire artificialmente le cinque schedine.
    final eligible = source
        .where((item) => item.expectedValue >= 0.0 && item.edge >= 0.0)
        .toList();

    if (eligible.isEmpty) {
      return const <_PortfolioShadow>[];
    }

    final reliabilityRanked = List<_CouponPick>.of(eligible)
      ..sort(_reliabilityRankingCompare);

    // CORE condivise:
    // circa il 30% del numero di eventi richiesto.
    //
    // 3  -> 1
    // 5  -> 2
    // 7  -> 3
    // 10 -> 3
    // 15 -> 5
    final sharedCoreCount = math.min(
      reliabilityRanked.length,
      math.max(1, (_count * 0.30).ceil()),
    );

    final sharedCore = _portfolioVariantTake(
      reliabilityRanked,
      sharedCoreCount,
    );

    final sharedCoreFixtures = sharedCore
        .map((item) => item.match.fixtureId)
        .toSet();

    // ============================================================
    // 1. CORE
    // ============================================================
    //
    // Riferimento principale:
    // Reliability -> probabilità -> Smart Score -> ranking storico.
    final coreCoupon = _portfolioVariantTake(reliabilityRanked, _count);

    final coreAlternatives = _portfolioNonCoreFixtures(
      coreCoupon,
      sharedCoreFixtures,
    );

    // ============================================================
    // 2. PROBABILITÀ
    // ============================================================
    //
    // Mantiene soltanto le CORE obbligatorie e privilegia
    // probabilità assoluta + Reliability.
    //
    // Prima prova a NON utilizzare le altre partite della CORE.
    final probabilityRanked = List<_CouponPick>.of(eligible)
      ..sort((a, b) {
        final probability = b.probability.compareTo(a.probability);
        if (probability != 0) return probability;

        final reliability = _portfolioReliability(
          b,
        ).compareTo(_portfolioReliability(a));
        if (reliability != 0) return reliability;

        return b.rankScore.compareTo(a.rankScore);
      });

    final probabilityCoupon = _portfolioVariantTake(
      probabilityRanked,
      _count,
      seed: sharedCore,
      avoidFixtures: coreAlternatives,
    );

    final probabilityAlternatives = _portfolioNonCoreFixtures(
      probabilityCoupon,
      sharedCoreFixtures,
    );

    // ============================================================
    // 3. EQUILIBRIO
    // ============================================================
    //
    // Usa il ranking complessivo GoalVdLine come criterio principale,
    // ma cerca prima candidate non già utilizzate nelle parti
    // non-CORE delle prime due schedine.
    final balanceRanked = List<_CouponPick>.of(eligible)
      ..sort((a, b) {
        final score = b.rankScore.compareTo(a.rankScore);
        if (score != 0) return score;

        final reliability = _portfolioReliability(
          b,
        ).compareTo(_portfolioReliability(a));
        if (reliability != 0) return reliability;

        return b.probability.compareTo(a.probability);
      });

    final balanceAvoid = <int>{...coreAlternatives, ...probabilityAlternatives};

    final balanceCoupon = _portfolioVariantTake(
      balanceRanked,
      _count,
      seed: sharedCore,
      avoidFixtures: balanceAvoid,
    );

    final balanceAlternatives = _portfolioNonCoreFixtures(
      balanceCoupon,
      sharedCoreFixtures,
    );

    // ============================================================
    // 4. VALUE
    // ============================================================
    //
    // Sempre candidate già validate e con EV/edge non negativi.
    // Tra queste privilegia EV -> edge -> Reliability.
    final valueRanked = List<_CouponPick>.of(eligible)
      ..sort((a, b) {
        final expectedValue = b.expectedValue.compareTo(a.expectedValue);
        if (expectedValue != 0) return expectedValue;

        final edge = b.edge.compareTo(a.edge);
        if (edge != 0) return edge;

        final reliability = _portfolioReliability(
          b,
        ).compareTo(_portfolioReliability(a));
        if (reliability != 0) return reliability;

        return b.probability.compareTo(a.probability);
      });

    final valueAvoid = <int>{
      ...coreAlternatives,
      ...probabilityAlternatives,
      ...balanceAlternatives,
    };

    final valueCoupon = _portfolioVariantTake(
      valueRanked,
      _count,
      seed: sharedCore,
      avoidFixtures: valueAvoid,
    );

    // ============================================================
    // 5. DIVERSIFICATA
    // ============================================================
    //
    // Misura quante volte ogni partita è già comparsa.
    // A parità di utilizzo vince sempre la candidata più affidabile.
    final usage = <int, int>{};

    void registerUsage(List<_CouponPick> coupon) {
      for (final item in coupon) {
        usage[item.match.fixtureId] = (usage[item.match.fixtureId] ?? 0) + 1;
      }
    }

    registerUsage(coreCoupon);
    registerUsage(probabilityCoupon);
    registerUsage(balanceCoupon);
    registerUsage(valueCoupon);

    final diversifiedRanked = List<_CouponPick>.of(eligible)
      ..sort((a, b) {
        final usageA = usage[a.match.fixtureId] ?? 0;
        final usageB = usage[b.match.fixtureId] ?? 0;

        final use = usageA.compareTo(usageB);
        if (use != 0) return use;

        final reliability = _portfolioReliability(
          b,
        ).compareTo(_portfolioReliability(a));
        if (reliability != 0) return reliability;

        final probability = b.probability.compareTo(a.probability);
        if (probability != 0) return probability;

        return b.rankScore.compareTo(a.rankScore);
      });

    final diversifiedCoupon = _portfolioVariantTake(
      diversifiedRanked,
      _count,
      seed: sharedCore,
    );

    debugPrint(
      'PORTFOLIO ELIGIBLE: '
      '${eligible.length}/${source.length} '
      '(EV >= 0, edge >= 0)',
    );

    return <_PortfolioShadow>[
      _PortfolioShadow(name: 'CORE', picks: coreCoupon),
      _PortfolioShadow(name: 'PROBABILITÀ', picks: probabilityCoupon),
      _PortfolioShadow(name: 'EQUILIBRIO', picks: balanceCoupon),
      _PortfolioShadow(name: 'VALUE', picks: valueCoupon),
      _PortfolioShadow(name: 'DIVERSIFICATA', picks: diversifiedCoupon),
    ];
  }

  void _logPortfolioShadow(List<_PortfolioShadow> portfolios) {
    if (portfolios.isEmpty) return;

    String pickKey(_CouponPick item) =>
        '${item.match.fixtureId}|${item.market.trim().toUpperCase()}';

    debugPrint('');
    debugPrint('========================================');
    debugPrint('GOALVDLINE PORTFOLIO ENGINE — P3A SHADOW');
    debugPrint('========================================');

    final union = <String>{};

    for (final portfolio in portfolios) {
      final keys = portfolio.picks.map(pickKey).toSet();
      union.addAll(keys);

      debugPrint('');
      debugPrint(
        '${portfolio.name} '
        '| ${portfolio.picks.length}/$_count eventi',
      );

      for (var index = 0; index < portfolio.picks.length; index++) {
        final item = portfolio.picks[index];

        debugPrint(
          '${index + 1}. '
          '${item.match.homeTeam} - ${item.match.awayTeam} '
          '| ${item.market} '
          '| P ${item.probability} '
          '| REL ${_portfolioReliability(item)} '
          '| EV ${item.expectedValue.toStringAsFixed(3)} '
          '| EDGE ${item.edge.toStringAsFixed(3)}',
        );
      }
    }

    debugPrint('');
    debugPrint('--- OVERLAP ---');

    for (var i = 0; i < portfolios.length; i++) {
      final a = portfolios[i];
      final aKeys = a.picks.map(pickKey).toSet();

      for (var j = i + 1; j < portfolios.length; j++) {
        final b = portfolios[j];
        final bKeys = b.picks.map(pickKey).toSet();

        final overlap = aKeys.intersection(bKeys).length;
        final denominator = math.min(aKeys.length, bKeys.length);

        debugPrint(
          '${a.name} ↔ ${b.name}: '
          '$overlap/$denominator',
        );
      }
    }

    final uniqueFixtures = portfolios
        .expand((portfolio) => portfolio.picks)
        .map((item) => item.match.fixtureId)
        .toSet();

    debugPrint('');
    debugPrint(
      'Selezioni uniche: ${union.length} | '
      'Partite uniche per Diego: ${uniqueFixtures.length}',
    );
    debugPrint('========================================');
  }

  void _logReliabilityRankingShadow(List<_CouponPick> source) {
    if (source.isEmpty) return;

    final currentRanking = List<_CouponPick>.of(source);

    currentRanking.sort((a, b) {
      final score = b.rankScore.compareTo(a.rankScore);
      if (score != 0) return score;

      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) return probability;

      return b.analysis.smartScore.compareTo(a.analysis.smartScore);
    });

    final reliabilityRanking = List<_CouponPick>.of(source);

    reliabilityRanking.sort(_reliabilityRankingCompare);

    // Simuliamo anche l'Auditor su ENTRAMBI i ranking.
    //
    // È solo diagnostica: non modifica qualified, feasible
    // né la schedina realmente generata.
    List<_CouponPick> auditedTop(List<_CouponPick> ranking) {
      final top = <_CouponPick>[];

      for (final item in ranking) {
        final audit = SmartBetLocalAuditor.evaluate(
          analysis: item.analysis,
          market: item.market,
          probability: item.probability,
          odd: item.odd ?? 0.0,
        );

        if (audit.isBlocked || audit.blocksMarket(item.market)) {
          continue;
        }

        top.add(item);

        if (top.length >= _count) {
          break;
        }
      }

      return top;
    }

    final currentTop = auditedTop(currentRanking);
    final reliabilityTop = auditedTop(reliabilityRanking);

    String keyOf(_CouponPick item) =>
        '${item.match.fixtureId}|${item.market.trim().toUpperCase()}';

    final currentIds = currentTop.map(keyOf).toSet();
    final reliabilityIds = reliabilityTop.map(keyOf).toSet();

    final overlap = currentIds.intersection(reliabilityIds).length;

    debugPrint('');
    debugPrint('========================================');
    debugPrint('SMARTBET RELIABILITY RANKING SHADOW');
    debugPrint('========================================');
    debugPrint(
      'Overlap POST-AUDITOR: $overlap/${currentTop.length} '
      '| candidate: ${source.length}',
    );

    debugPrint('');
    debugPrint('--- TOP ATTUALE ---');

    for (var index = 0; index < currentTop.length; index++) {
      final item = currentTop[index];

      debugPrint(
        '${index + 1}. ${item.match.homeTeam} - ${item.match.awayTeam} '
        '| ${item.market} '
        '| P ${item.probability} '
        '| REL ${item.reliabilityScore ?? -1} '
        '| OLD ${item.rankScore.toStringAsFixed(1)}',
      );
    }

    debugPrint('');
    debugPrint('--- TOP RELIABILITY ---');

    for (var index = 0; index < reliabilityTop.length; index++) {
      final item = reliabilityTop[index];

      debugPrint(
        '${index + 1}. ${item.match.homeTeam} - ${item.match.awayTeam} '
        '| ${item.market} '
        '| P ${item.probability} '
        '| REL ${item.reliabilityScore ?? -1} '
        '| OLD ${item.rankScore.toStringAsFixed(1)}',
      );
    }

    final entering = reliabilityTop
        .where((item) => !currentIds.contains(keyOf(item)))
        .toList();

    final leaving = currentTop
        .where((item) => !reliabilityIds.contains(keyOf(item)))
        .toList();

    debugPrint('');
    debugPrint('--- DIFFERENZE ---');

    if (entering.isEmpty && leaving.isEmpty) {
      debugPrint('Nessun cambio nelle partite selezionate.');
    } else {
      for (final item in entering) {
        debugPrint(
          'ENTRA: ${item.match.homeTeam} - ${item.match.awayTeam} '
          '| ${item.market} '
          '| P ${item.probability} '
          '| REL ${item.reliabilityScore ?? -1}',
        );
      }

      for (final item in leaving) {
        debugPrint(
          'ESCE: ${item.match.homeTeam} - ${item.match.awayTeam} '
          '| ${item.market} '
          '| P ${item.probability} '
          '| REL ${item.reliabilityScore ?? -1}',
        );
      }
    }

    debugPrint('========================================');
  }

  void _logReliabilityShadow(List<_CouponPick> selected) {
    if (selected.isEmpty) return;

    debugPrint('');
    debugPrint('========================================');
    debugPrint('SMARTBET RELIABILITY SHADOW');
    debugPrint('========================================');

    for (final item in selected) {
      debugPrint('');
      debugPrint(
        '${item.match.homeTeam} - ${item.match.awayTeam} '
        '| DATA ${item.analysis.dataConfidence} '
        '| PRED ${item.analysis.predictionConfidence}',
      );

      final candidates = _sportsMarketCandidates(item.analysis);

      for (final candidate in candidates.take(6)) {
        final reliability = SmartBetReliabilityService.score(
          analysis: item.analysis,
          market: candidate.market,
          probability: candidate.probability,
        );

        final marker = candidate.market == item.market ? ' ★ SELEZIONATO' : '';

        debugPrint(
          '${candidate.market.padRight(22)} '
          'P ${candidate.probability.toString().padLeft(3)} '
          'REL ${(reliability?.toString() ?? 'N/D').padLeft(3)}'
          '$marker',
        );
      }
    }

    debugPrint('');
    debugPrint('========================================');
  }

  List<_CouponPick> _liveSelectionSnapshot(List<_CouponPick> source) {
    final ranked = List<_CouponPick>.of(source);

    ranked.sort((a, b) {
      final score = b.rankScore.compareTo(a.rankScore);
      if (score != 0) return score;

      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) return probability;

      return b.analysis.smartScore.compareTo(a.analysis.smartScore);
    });

    final selected = ranked.take(_count).toList();
    selected.sort(_presentationCompare);
    return selected;
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

  String get _activeCouponName {
    if (_mode != _CouponMode.automatic || _portfolioResults.isEmpty) {
      return _profileName;
    }

    final safeIndex = _selectedPortfolioIndex.clamp(
      0,
      _portfolioResults.length - 1,
    );

    return _portfolioResults[safeIndex].name;
  }

  // ============================================================
  // CONDIVIDI
  // ============================================================

  Future<void> _share() async {
    if (_results.isEmpty) return;

    final text = StringBuffer()
      ..writeln('GOALVDLINE — SCHEDINA $_activeCouponName')
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
        subject: 'GoalVdLine — Schedina $_activeCouponName',
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

  Widget _portfolioSelector() {
    if (_mode != _CouponMode.automatic ||
        _portfolioResults.length <= 1 ||
        _loading) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PORTFOLIO GOALVDLINE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_portfolioResults.length, (index) {
              final portfolio = _portfolioResults[index];
              final selected = index == _selectedPortfolioIndex;

              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(portfolio.name),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: const Color(0xFF00C853),
                  backgroundColor: const Color(0xFF1F2937),
                  side: BorderSide(
                    color: selected ? const Color(0xFF00C853) : Colors.white12,
                  ),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (enabled) {
                    if (!enabled) return;

                    setState(() {
                      _selectedPortfolioIndex = index;

                      _results
                        ..clear()
                        ..addAll(portfolio.picks);
                    });
                  },
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _modeSelector() {
    Widget chip(_CouponMode mode, String label, IconData icon) {
      final selected = _mode == mode;

      return ChoiceChip(
        avatar: Icon(
          icon,
          size: 17,
          color: selected ? Colors.white : Colors.white54,
        ),
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
        ),
        onSelected: _loading
            ? null
            : (enabled) {
                if (!enabled) return;

                setState(() {
                  _mode = mode;
                  _results.clear();
                  _portfolioResults.clear();
                  _selectedPortfolioIndex = 0;
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
          'Modalità',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            chip(_CouponMode.automatic, 'AUTOMATICA', Icons.auto_awesome),
            chip(_CouponMode.manual, 'MANUALE', Icons.touch_app_outlined),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          _mode == _CouponMode.automatic
              ? 'GoalVdLine sceglie autonomamente le partite migliori.'
              : 'Scegli tu fino a 15 partite ufficiali. '
                    'SmartBet e DiegoAI le analizzano senza sostituirle.',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  String _manualMatchDate(MatchModel match) {
    final date = DateTime.tryParse(match.date)?.toLocal();

    if (date == null) {
      return match.league;
    }

    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute • ${match.league}';
  }

  List<MatchModel> _manualSelectedList() {
    final matches = _manualSelectedMatches.values.toList();

    matches.sort((a, b) {
      final dateA = DateTime.tryParse(a.date);
      final dateB = DateTime.tryParse(b.date);

      if (dateA != null && dateB != null) {
        return dateA.compareTo(dateB);
      }

      return a.homeTeam.compareTo(b.homeTeam);
    });

    return matches;
  }

  Future<List<MatchModel>> _manualAvailableMatches() async {
    final all = await _loadMatchesForSelectedPeriod();

    final matches = all
        .where(
          (match) =>
              match.fixtureId > 0 &&
              match.hasTeamIds &&
              _isUpcoming(match) &&
              (!_italyScheduleOnly || ItalyScheduleFilter.allows(match)) &&
              (_selectedCompetitionKeys.isEmpty ||
                  _selectedCompetitionKeys.contains(
                    CompetitionFilterSheet.keyFor(match),
                  )),
        )
        .toList();

    matches.sort((a, b) {
      final dateA = DateTime.tryParse(a.date);
      final dateB = DateTime.tryParse(b.date);

      if (dateA != null && dateB != null) {
        return dateA.compareTo(dateB);
      }

      return a.homeTeam.compareTo(b.homeTeam);
    });

    return matches;
  }

  Future<void> _openManualMatchSelector() async {
    if (_loading) return;

    List<MatchModel> matches;

    try {
      matches = await _manualAvailableMatches();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile caricare le partite disponibili.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessuna partita disponibile con i filtri attuali.'),
        ),
      );
      return;
    }

    var query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF111827),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setSheetState) {
            final normalized = query.trim().toLowerCase();

            final filtered = normalized.isEmpty
                ? matches
                : matches.where((match) {
                    final source =
                        '${match.homeTeam} '
                                '${match.awayTeam} '
                                '${match.league} '
                                '${match.country}'
                            .toLowerCase();

                    return source.contains(normalized);
                  }).toList();

            return SizedBox(
              height: MediaQuery.of(modalContext).size.height * 0.84,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Seleziona partite',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${_manualSelectedMatches.length}/15',
                          style: const TextStyle(
                            color: Color(0xFF00C853),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Cerca squadra o campionato',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white54,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1F2937),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Nessuna partita trovata',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final match = filtered[index];

                              final selected = _manualSelectedMatches
                                  .containsKey(match.fixtureId);

                              return CheckboxListTile(
                                value: selected,
                                activeColor: const Color(0xFF00C853),
                                checkColor: Colors.white,
                                title: Text(
                                  '${match.homeTeam} - ${match.awayTeam}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${match.country} • '
                                  '${_manualMatchDate(match)}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                onChanged: (_) {
                                  if (selected) {
                                    setState(() {
                                      _manualSelectedMatches.remove(
                                        match.fixtureId,
                                      );
                                      _results.clear();
                                      _portfolioResults.clear();
                                      _selectedPortfolioIndex = 0;
                                      _error = null;
                                      _notice = null;
                                    });

                                    setSheetState(() {});
                                    return;
                                  }

                                  if (_manualSelectedMatches.length >= 15) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Puoi selezionare al massimo 15 partite.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  setState(() {
                                    _manualSelectedMatches[match.fixtureId] =
                                        match;

                                    _results.clear();
                                    _portfolioResults.clear();
                                    _selectedPortfolioIndex = 0;
                                    _error = null;
                                    _notice = null;
                                  });

                                  setSheetState(() {});
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('FATTO'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _manualSelectionPanel() {
    final matches = _manualSelectedList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Partite scelte',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${matches.length}/15',
                style: const TextStyle(
                  color: Color(0xFF00C853),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'GoalVdLine analizzerà esattamente '
            'le partite che scegli.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _openManualMatchSelector,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('SELEZIONA PARTITE'),
            ),
          ),
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...matches.map(
              (match) => Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${match.homeTeam} - ${match.awayTeam}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _manualMatchDate(match),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _manualSelectedMatches.remove(match.fixtureId);

                                _results.clear();
                                _portfolioResults.clear();
                                _selectedPortfolioIndex = 0;
                                _error = null;
                                _notice = null;
                              });
                            },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
                  _selectedCompetitionKeys.clear();
                  _manualSelectedMatches.clear();
                  _results.clear();
                  _portfolioResults.clear();
                  _selectedPortfolioIndex = 0;
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

  Future<void> _openCompetitionFilter() async {
    try {
      final all = await _loadMatchesForSelectedPeriod();
      final available = all
          .where(
            (m) =>
                m.hasTeamIds &&
                _isUpcoming(m) &&
                (!_italyScheduleOnly || ItalyScheduleFilter.allows(m)),
          )
          .toList();

      if (!mounted) return;

      final selected = await CompetitionFilterSheet.show(
        context: context,
        matches: available,
        selectedKeys: _selectedCompetitionKeys,
      );

      if (selected == null || !mounted) return;

      setState(() {
        _selectedCompetitionKeys
          ..clear()
          ..addAll(selected);

        _manualSelectedMatches.clear();
        _results.clear();
        _portfolioResults.clear();
        _selectedPortfolioIndex = 0;
        _error = null;
        _notice = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile caricare i campionati disponibili.'),
        ),
      );
    }
  }

  Widget _competitionSelector() {
    final all = _selectedCompetitionKeys.isEmpty;

    final leagues =
        _selectedCompetitionKeys
            .map((key) {
              final parts = key.split('|||');
              return parts.length > 1 ? parts.last.trim() : key.trim();
            })
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final summary = all
        ? 'Nessun filtro: GoalVdLine usa tutti i campionati disponibili.'
        : leagues.length <= 3
        ? leagues.join(' • ')
        : '${leagues.take(3).join(' • ')} • +${leagues.length - 3}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CAMPIONATI',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          all
              ? 'Tutti i campionati'
              : '${leagues.length} campionati selezionati',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          summary,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _openCompetitionFilter,
            icon: const Icon(Icons.tune),
            label: Text(
              all ? 'SCEGLI CAMPIONATI' : 'MODIFICA CAMPIONATI',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00C853),
              side: const BorderSide(color: Color(0xFF00C853)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    if (!_loading) return const SizedBox.shrink();

    final advancedPhase =
        _phase == 'advanced' ||
        _phase == 'audit' ||
        _phase == 'odds' ||
        _phase == 'recovery';
    final current = advancedPhase ? _oddsProcessed : _processed;
    final total = advancedPhase ? _oddsTotal : _total;
    final value = total > 0
        ? (current / total).clamp(0.0, 1.0).toDouble()
        : null;

    String title;
    String subtitle;

    if (_phase == 'manual') {
      title = 'Analisi manuale: $current / $total';
      subtitle =
          'SmartBet + DiegoAI stanno analizzando '
          'soltanto le partite che hai selezionato.';
    } else if (_phase == 'advanced') {
      title = 'Analisi GoalVdLine: $current / $total';
      final remaining = math.max(0, total - current);
      subtitle = current == 0
          ? 'Avvio analisi avanzata delle candidate migliori…'
          : remaining > 0
          ? '$current candidate completate • $remaining ancora in analisi.'
          : 'Analisi GoalVdLine completata. Passaggio alle quote…';
    } else if (_phase == 'audit') {
      title = 'Controllo fattibilità: $current / $total';
      final remaining = math.max(0, total - current);
      subtitle = current == 0
          ? 'L’Auditor verifica solo le selezioni finali di GoalVdLine…'
          : remaining > 0
          ? '$current controllate • $remaining ancora da verificare.'
          : 'Controllo di fattibilità completato.';
    } else if (_phase == 'odds') {
      title =
          'Quote + selezione: $current / $total • ${_results.length} / $_count trovate';
      subtitle =
          'Le selezioni valide compaiono subito qui sotto mentre GoalVdLine continua.';
    } else if (_phase == 'recovery') {
      title =
          'Ricerca alternative: $current / $total • ${_results.length} / $_count trovate';
      subtitle =
          'GoalVdLine prova altre candidate senza abbassare quota minima o criteri di qualità.';
    } else {
      title = 'Scansione statistica: $current / $total';
      subtitle =
          'SmartCore sta confrontando le partite disponibili prima dell’analisi AI.';
    }

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
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
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
        title: const Text('Crea Schedina GoalVdLine'),
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
                  'LA MIA SCHEDINA GOALVDLINE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'GoalVdLine analizza il pool disponibile, seleziona le '
                  'giocate migliori e usa le quote reali solo nella fase finale.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _modeSelector(),

          const SizedBox(height: 22),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ANALISI GOALVDLINE COMPLETA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Un’unica analisi approfondita costruisce il pool migliore. '
                  'Da questo pool GoalVdLine creerà schedine coordinate senza '
                  'forzare eventi deboli.',
                  style: TextStyle(
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

          const SizedBox(height: 14),

          _competitionSelector(),

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
                        _manualSelectedMatches.clear();
                        _results.clear();
                        _portfolioResults.clear();
                        _selectedPortfolioIndex = 0;
                        _error = null;
                        _notice = null;
                      });
                    },
            ),
          ),

          const SizedBox(height: 22),

          if (_mode == _CouponMode.automatic) ...[
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [3, 5, 7, 10, 15].map((value) {
                final selected = _count == value;

                return ChoiceChip(
                  label: Text('$value'),
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
                  ),
                  onSelected: _loading
                      ? null
                      : (enabled) {
                          if (!enabled) return;

                          setState(() {
                            _count = value;
                            _results.clear();
                            _portfolioResults.clear();
                            _selectedPortfolioIndex = 0;
                            _error = null;
                            _notice = null;
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _loading ? null : _createCoupon,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _loading
                    ? 'ANALISI IN CORSO...'
                    : 'CREA LA MIA SCHEDINA GOALVDLINE',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF00C853),
              ),
            ),
          ] else ...[
            _manualSelectionPanel(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading || _manualSelectedMatches.isEmpty
                    ? null
                    : _analyzeManualCoupon,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(
                  _loading
                      ? 'ANALISI IN CORSO...'
                      : 'ANALIZZA '
                            '${_manualSelectedMatches.length} '
                            'PARTITE',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF00C853),
                ),
              ),
            ),
          ],

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
              _loading
                  ? 'Selezioni provvisorie • '
                        '${_results.length}/'
                        '${_mode == _CouponMode.manual ? _manualSelectedMatches.length : _count}'
                  : _mode == _CouponMode.manual
                  ? 'Analisi manuale'
                  : 'Schedina $_activeCouponName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 6),
              const Text(
                'GoalVdLine sta ancora lavorando: le selezioni possono aggiornarsi fino al completamento.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
            if (_mode == _CouponMode.automatic &&
                _portfolioResults.length > 1 &&
                !_loading) ...[
              const SizedBox(height: 12),
              _portfolioSelector(),
            ],
            const SizedBox(height: 12),
            _summary(),
            const SizedBox(height: 15),
            ..._groupedResultWidgets(),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _loading ? null : _share,
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
            'calcolo probabilistico per costruire il portfolio delle schedine.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedResultWidgets() {
    final widgets = <Widget>[];
    String? currentGroup;
    var position = 0;

    for (final item in _results) {
      final country = item.match.country.trim().isEmpty
          ? 'Internazionale'
          : item.match.country.trim();
      final league = item.match.league.trim().isEmpty
          ? 'Competizione'
          : item.match.league.trim();
      final group = '$country • $league';

      if (group != currentGroup) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 6));
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 9),
            child: Text(
              group,
              style: const TextStyle(
                color: Color(0xFF00C853),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        currentGroup = group;
      }

      position++;
      widgets.add(_resultCard(item, position));
    }

    return widgets;
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
                      'SCELTA GOALVDLINE',
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
          if (item.dualAnalysis != null) ...[
            const SizedBox(height: 12),
            DualEngineSummary(analysis: item.dualAnalysis!),
          ],

          TeamStatsExpansion(match: item.match),

          const SizedBox(height: 10),
          Text(
            'Smart Score: ${item.analysis.smartScore}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Auditor: ${item.auditorStatus}',
            style: TextStyle(
              color: item.auditorStatus == 'SCONSIGLIATA'
                  ? Colors.redAccent
                  : item.auditorStatus == 'CON RISERVA'
                  ? Colors.orangeAccent
                  : item.auditorStatus == 'CONFERMATA'
                  ? const Color(0xFF00C853)
                  : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
