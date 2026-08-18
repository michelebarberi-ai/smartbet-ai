import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import 'settings_store.dart';
import 'smartbet_coupon_service.dart';

class SmartBetAutoCouponProgress {
  final String phase;
  final int current;
  final int total;
  final String message;

  const SmartBetAutoCouponProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.message,
  });

  double get progress {
    if (total <= 0) {
      return 0.0;
    }

    return (current / total).clamp(0.0, 1.0);
  }
}

class SmartBetAutoCouponResult {
  final SmartBetCouponResult coupon;

  final int totalMatches;

  final int metadataCandidates;

  final int preliminaryAnalyzed;

  final int preliminaryValid;

  final int advancedCandidates;

  const SmartBetAutoCouponResult({
    required this.coupon,
    required this.totalMatches,
    required this.metadataCandidates,
    required this.preliminaryAnalyzed,
    required this.preliminaryValid,
    required this.advancedCandidates,
  });
}

// ============================================================
// PRE-CANDIDATO
// ============================================================

class _PreliminaryCandidate {
  final MatchModel match;

  final AnalysisResult analysis;

  const _PreliminaryCandidate({required this.match, required this.analysis});

  int get bestProbability {
    return [
      analysis.homeProbability,
      analysis.drawProbability,
      analysis.awayProbability,
    ].reduce((a, b) => a > b ? a : b);
  }

  double get qualityScore {
    final scoreComponent = analysis.smartScore / 100.0;

    final probabilityComponent = bestProbability / 100.0;

    final competitionComponent = match.aiWeight.clamp(0.0, 1.0);

    final riskComponent = _riskQuality(analysis.risk);

    return ((scoreComponent * 0.42) +
            (probabilityComponent * 0.32) +
            (competitionComponent * 0.18) +
            (riskComponent * 0.08)) *
        100.0;
  }

  static double _riskQuality(String risk) {
    final value = risk.toLowerCase();

    if (value.contains('molto basso')) {
      return 1.00;
    }

    if (value == 'basso') {
      return 0.90;
    }

    if (value == 'medio') {
      return 0.70;
    }

    if (value.contains('medio-alto')) {
      return 0.40;
    }

    if (value == 'alto') {
      return 0.15;
    }

    return 0.50;
  }
}

class SmartBetAutoCouponService {
  // ============================================================
  // CONFIGURAZIONE ADATTIVA
  // ============================================================

  // Primo giro:
  // abbastanza veloce.
  static const int initialPreliminaryMatches = 60;

  // Se il primo giro trova troppo poco,
  // analizziamo altre 30 partite.
  static const int expandedPreliminaryMatches = 90;

  // AI avanzata soltanto sulle migliori.
  static const int maximumAdvancedMatches = 12;

  // Pre-analisi concorrente controllata.
  // Tre partite per volta velocizzano il processo senza
  // lanciare decine di richieste contemporaneamente.
  static const int preliminaryBatchSize = 3;

  static const double preferredMinimumAiWeight = 0.70;

  // ============================================================
  // CREA SCHEDINA AUTOMATICA
  // ============================================================

  Future<SmartBetAutoCouponResult> build({
    void Function(SmartBetAutoCouponProgress progress)? onProgress,
  }) async {
    await SettingsStore.instance.initialize();

    final settings = SettingsStore.instance;

    // ==========================================================
    // CARICA PARTITE
    // ==========================================================

    onProgress?.call(
      const SmartBetAutoCouponProgress(
        phase: 'matches',
        current: 0,
        total: 1,
        message: 'Caricamento partite del giorno...',
      ),
    );

    final allMatches = await MatchRepository.getTodayMatches();

    if (allMatches.isEmpty) {
      return SmartBetAutoCouponResult(
        coupon: _emptyCoupon('Nessuna partita disponibile oggi.'),
        totalMatches: 0,
        metadataCandidates: 0,
        preliminaryAnalyzed: 0,
        preliminaryValid: 0,
        advancedCandidates: 0,
      );
    }

    // ==========================================================
    // POOL METADATA
    // ==========================================================

    final metadataPool = _buildMetadataPool(allMatches);

    if (metadataPool.isEmpty) {
      return SmartBetAutoCouponResult(
        coupon: _emptyCoupon(
          'Nessuna partita adatta alla '
          'preselezione automatica.',
        ),
        totalMatches: allMatches.length,
        metadataCandidates: 0,
        preliminaryAnalyzed: 0,
        preliminaryValid: 0,
        advancedCandidates: 0,
      );
    }

    final preliminary = <_PreliminaryCandidate>[];

    int analyzed = 0;

    final desiredAdvanced = _desiredAdvancedCount(settings.couponSelections);

    // ==========================================================
    // PRIMO PASSAGGIO
    // ==========================================================
    //
    // Analizziamo piccoli blocchi in parallelo.
    // Dopo ogni blocco controlliamo se abbiamo già
    // abbastanza candidate valide: in quel caso ci fermiamo
    // senza arrivare necessariamente a 60 partite.
    // ==========================================================

    final firstPassCount = metadataPool.length < initialPreliminaryMatches
        ? metadataPool.length
        : initialPreliminaryMatches;

    for (int start = 0; start < firstPassCount; start += preliminaryBatchSize) {
      final end = (start + preliminaryBatchSize) < firstPassCount
          ? start + preliminaryBatchSize
          : firstPassCount;

      final batch = metadataPool.sublist(start, end);

      onProgress?.call(
        SmartBetAutoCouponProgress(
          phase: 'preliminary',
          current: end,
          total: firstPassCount,
          message:
              'Pre-analisi $end/'
              '$firstPassCount\n'
              '${batch.first.homeTeam} - '
              '${batch.first.awayTeam}'
              '${batch.length > 1 ? ' + altre ${batch.length - 1}' : ''}',
        ),
      );

      await _analyzePreliminaryBatch(matches: batch, output: preliminary);

      analyzed = end;

      final currentSelection = _selectPreliminaryCandidates(
        preliminary,
        preferredScore: settings.minimumSmartScore,
        desiredCount: desiredAdvanced,
      );

      if (currentSelection.length >= desiredAdvanced) {
        break;
      }
    }

    // ==========================================================
    // VALUTA QUANTE CANDIDATE ABBIAMO
    // ==========================================================

    var selectedPreliminary = _selectPreliminaryCandidates(
      preliminary,
      preferredScore: settings.minimumSmartScore,
      desiredCount: desiredAdvanced,
    );

    // ==========================================================
    // ESPANSIONE AUTOMATICA
    // ==========================================================
    //
    // Se il primo giro trova troppo poche candidate,
    // non abbassiamo subito la qualità:
    // analizziamo prima altre partite.
    // ==========================================================

    if (selectedPreliminary.length < desiredAdvanced &&
        metadataPool.length > analyzed) {
      final expansionEnd = metadataPool.length < expandedPreliminaryMatches
          ? metadataPool.length
          : expandedPreliminaryMatches;

      for (
        int start = analyzed;
        start < expansionEnd;
        start += preliminaryBatchSize
      ) {
        final end = (start + preliminaryBatchSize) < expansionEnd
            ? start + preliminaryBatchSize
            : expansionEnd;

        final batch = metadataPool.sublist(start, end);

        onProgress?.call(
          SmartBetAutoCouponProgress(
            phase: 'expansion',
            current: end,
            total: expansionEnd,
            message:
                'Ricerca ampliata $end/'
                '$expansionEnd\n'
                '${batch.first.homeTeam} - '
                '${batch.first.awayTeam}'
                '${batch.length > 1 ? ' + altre ${batch.length - 1}' : ''}',
          ),
        );

        await _analyzePreliminaryBatch(matches: batch, output: preliminary);

        analyzed = end;

        selectedPreliminary = _selectPreliminaryCandidates(
          preliminary,
          preferredScore: settings.minimumSmartScore,
          desiredCount: desiredAdvanced,
        );

        if (selectedPreliminary.length >= desiredAdvanced) {
          break;
        }
      }
    }

    // ==========================================================
    // NESSUNA CANDIDATA
    // ==========================================================

    if (selectedPreliminary.isEmpty) {
      return SmartBetAutoCouponResult(
        coupon: _emptyCoupon(
          'SmartBet non ha trovato partite '
          'con dati statistici sufficienti.',
        ),
        totalMatches: allMatches.length,
        metadataCandidates: metadataPool.length,
        preliminaryAnalyzed: analyzed,
        preliminaryValid: preliminary.length,
        advancedCandidates: 0,
      );
    }

    // ==========================================================
    // ORDINA PER QUALITÀ PRELIMINARE
    // ==========================================================

    selectedPreliminary.sort((a, b) {
      final qualityComparison = b.qualityScore.compareTo(a.qualityScore);

      if (qualityComparison != 0) {
        return qualityComparison;
      }

      final scoreComparison = b.analysis.smartScore.compareTo(
        a.analysis.smartScore,
      );

      if (scoreComparison != 0) {
        return scoreComparison;
      }

      return b.bestProbability.compareTo(a.bestProbability);
    });

    // ==========================================================
    // SHORTLIST AI AVANZATA
    // ==========================================================

    final advancedShortlist = selectedPreliminary
        .take(maximumAdvancedMatches)
        .map((item) => item.match)
        .toList();

    onProgress?.call(
      SmartBetAutoCouponProgress(
        phase: 'advanced',
        current: 0,
        total: advancedShortlist.length,
        message:
            'Preselezione completata.\n'
            '${advancedShortlist.length} '
            'candidate passano '
            'all’analisi AI avanzata.',
      ),
    );

    // ==========================================================
    // MOTORE SCHEDINA
    // ==========================================================

    final couponService = SmartBetCouponService();

    final rawCoupon = await couponService.buildCoupon(
      matches: advancedShortlist,
    );

    // ==========================================================
    // LIMITE IMPOSTAZIONI
    // ==========================================================

    final coupon = _applySelectionLimit(rawCoupon, settings.couponSelections);

    onProgress?.call(
      SmartBetAutoCouponProgress(
        phase: 'complete',
        current: advancedShortlist.length,
        total: advancedShortlist.length,
        message: coupon.hasCoupon
            ? 'Schedina SmartBet completata.'
            : 'Nessuna schedina consigliata.',
      ),
    );

    return SmartBetAutoCouponResult(
      coupon: coupon,
      totalMatches: allMatches.length,
      metadataCandidates: metadataPool.length,
      preliminaryAnalyzed: analyzed,
      preliminaryValid: preliminary.length,
      advancedCandidates: advancedShortlist.length,
    );
  }

  // ============================================================
  // ANALISI PRELIMINARE
  // ============================================================

  Future<void> _analyzePreliminaryBatch({
    required List<MatchModel> matches,
    required List<_PreliminaryCandidate> output,
  }) async {
    final results = await Future.wait(
      matches.map(_analyzePreliminaryCandidate),
    );

    for (final candidate in results) {
      if (candidate != null) {
        output.add(candidate);
      }
    }
  }

  Future<_PreliminaryCandidate?> _analyzePreliminaryCandidate(
    MatchModel match,
  ) async {
    try {
      final result = await SmartCore.analyze(match);

      if (result.smartScore <= 0) {
        return null;
      }

      // Manteniamo anche score inferiori alla
      // soglia preferita.
      //
      // Servono per l'adattamento successivo.
      if (result.smartScore < 55) {
        return null;
      }

      return _PreliminaryCandidate(match: match, analysis: result);
    } catch (_) {
      // Una partita non deve interrompere
      // l'intera schedina.
      return null;
    }
  }

  // ============================================================
  // SELEZIONE ADATTIVA PRELIMINARE
  // ============================================================

  List<_PreliminaryCandidate> _selectPreliminaryCandidates(
    List<_PreliminaryCandidate> source, {
    required int preferredScore,
    required int desiredCount,
  }) {
    if (source.isEmpty) {
      return [];
    }

    final firstThreshold = preferredScore.clamp(55, 90);

    final thresholds = <int>[
      firstThreshold,
      (firstThreshold - 3).clamp(55, 90),
      (firstThreshold - 5).clamp(55, 90),
      60,
      58,
      55,
    ];

    final uniqueThresholds = <int>[];

    for (final threshold in thresholds) {
      if (!uniqueThresholds.contains(threshold)) {
        uniqueThresholds.add(threshold);
      }
    }

    List<_PreliminaryCandidate> fallback = [];

    for (final threshold in uniqueThresholds) {
      final current = source
          .where((item) => item.analysis.smartScore >= threshold)
          .toList();

      if (current.length > fallback.length) {
        fallback = current;
      }

      if (current.length >= desiredCount) {
        return current;
      }
    }

    return fallback;
  }

  // ============================================================
  // QUANTE CANDIDATE AI AVANZATE CERCHIAMO
  // ============================================================

  int _desiredAdvancedCount(int requestedSelections) {
    // Cerchiamo circa il doppio delle
    // selezioni finali.
    //
    // Esempio:
    // 6 desiderate -> 12 candidate AI.
    // 5 desiderate -> 10 candidate.
    // 3 desiderate -> 8 candidate minime.
    var desired = requestedSelections * 2;

    if (desired < 8) {
      desired = 8;
    }

    if (desired > maximumAdvancedMatches) {
      desired = maximumAdvancedMatches;
    }

    return desired;
  }

  // ============================================================
  // POOL METADATA
  // ============================================================

  List<MatchModel> _buildMetadataPool(List<MatchModel> matches) {
    final now = DateTime.now();

    final preferred = <MatchModel>[];

    final secondary = <MatchModel>[];

    final fallback = <MatchModel>[];

    for (final match in matches) {
      if (!match.hasTeamIds) {
        continue;
      }

      DateTime? matchDate;

      try {
        matchDate = DateTime.parse(match.date).toLocal();
      } catch (_) {}

      if (matchDate != null && matchDate.isBefore(now)) {
        continue;
      }

      // ========================================================
      // LIVELLO 1
      // ========================================================

      if (!match.isFriendly && match.aiWeight >= 0.85) {
        preferred.add(match);
        continue;
      }

      // ========================================================
      // LIVELLO 2
      // ========================================================

      if (!match.isFriendly && match.aiWeight >= preferredMinimumAiWeight) {
        secondary.add(match);
        continue;
      }

      // ========================================================
      // RISERVA
      // ========================================================

      fallback.add(match);
    }

    preferred.sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

    secondary.sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

    fallback.sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

    // ==========================================================
    // DIVERSIFICAZIONE
    // ==========================================================
    //
    // Evitiamo di riempire la shortlist
    // con decine di partite dello stesso
    // campionato.
    // ==========================================================

    final ordered = [...preferred, ...secondary, ...fallback];

    final result = <MatchModel>[];

    final leagueCounts = <String, int>{};

    for (final match in ordered) {
      final key = '${match.country}::${match.league}';

      final count = leagueCounts[key] ?? 0;

      // Massimo 8 partite per competizione
      // nel pool preliminare.
      if (count >= 8) {
        continue;
      }

      leagueCounts[key] = count + 1;

      result.add(match);

      if (result.length >= expandedPreliminaryMatches) {
        break;
      }
    }

    return result;
  }

  // ============================================================
  // APPLICA LIMITE SELEZIONI
  // ============================================================

  SmartBetCouponResult _applySelectionLimit(
    SmartBetCouponResult original,
    int requestedSelections,
  ) {
    if (!original.hasCoupon) {
      return original;
    }

    final limit = requestedSelections.clamp(2, 6);

    if (original.selections.length <= limit) {
      return original;
    }

    final selections = original.selections.take(limit).toList();

    double totalOdd = 1.0;

    double totalScore = 0.0;

    double combinedProbability = 1.0;

    for (final selection in selections) {
      totalOdd *= selection.odd;

      totalScore += selection.smartScore;

      final probability = _selectionProbability(selection);

      if (probability <= 0.0) {
        combinedProbability = 0.0;
      } else if (combinedProbability > 0.0) {
        combinedProbability *= probability;
      }
    }

    final averageScore = totalScore / selections.length;

    final risk = _couponRisk(selections.length, combinedProbability);

    return SmartBetCouponResult(
      selections: selections,
      analyzedMatches: original.analyzedMatches,
      validCandidates: original.validCandidates,
      rejectedMatches: original.rejectedMatches,
      totalOdd: totalOdd,
      averageSmartScore: averageScore,
      estimatedCombinedProbability: combinedProbability,
      riskLevel: risk,
      recommendedStakePercent: original.recommendedStakePercent,
      message:
          '${original.message} '
          'Limite impostato: '
          '${selections.length} eventi.',
    );
  }

  // ============================================================
  // PROBABILITÀ SELEZIONE
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
  // RISCHIO
  // ============================================================

  String _couponRisk(int selections, double probability) {
    if (selections >= 6) {
      return 'Alto';
    }

    if (probability < 0.10) {
      return 'Alto';
    }

    if (probability < 0.18) {
      return 'Medio-Alto';
    }

    if (probability < 0.32) {
      return 'Medio';
    }

    return 'Contenuto';
  }

  // ============================================================
  // EMPTY
  // ============================================================

  SmartBetCouponResult _emptyCoupon(String message) {
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
