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

  final String profileName;

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
    this.profileName = 'SMART',
  });

  bool get hasCoupon {
    return selections.isNotEmpty;
  }

  int get selectionCount {
    return selections.length;
  }
}

// ============================================================
// TRE STRATEGIE SCHEDINA
// ============================================================

class SmartBetCouponSet {
  final SmartBetCouponResult premium;
  final SmartBetCouponResult balanced;
  final SmartBetCouponResult value;

  const SmartBetCouponSet({
    required this.premium,
    required this.balanced,
    required this.value,
  });

  bool get hasAnyCoupon {
    return premium.hasCoupon || balanced.hasCoupon || value.hasCoupon;
  }

  SmartBetCouponResult get preferred {
    if (premium.hasCoupon) {
      return premium;
    }

    if (balanced.hasCoupon) {
      return balanced;
    }

    return value;
  }

  int get availableProfiles {
    var count = 0;

    if (premium.hasCoupon) {
      count++;
    }

    if (balanced.hasCoupon) {
      count++;
    }

    if (value.hasCoupon) {
      count++;
    }

    return count;
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

  // Analisi AI avanzata controllata:
  // massimo 2 partite contemporaneamente.
  static const int advancedBatchSize = 2;

  static const double minimumOdd = 1.18;

  static const double maximumCouponStakePercent = 0.50;

  // ============================================================
  // PROFILI
  // ============================================================

  // Primo tentativo:
  // alta qualità, quote relativamente prudenti.
  static const _CouponProfile _premiumProfile = _CouponProfile(
    name: 'PREMIUM',
    minimumSmartScore: 68,
    minimumAiProbability: 0.34,
    minimumEdge: 0.025,
    maximumOdd: 4.20,
    highOddThreshold: 3.40,
    highOddMinimumSmartScore: 72,
    highOddMinimumProbability: 0.36,
    highOddMinimumEdge: 0.030,
    rejectHighRisk: true,
  );

  // Secondo tentativo:
  // buon compromesso affidabilità/value.
  static const _CouponProfile _balancedProfile = _CouponProfile(
    name: 'BILANCIATA',
    minimumSmartScore: 62,
    minimumAiProbability: 0.27,
    minimumEdge: 0.012,
    maximumOdd: 5.75,
    highOddThreshold: 4.00,
    highOddMinimumSmartScore: 68,
    highOddMinimumProbability: 0.29,
    highOddMinimumEdge: 0.020,
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

  // Profili adattivi: entrano in gioco solo quando il profilo
  // principale non riesce a produrre una schedina.
  //
  // L'obiettivo è mostrare davvero tre strategie differenti,
  // senza trasformare "Premium" in una soglia irraggiungibile
  // nelle giornate con poche Value Bet.
  static const _CouponProfile _premiumAdaptiveProfile = _CouponProfile(
    name: 'PREMIUM',
    minimumSmartScore: 60,
    minimumAiProbability: 0.28,
    minimumEdge: 0.008,
    maximumOdd: 4.50,
    highOddThreshold: 3.60,
    highOddMinimumSmartScore: 64,
    highOddMinimumProbability: 0.30,
    highOddMinimumEdge: 0.012,
    rejectHighRisk: true,
  );

  static const _CouponProfile _balancedAdaptiveProfile = _CouponProfile(
    name: 'BILANCIATA',
    minimumSmartScore: 58,
    minimumAiProbability: 0.24,
    minimumEdge: 0.005,
    maximumOdd: 6.25,
    highOddThreshold: 4.25,
    highOddMinimumSmartScore: 62,
    highOddMinimumProbability: 0.26,
    highOddMinimumEdge: 0.008,
    rejectHighRisk: false,
  );

  // Fallback usato SOLTANTO se i tre profili principali
  // non riescono a costruire una schedina.
  //
  // Non crea nuove giocate: lavora esclusivamente su risultati
  // che hanno già superato Value Bet + Stake Engine
  // (shouldBet == true e stake valido).
  static const int _smartFallbackMinimumScore = 58;
  static const double _smartFallbackMinimumProbability = 0.24;
  static const double _smartFallbackMaximumOdd = 6.50;

  // ============================================================
  // CREA SCHEDINA
  // ============================================================

  Future<SmartBetCouponResult> buildCoupon({
    required List<MatchModel> matches,
  }) async {
    final set = await buildCouponSet(
      matches: matches,
      minimumRequired: minimumSelections,
    );

    return set.preferred;
  }

  // ============================================================
  // CREA LE TRE SCHEDINE CON UNA SOLA ANALISI AI
  // ============================================================

  Future<SmartBetCouponSet> buildCouponSet({
    required List<MatchModel> matches,
    int minimumRequired = minimumSelections,
  }) async {
    final safeMinimum = minimumRequired.clamp(1, minimumSelections);

    if (matches.isEmpty) {
      final emptyPremium = _emptyResult(
        message: 'Nessuna partita selezionata.',
        profileName: 'PREMIUM',
      );

      final emptyBalanced = _emptyResult(
        message: 'Nessuna partita selezionata.',
        profileName: 'BILANCIATA',
      );

      final emptyValue = _emptyResult(
        message: 'Nessuna partita selezionata.',
        profileName: 'VALUE',
      );

      return SmartBetCouponSet(
        premium: emptyPremium,
        balanced: emptyBalanced,
        value: emptyValue,
      );
    }

    final aiService = SmartBetAiService();

    final analyzed = <SmartBetCouponSelection>[];

    int analyzedMatches = 0;

    try {
      // ========================================================
      // ANALISI AI AVANZATA A COPPIE
      // ========================================================
      //
      // Ogni partita viene analizzata UNA SOLA VOLTA.
      // Gli stessi risultati vengono poi riutilizzati per
      // Premium, Bilanciata e Value.
      // ========================================================

      for (int start = 0; start < matches.length; start += advancedBatchSize) {
        final end = (start + advancedBatchSize) < matches.length
            ? start + advancedBatchSize
            : matches.length;

        final batch = matches.sublist(start, end);

        final results = await Future.wait(batch.map(aiService.analyzeMatch));

        for (int i = 0; i < results.length; i++) {
          final match = batch[i];
          final result = results[i];

          analyzedMatches++;

          if (!_isBaseValid(result)) {
            continue;
          }

          analyzed.add(SmartBetCouponSelection(match: match, analysis: result));
        }

        if (end < matches.length) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      aiService.dispose();
    }

    if (analyzed.isEmpty) {
      final commonMessage =
          'Nessuna partita ha superato Value Bet e Stake Engine. '
          'Prova ad aggiungere altre partite alla selezione.';

      return SmartBetCouponSet(
        premium: _emptyResult(
          message: commonMessage,
          profileName: 'PREMIUM',
          analyzedMatches: analyzedMatches,
        ),
        balanced: _emptyResult(
          message: commonMessage,
          profileName: 'BILANCIATA',
          analyzedMatches: analyzedMatches,
        ),
        value: _emptyResult(
          message: commonMessage,
          profileName: 'VALUE',
          analyzedMatches: analyzedMatches,
        ),
      );
    }

    final manualMode = safeMinimum == 1;

    // Ogni strategia ha un numero minimo diverso.
    //
    // Automatico:
    // PREMIUM   -> almeno 2
    // BILANCIATA -> almeno 3
    // VALUE      -> almeno 3
    //
    // Manuale:
    // consentiamo anche una singola giocata realmente valida,
    // perché l'utente può aver selezionato poche partite.
    final premiumMinimum = manualMode ? 1 : 2;
    final balancedMinimum = manualMode ? 1 : 3;
    final valueMinimum = manualMode ? 1 : 3;

    final premium = _buildProfileResult(
      analyzed: analyzed,
      analyzedMatches: analyzedMatches,
      profile: _premiumProfile,
      adaptiveProfile: _premiumAdaptiveProfile,
      maximumProfileSelections: 2,
      minimumRequired: premiumMinimum,
      allowSmartFallback: false,
      strategy: 'PREMIUM',
    );

    final balanced = _buildProfileResult(
      analyzed: analyzed,
      analyzedMatches: analyzedMatches,
      profile: _balancedProfile,
      adaptiveProfile: _balancedAdaptiveProfile,
      maximumProfileSelections: 4,
      minimumRequired: balancedMinimum,
      allowSmartFallback: false,
      strategy: 'BILANCIATA',
    );

    final value = _buildProfileResult(
      analyzed: analyzed,
      analyzedMatches: analyzedMatches,
      profile: _controlledValueProfile,
      maximumProfileSelections: maximumSelections,
      minimumRequired: valueMinimum,
      allowSmartFallback: true,
      strategy: 'VALUE',
    );

    return SmartBetCouponSet(
      premium: premium,
      balanced: balanced,
      value: value,
    );
  }

  // ============================================================
  // COSTRUISCE UNA STRATEGIA DA RISULTATI GIÀ ANALIZZATI
  // ============================================================

  SmartBetCouponResult _buildProfileResult({
    required List<SmartBetCouponSelection> analyzed,
    required int analyzedMatches,
    required _CouponProfile profile,
    _CouponProfile? adaptiveProfile,
    required int maximumProfileSelections,
    required int minimumRequired,
    required bool allowSmartFallback,
    required String strategy,
  }) {
    var candidates = analyzed
        .map(
          (selection) =>
              _buildCandidate(selection: selection, profile: profile),
        )
        .whereType<_CouponCandidate>()
        .toList();

    _sortCandidatesForStrategy(candidates, strategy);

    var usedFallback = false;
    var usedAdaptiveProfile = false;

    if (candidates.length < minimumRequired && adaptiveProfile != null) {
      final adaptiveCandidates = analyzed
          .map(
            (selection) =>
                _buildCandidate(selection: selection, profile: adaptiveProfile),
          )
          .whereType<_CouponCandidate>()
          .toList();

      _sortCandidatesForStrategy(adaptiveCandidates, strategy);

      if (adaptiveCandidates.length >= minimumRequired) {
        candidates = adaptiveCandidates;
        usedAdaptiveProfile = true;
      }
    }

    if (candidates.length < minimumRequired && allowSmartFallback) {
      final fallback = analyzed
          .map(_buildSmartFallbackCandidate)
          .whereType<_CouponCandidate>()
          .toList();

      _sortCandidatesForStrategy(fallback, strategy);

      // Evitiamo duplicati qualora una candidata sia già presente.
      final knownFixtures = candidates
          .map((item) => item.selection.match.fixtureId)
          .toSet();

      for (final item in fallback) {
        if (knownFixtures.add(item.selection.match.fixtureId)) {
          candidates.add(item);
        }
      }

      _sortCandidatesForStrategy(candidates, strategy);
      usedFallback = true;
    }

    if (candidates.length < minimumRequired) {
      return SmartBetCouponResult(
        selections: const [],
        analyzedMatches: analyzedMatches,
        validCandidates: candidates.length,
        rejectedMatches: analyzedMatches - candidates.length,
        totalOdd: 0.0,
        averageSmartScore: 0.0,
        estimatedCombinedProbability: 0.0,
        riskLevel: 'Non disponibile',
        recommendedStakePercent: 0.0,
        profileName: profile.name == 'VALUE CONTROLLATO'
            ? 'VALUE'
            : profile.name,
        message:
            '${profile.name}: non ci sono abbastanza selezioni '
            'con qualità sufficiente. '
            'SmartBet non forza eventi deboli.',
      );
    }

    final selections = candidates
        .take(maximumProfileSelections)
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

    final profileName = profile.name == 'VALUE CONTROLLATO'
        ? 'VALUE'
        : profile.name;

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
      profileName: profileName,
      message: usedFallback
          ? '$profileName: selezioni validate con fallback SMART '
                'dopo i controlli Value Bet e Stake Engine.'
          : usedAdaptiveProfile
          ? '$profileName: profilo adattivo attivato per usare '
                'le migliori opportunità disponibili oggi.'
          : '$profileName: ${selections.length} selezioni scelte '
                'secondo i criteri specifici del profilo.',
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
  // FALLBACK SMART
  // ============================================================

  _CouponCandidate? _buildSmartFallbackCandidate(
    SmartBetCouponSelection selection,
  ) {
    final result = selection.analysis;

    // Il risultato deve essere già stato approvato dallo Stake Engine.
    if (!result.shouldBet) {
      return null;
    }

    if (selection.outcome.trim().isEmpty) {
      return null;
    }

    final odd = selection.odd;

    if (odd < minimumOdd || odd > _smartFallbackMaximumOdd) {
      return null;
    }

    if (result.smartScore < _smartFallbackMinimumScore) {
      return null;
    }

    final probability = _selectionProbability(selection);

    if (probability < _smartFallbackMinimumProbability) {
      return null;
    }

    // Rischio alto ammesso soltanto con score molto forte.
    if (_isHighRisk(result.risk) && result.smartScore < 72) {
      return null;
    }

    final impliedProbability = 1.0 / odd;
    final edge = probability - impliedProbability;

    // Nel fallback NON imponiamo una seconda soglia edge:
    // il ValueBetCalculator e lo StakeEngine hanno già deciso
    // che la giocata possiede valore sufficiente.
    final scoreComponent = (result.smartScore / 100.0).clamp(0.0, 1.0);
    final probabilityComponent = probability.clamp(0.0, 1.0);
    final riskComponent = _riskQuality(result.risk);
    final stakeComponent = (selection.stakePercent / 2.0).clamp(0.0, 1.0);

    final oddComponent = odd <= 1.80
        ? 1.00
        : odd <= 2.40
        ? 0.92
        : odd <= 3.20
        ? 0.78
        : odd <= 4.50
        ? 0.58
        : 0.35;

    final qualityScore =
        ((scoreComponent * 0.34) +
            (probabilityComponent * 0.30) +
            (riskComponent * 0.16) +
            (oddComponent * 0.10) +
            (stakeComponent * 0.10)) *
        100.0;

    return _CouponCandidate(
      selection: selection,
      aiProbability: probability,
      impliedProbability: impliedProbability,
      edge: edge,
      qualityScore: qualityScore,
    );
  }

  // ============================================================
  // ORDINA CANDIDATI PER STRATEGIA
  // ============================================================

  void _sortCandidatesForStrategy(
    List<_CouponCandidate> items,
    String strategy,
  ) {
    final normalized = strategy.toUpperCase().trim();

    if (normalized == 'PREMIUM') {
      // PREMIUM:
      // priorità ad affidabilità, rischio e quota più prudente.
      items.sort((a, b) {
        final risk = _riskQuality(
          b.selection.risk,
        ).compareTo(_riskQuality(a.selection.risk));
        if (risk != 0) {
          return risk;
        }

        final probability = b.aiProbability.compareTo(a.aiProbability);
        if (probability != 0) {
          return probability;
        }

        final smartScore = b.selection.smartScore.compareTo(
          a.selection.smartScore,
        );
        if (smartScore != 0) {
          return smartScore;
        }

        return a.selection.odd.compareTo(b.selection.odd);
      });

      return;
    }

    if (normalized == 'VALUE') {
      // VALUE:
      // priorità all'expected value reale e poi all'edge.
      items.sort((a, b) {
        final aEv = (a.aiProbability * a.selection.odd) - 1.0;
        final bEv = (b.aiProbability * b.selection.odd) - 1.0;

        final ev = bEv.compareTo(aEv);
        if (ev != 0) {
          return ev;
        }

        final edge = b.edge.compareTo(a.edge);
        if (edge != 0) {
          return edge;
        }

        return b.qualityScore.compareTo(a.qualityScore);
      });

      return;
    }

    // BILANCIATA:
    // usa il ranking composito generale.
    _sortCandidates(items);
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

  SmartBetCouponResult _emptyResult({
    required String message,
    String profileName = 'SMART',
    int analyzedMatches = 0,
  }) {
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
      message: message,
      profileName: profileName,
    );
  }
}
