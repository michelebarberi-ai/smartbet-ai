import 'dart:math' as math;

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'smartbet_ai_service.dart';

// ============================================================
// SINGOLA SELEZIONE DELLA SCHEDINA
// ============================================================

class SmartBetCouponSelection {
  final MatchModel match;
  final AnalysisResult analysis;

  const SmartBetCouponSelection({required this.match, required this.analysis});

  String get matchLabel {
    return '${match.homeTeam} - ${match.awayTeam}';
  }

  String get outcome {
    return analysis.stakeOutcome;
  }

  double get odd {
    return analysis.stakeOdd;
  }

  String get bookmaker {
    return analysis.stakeBookmaker;
  }

  int get smartScore {
    return analysis.smartScore;
  }

  String get risk {
    return analysis.risk;
  }

  double get stakePercent {
    return analysis.recommendedStakePercent;
  }
}

// ============================================================
// RISULTATO FINALE SCHEDINA
// ============================================================

class SmartBetCouponResult {
  final List<SmartBetCouponSelection> selections;

  final int analyzedMatches;
  final int validCandidates;
  final int rejectedMatches;

  final double totalOdd;

  // Qualità media delle selezioni.
  // NON è la probabilità della multipla.
  final double averageSmartScore;

  // Probabilità congiunta stimata degli esiti selezionati.
  final double estimatedCombinedProbability;

  final String riskLevel;

  final double recommendedStakePercent;

  final String message;

  const SmartBetCouponResult({
    required this.selections,
    required this.analyzedMatches,
    required this.validCandidates,
    required this.rejectedMatches,
    required this.totalOdd,
    required this.averageSmartScore,
    required this.estimatedCombinedProbability,
    required this.riskLevel,
    required this.recommendedStakePercent,
    required this.message,
  });

  bool get hasCoupon {
    return selections.length >= 2;
  }

  int get selectionCount {
    return selections.length;
  }
}

// ============================================================
// PROFILO ADATTIVO
// ============================================================

class _CouponProfile {
  final String name;

  final int minimumSmartScore;

  final double minimumAiProbability;

  final double minimumEdge;

  final double maximumOdd;

  final double highOddThreshold;

  final int highOddMinimumSmartScore;

  final double highOddMinimumProbability;

  final double highOddMinimumEdge;

  final bool rejectHighRisk;

  const _CouponProfile({
    required this.name,
    required this.minimumSmartScore,
    required this.minimumAiProbability,
    required this.minimumEdge,
    required this.maximumOdd,
    required this.highOddThreshold,
    required this.highOddMinimumSmartScore,
    required this.highOddMinimumProbability,
    required this.highOddMinimumEdge,
    required this.rejectHighRisk,
  });
}

// ============================================================
// CANDIDATO
// ============================================================

class _CouponCandidate {
  final SmartBetCouponSelection selection;

  final double aiProbability;

  final double impliedProbability;

  final double edge;

  final double qualityScore;

  const _CouponCandidate({
    required this.selection,
    required this.aiProbability,
    required this.impliedProbability,
    required this.edge,
    required this.qualityScore,
  });
}

// ============================================================
// SERVIZIO SCHEDINA SMARTBET
// ============================================================

class SmartBetCouponService {
  static const int maximumSelections = 6;

  static const int minimumSelections = 2;

  static const double minimumOdd = 1.18;

  static const double maximumCouponStakePercent = 0.50;

  // ============================================================
  // PROFILI
  // ============================================================

  // Primo tentativo:
  // alta qualità, quote relativamente prudenti.
  static const _CouponProfile _premiumProfile = _CouponProfile(
    name: 'PREMIUM',
    minimumSmartScore: 72,
    minimumAiProbability: 0.38,
    minimumEdge: 0.035,
    maximumOdd: 3.80,
    highOddThreshold: 3.20,
    highOddMinimumSmartScore: 78,
    highOddMinimumProbability: 0.40,
    highOddMinimumEdge: 0.050,
    rejectHighRisk: true,
  );

  // Secondo tentativo:
  // buon compromesso affidabilità/value.
  static const _CouponProfile _balancedProfile = _CouponProfile(
    name: 'BILANCIATO',
    minimumSmartScore: 65,
    minimumAiProbability: 0.29,
    minimumEdge: 0.020,
    maximumOdd: 5.25,
    highOddThreshold: 3.80,
    highOddMinimumSmartScore: 72,
    highOddMinimumProbability: 0.31,
    highOddMinimumEdge: 0.035,
    rejectHighRisk: false,
  );

  // Ultimo tentativo:
  // accetta value più aggressive,
  // ma mantiene un limite assoluto.
  static const _CouponProfile _controlledValueProfile = _CouponProfile(
    name: 'VALUE CONTROLLATO',
    minimumSmartScore: 62,
    minimumAiProbability: 0.25,
    minimumEdge: 0.015,
    maximumOdd: 7.50,
    highOddThreshold: 4.25,
    highOddMinimumSmartScore: 70,
    highOddMinimumProbability: 0.29,
    highOddMinimumEdge: 0.030,
    rejectHighRisk: true,
  );

  static const List<_CouponProfile> _profiles = [
    _premiumProfile,
    _balancedProfile,
    _controlledValueProfile,
  ];

  // ============================================================
  // CREA SCHEDINA
  // ============================================================

  Future<SmartBetCouponResult> buildCoupon({
    required List<MatchModel> matches,
  }) async {
    if (matches.isEmpty) {
      return _emptyResult(message: 'Nessuna partita selezionata.');
    }

    final aiService = SmartBetAiService();

    final analyzed = <SmartBetCouponSelection>[];

    int analyzedMatches = 0;

    try {
      // ========================================================
      // UNA SOLA ANALISI AI PER PARTITA
      // ========================================================

      for (final match in matches) {
        final result = await aiService.analyzeMatch(match);

        analyzedMatches++;

        if (!_isBaseValid(result)) {
          continue;
        }

        analyzed.add(SmartBetCouponSelection(match: match, analysis: result));

        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      aiService.dispose();
    }

    if (analyzed.isEmpty) {
      return SmartBetCouponResult(
        selections: const [],
        analyzedMatches: analyzedMatches,
        validCandidates: 0,
        rejectedMatches: analyzedMatches,
        totalOdd: 0.0,
        averageSmartScore: 0.0,
        estimatedCombinedProbability: 0.0,
        riskLevel: 'Non disponibile',
        recommendedStakePercent: 0.0,
        message:
            'Nessuna partita supera i controlli '
            'base di SmartBet.',
      );
    }

    // ==========================================================
    // PROFILO ADATTIVO
    // ==========================================================

    _CouponProfile? selectedProfile;

    List<_CouponCandidate> candidates = [];

    for (final profile in _profiles) {
      final current = analyzed
          .map(
            (selection) =>
                _buildCandidate(selection: selection, profile: profile),
          )
          .whereType<_CouponCandidate>()
          .toList();

      _sortCandidates(current);

      // Appena troviamo almeno 2 candidate
      // sufficientemente valide, ci fermiamo.
      //
      // Non forziamo 5-6 eventi abbassando
      // ancora la qualità.
      if (current.length >= minimumSelections) {
        selectedProfile = profile;
        candidates = current;
        break;
      }
    }

    // ==========================================================
    // NESSUN PROFILO TROVA ALMENO 2 EVENTI
    // ==========================================================

    if (selectedProfile == null) {
      return SmartBetCouponResult(
        selections: const [],
        analyzedMatches: analyzedMatches,
        validCandidates: 0,
        rejectedMatches: analyzedMatches,
        totalOdd: 0.0,
        averageSmartScore: 0.0,
        estimatedCombinedProbability: 0.0,
        riskLevel: 'Non disponibile',
        recommendedStakePercent: 0.0,
        message:
            'Oggi SmartBet non trova almeno due '
            'selezioni con un rapporto '
            'affidabilità/rendimento sufficiente.',
      );
    }

    // ==========================================================
    // SELEZIONI FINALI
    // ==========================================================

    final selections = candidates
        .take(maximumSelections)
        .map((item) => item.selection)
        .toList();

    final totalOdd = _calculateTotalOdd(selections);

    final averageSmartScore = _calculateAverageSmartScore(selections);

    final combinedProbability = _calculateCombinedProbability(selections);

    final riskLevel = _calculateCouponRisk(
      selections: selections,
      combinedProbability: combinedProbability,
    );

    final stakePercent = _calculateCouponStake(
      selections: selections,
      combinedProbability: combinedProbability,
    );

    return SmartBetCouponResult(
      selections: selections,
      analyzedMatches: analyzedMatches,
      validCandidates: candidates.length,
      rejectedMatches: analyzedMatches - candidates.length,
      totalOdd: totalOdd,
      averageSmartScore: averageSmartScore,
      estimatedCombinedProbability: combinedProbability,
      riskLevel: riskLevel,
      recommendedStakePercent: stakePercent,
      message:
          'Profilo ${selectedProfile.name}: '
          '${selections.length} selezioni '
          'scelte per equilibrio tra '
          'affidabilità, probabilità e value.',
    );
  }

  // ============================================================
  // VALIDAZIONE BASE
  // ============================================================

  bool _isBaseValid(AnalysisResult result) {
    if (result.smartScore <= 0) {
      return false;
    }

    if (!result.shouldBet) {
      return false;
    }

    if (result.stakeOutcome.trim().isEmpty) {
      return false;
    }

    if (result.stakeOdd < minimumOdd) {
      return false;
    }

    return true;
  }

  // ============================================================
  // CREA CANDIDATO PER PROFILO
  // ============================================================

  _CouponCandidate? _buildCandidate({
    required SmartBetCouponSelection selection,
    required _CouponProfile profile,
  }) {
    final result = selection.analysis;

    if (result.smartScore < profile.minimumSmartScore) {
      return null;
    }

    final odd = selection.odd;

    if (odd < minimumOdd || odd > profile.maximumOdd) {
      return null;
    }

    final probability = _selectionProbability(selection);

    if (probability < profile.minimumAiProbability) {
      return null;
    }

    final impliedProbability = 1.0 / odd;

    final edge = probability - impliedProbability;

    if (edge < profile.minimumEdge) {
      return null;
    }

    // ==========================================================
    // QUOTA ALTA
    // ==========================================================

    if (odd >= profile.highOddThreshold) {
      if (result.smartScore < profile.highOddMinimumSmartScore) {
        return null;
      }

      if (probability < profile.highOddMinimumProbability) {
        return null;
      }

      if (edge < profile.highOddMinimumEdge) {
        return null;
      }

      if (_isHighRisk(result.risk)) {
        return null;
      }
    }

    if (profile.rejectHighRisk && _isHighRisk(result.risk)) {
      return null;
    }

    final qualityScore = _calculateQualityScore(
      selection: selection,
      probability: probability,
      edge: edge,
      profile: profile,
    );

    return _CouponCandidate(
      selection: selection,
      aiProbability: probability,
      impliedProbability: impliedProbability,
      edge: edge,
      qualityScore: qualityScore,
    );
  }

  // ============================================================
  // ORDINA CANDIDATI
  // ============================================================

  void _sortCandidates(List<_CouponCandidate> items) {
    items.sort((a, b) {
      final qualityComparison = b.qualityScore.compareTo(a.qualityScore);

      if (qualityComparison != 0) {
        return qualityComparison;
      }

      final probabilityComparison = b.aiProbability.compareTo(a.aiProbability);

      if (probabilityComparison != 0) {
        return probabilityComparison;
      }

      return a.selection.odd.compareTo(b.selection.odd);
    });
  }

  // ============================================================
  // QUALITY SCORE
  // ============================================================

  double _calculateQualityScore({
    required SmartBetCouponSelection selection,
    required double probability,
    required double edge,
    required _CouponProfile profile,
  }) {
    final scoreComponent = (selection.smartScore / 100.0).clamp(0.0, 1.0);

    final probabilityComponent = probability.clamp(0.0, 1.0);

    // Edge massimo considerato ai fini del ranking:
    // 15 punti percentuali.
    //
    // Edge enormi non devono far dominare
    // automaticamente una quota molto alta.
    final edgeComponent = (edge / 0.15).clamp(0.0, 1.0);

    final riskComponent = _riskQuality(selection.risk);

    final oddComponent = _oddQuality(selection.odd, profile);

    final stakeComponent = (selection.stakePercent / 2.0).clamp(0.0, 1.0);

    // ==========================================================
    // PESI
    // ==========================================================
    //
    // Smart Score      30%
    // Probabilità AI   30%
    // Edge             15%
    // Rischio          12%
    // Qualità quota     8%
    // Stake             5%
    // ==========================================================

    final score =
        (scoreComponent * 0.30) +
        (probabilityComponent * 0.30) +
        (edgeComponent * 0.15) +
        (riskComponent * 0.12) +
        (oddComponent * 0.08) +
        (stakeComponent * 0.05);

    return score * 100.0;
  }

  // ============================================================
  // QUALITÀ QUOTA
  // ============================================================

  double _oddQuality(double odd, _CouponProfile profile) {
    if (odd <= 1.80) {
      return 1.00;
    }

    if (odd <= 2.40) {
      return 0.95;
    }

    if (odd <= 3.00) {
      return 0.85;
    }

    if (odd <= 3.80) {
      return 0.68;
    }

    if (odd <= 4.75) {
      return 0.48;
    }

    if (odd <= 6.00) {
      return 0.30;
    }

    if (odd <= profile.maximumOdd) {
      return 0.16;
    }

    return 0.0;
  }

  // ============================================================
  // QUALITÀ RISCHIO
  // ============================================================

  double _riskQuality(String risk) {
    final value = risk.toLowerCase().trim();

    if (value.contains('molto basso')) {
      return 1.00;
    }

    if (value == 'basso' || value == 'low') {
      return 0.90;
    }

    if (value == 'medio' || value == 'medium') {
      return 0.68;
    }

    if (value.contains('medio-alto') || value.contains('medium-high')) {
      return 0.40;
    }

    if (value == 'alto' || value == 'high') {
      return 0.15;
    }

    return 0.50;
  }

  bool _isHighRisk(String risk) {
    final value = risk.toLowerCase().trim();

    return value == 'alto' ||
        value == 'high' ||
        value.contains('molto alto') ||
        value.contains('very high');
  }

  // ============================================================
  // PROBABILITÀ SINGOLO ESITO
  // ============================================================

  double _selectionProbability(SmartBetCouponSelection selection) {
    final outcome = selection.outcome.trim().toUpperCase();

    int probability;

    switch (outcome) {
      case '1':
        probability = selection.analysis.homeProbability;
        break;

      case 'X':
        probability = selection.analysis.drawProbability;
        break;

      case '2':
        probability = selection.analysis.awayProbability;
        break;

      default:
        return 0.0;
    }

    return probability.clamp(0, 100) / 100.0;
  }

  // ============================================================
  // QUOTA TOTALE
  // ============================================================

  double _calculateTotalOdd(List<SmartBetCouponSelection> selections) {
    if (selections.isEmpty) {
      return 0.0;
    }

    double total = 1.0;

    for (final selection in selections) {
      total *= selection.odd;
    }

    return total;
  }

  // ============================================================
  // SMART SCORE MEDIO
  // ============================================================

  double _calculateAverageSmartScore(List<SmartBetCouponSelection> selections) {
    if (selections.isEmpty) {
      return 0.0;
    }

    final total = selections.fold<int>(0, (sum, item) => sum + item.smartScore);

    return total / selections.length;
  }

  // ============================================================
  // PROBABILITÀ CONGIUNTA
  // ============================================================

  double _calculateCombinedProbability(
    List<SmartBetCouponSelection> selections,
  ) {
    if (selections.isEmpty) {
      return 0.0;
    }

    double probability = 1.0;

    for (final selection in selections) {
      final singleProbability = _selectionProbability(selection);

      if (singleProbability <= 0.0) {
        return 0.0;
      }

      probability *= singleProbability;
    }

    return probability.clamp(0.0, 1.0);
  }

  // ============================================================
  // RISCHIO COMPLESSIVO
  // ============================================================

  String _calculateCouponRisk({
    required List<SmartBetCouponSelection> selections,
    required double combinedProbability,
  }) {
    if (selections.length >= 6) {
      return 'Alto';
    }

    final maximumOdd = selections.map((item) => item.odd).reduce(math.max);

    if (combinedProbability < 0.10) {
      return 'Alto';
    }

    if (combinedProbability < 0.18) {
      return 'Medio-Alto';
    }

    if (maximumOdd >= 5.00 && combinedProbability < 0.28) {
      return 'Medio-Alto';
    }

    if (combinedProbability < 0.32) {
      return 'Medio';
    }

    return 'Contenuto';
  }

  // ============================================================
  // STAKE SCHEDINA
  // ============================================================

  double _calculateCouponStake({
    required List<SmartBetCouponSelection> selections,
    required double combinedProbability,
  }) {
    if (selections.length < minimumSelections) {
      return 0.0;
    }

    if (combinedProbability <= 0.0) {
      return 0.0;
    }

    double minimumSingleStake = selections.first.stakePercent;

    for (final selection in selections.skip(1)) {
      minimumSingleStake = math.min(minimumSingleStake, selection.stakePercent);
    }

    double multiplier;

    if (selections.length <= 2) {
      multiplier = 0.50;
    } else if (selections.length == 3) {
      multiplier = 0.40;
    } else if (selections.length == 4) {
      multiplier = 0.30;
    } else {
      multiplier = 0.25;
    }

    if (combinedProbability < 0.10) {
      multiplier *= 0.50;
    } else if (combinedProbability < 0.20) {
      multiplier *= 0.70;
    } else if (combinedProbability < 0.30) {
      multiplier *= 0.85;
    }

    final hasAggressiveOdd = selections.any(
      (selection) => selection.odd >= 4.50,
    );

    if (hasAggressiveOdd) {
      multiplier *= 0.80;
    }

    var stake = minimumSingleStake * multiplier;

    stake = math.min(stake, maximumCouponStakePercent);

    if (stake < 0.05) {
      return 0.0;
    }

    return stake;
  }

  // ============================================================
  // RISULTATO VUOTO
  // ============================================================

  SmartBetCouponResult _emptyResult({required String message}) {
    return SmartBetCouponResult(
      selections: const [],
      analyzedMatches: 0,
      validCandidates: 0,
      rejectedMatches: 0,
      totalOdd: 0.0,
      averageSmartScore: 0.0,
      estimatedCombinedProbability: 0.0,
      riskLevel: 'Non disponibile',
      recommendedStakePercent: 0.0,
      message: message,
    );
  }
}
