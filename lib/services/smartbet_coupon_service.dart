import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'smartbet_ai_service.dart';
import 'smartbet_sports_market_selector.dart';
import 'smartbet_sports_coupon_adapter.dart';
import 'smartbet_shared_local_learning_service.dart';
import 'smartbet_live_calibration_service.dart';
import 'smartbet_analysis_registration_service.dart';
import 'odds_service.dart';

// ============================================================
// SINGOLA SELEZIONE DELLA SCHEDINA
// ============================================================

class SmartBetCouponSelection {
  final MatchModel match;
  final AnalysisResult analysis;

  /// Pronostico selezionato dal motore sportivo.
  /// Null mantiene la compatibilita con le vecchie selezioni.
  final SmartBetSportsMarketPick? sportsPick;
  final String? sportsBookmaker;

  /// Solo per la schedina live. Non sostituisce la previsione originaria
  /// del modello, che resta in sportsPick ed e' quella salvata nello storico.
  final int? calibratedProbabilityPercent;
  final int learningSamples;

  int get originalProbabilityPercent => sportsPick?.probability ?? 0;
  int get effectiveProbabilityPercent =>
      calibratedProbabilityPercent ?? originalProbabilityPercent;
  bool get hasLocalCalibration =>
      calibratedProbabilityPercent != null &&
      calibratedProbabilityPercent != originalProbabilityPercent;

  const SmartBetCouponSelection({
    required this.match,
    required this.analysis,
    this.sportsPick,
    this.sportsBookmaker,
    this.calibratedProbabilityPercent,
    this.learningSamples = 0,
  });

  String get matchLabel {
    return '${match.homeTeam} - ${match.awayTeam}';
  }

  String get outcome {
    return sportsPick?.market ?? analysis.stakeOutcome;
  }

  double get odd {
    return sportsPick?.odd ?? analysis.stakeOdd;
  }

  String get bookmaker {
    return sportsBookmaker ?? analysis.stakeBookmaker;
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

  /// Mercati secondari derivati dalle STESSE analisi dei profili.
  /// Usati solo dalla generazione headless a tre schedine; non cambiano i
  /// profili e non vengono registrati automaticamente come pronostici giocati.
  final List<SmartBetCouponSelection> verifiedMarketAlternatives;

  const SmartBetCouponSet({
    required this.premium,
    required this.balanced,
    required this.value,
    this.verifiedMarketAlternatives = const <SmartBetCouponSelection>[],
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

  final bool rejectHighRisk;

  const _CouponProfile({
    required this.name,
    required this.minimumSmartScore,
    required this.minimumAiProbability,
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
  /// Provider opzionali per test senza richieste API.
  /// In produzione vengono usati i servizi originali.
  final Future<AnalysisResult> Function(MatchModel)? analysisProvider;
  final Future<FixtureMarketOdds?> Function(int)? oddsProvider;
  final Future<SmartBetLiveCalibrationSession?> Function()? learningProvider;
  final SmartBetSharedLearningProbability Function({
    required SmartBetLiveCalibrationSession? session,
    required String market,
    required int originalPercent,
    required int fixtureId,
    required bool hasRealOdd,
  })?
  learningEvaluator;
  final Future<void> Function(SmartBetCouponSelection)? registrationProvider;

  SmartBetCouponService({
    this.analysisProvider,
    this.oddsProvider,
    this.learningProvider,
    this.learningEvaluator,
    this.registrationProvider,
  });

  static const int maximumSelections = 6;

  static const int minimumSelections = 2;

  // Analisi AI avanzata controllata:
  // massimo 2 partite contemporaneamente.
  static const int advancedBatchSize = 2;

  static const double minimumOdd = 1.25;

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
    rejectHighRisk: true,
  );

  // Secondo tentativo:
  // buon compromesso affidabilità/value.
  static const _CouponProfile _balancedProfile = _CouponProfile(
    name: 'BILANCIATA',
    minimumSmartScore: 62,
    minimumAiProbability: 0.27,
    rejectHighRisk: false,
  );

  // Ultimo tentativo:
  // accetta value più aggressive,
  // ma mantiene un limite assoluto.
  static const _CouponProfile _controlledValueProfile = _CouponProfile(
    name: 'VALUE CONTROLLATO',
    minimumSmartScore: 62,
    minimumAiProbability: 0.25,
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
    rejectHighRisk: true,
  );

  static const _CouponProfile _balancedAdaptiveProfile = _CouponProfile(
    name: 'BILANCIATA',
    minimumSmartScore: 58,
    minimumAiProbability: 0.24,
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
    int maximumValueSelections = maximumSelections,
    bool collectVerifiedAlternatives = false,
  }) async {
    final safeMinimum = minimumRequired.clamp(1, minimumSelections);
    if (maximumValueSelections < 2 || maximumValueSelections > 15) {
      throw ArgumentError.value(
        maximumValueSelections,
        'maximumValueSelections',
      );
    }

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

    // La stessa preferenza locale di GoalVdLine e Combinazioni AI.
    // Uno snapshot per generazione: fail-closed se OFF o gate non idoneo.
    final learningSession = learningProvider != null
        ? await learningProvider!()
        : await const SmartBetSharedLocalLearningService().prepare();

    final aiService = analysisProvider == null ? SmartBetAiService() : null;
    final oddsService = oddsProvider == null ? OddsService() : null;

    final analyzed = <SmartBetCouponSelection>[];
    final verifiedMarketAlternatives = <SmartBetCouponSelection>[];

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

        final results = await Future.wait(
          batch.map(
            (match) => analysisProvider != null
                ? analysisProvider!(match)
                : aiService!.analyzeMatch(match, runAudit: true),
          ),
        );

        for (int i = 0; i < results.length; i++) {
          final match = batch[i];
          final result = results[i];

          analyzedMatches++;

          if (!_isBaseValid(result)) {
            continue;
          }

          FixtureMarketOdds? marketOdds;
          try {
            marketOdds = oddsProvider != null
                ? await oddsProvider!(match.fixtureId)
                : await oddsService!.getFixtureMarketOdds(
                    fixtureId: match.fixtureId,
                  );
          } catch (_) {
            marketOdds = null;
          }

          final sportsPick = SmartBetSportsCouponAdapter.bestPlayable(
            analysis: result,
            odds: marketOdds,
          );

          if (sportsPick == null) {
            continue;
          }

          final bookmaker = marketOdds
              ?.oddFor(sportsPick.market)
              ?.bookmakerName;

          // Non alteriamo il mercato deciso dall'Auditor sportivo.
          // Le correzioni sono applicabili solo a una scelta con quota reale.
          final evaluateLearning =
              learningEvaluator ?? SmartBetSharedLocalLearningService.evaluate;
          final learning = evaluateLearning(
            session: learningSession,
            market: sportsPick.market,
            originalPercent: sportsPick.probability,
            fixtureId: match.fixtureId,
            hasRealOdd: sportsPick.odd.isFinite && sportsPick.odd >= minimumOdd,
          );

          analyzed.add(
            SmartBetCouponSelection(
              match: match,
              analysis: result,
              sportsPick: sportsPick,
              sportsBookmaker: bookmaker,
              calibratedProbabilityPercent: learning.applied
                  ? learning.percent
                  : null,
              learningSamples: learning.applied ? learning.samples : 0,
            ),
          );

          if (collectVerifiedAlternatives &&
              result.smartScore >= _controlledValueProfile.minimumSmartScore &&
              !_isHighRisk(result.risk)) {
            // Nessuna nuova analisi o modello parallelo: tutti i mercati
            // della stessa partita, incluso il principale se il profilo
            // Value non lo ha scelto, con quota reale e audit verificati.
            for (final alternative in SmartBetSportsCouponAdapter.allPlayable(
              analysis: result,
              odds: marketOdds,
            )) {
              final alternativeLearning = evaluateLearning(
                session: learningSession,
                market: alternative.market,
                originalPercent: alternative.probability,
                fixtureId: match.fixtureId,
                hasRealOdd: true,
              );
              verifiedMarketAlternatives.add(
                SmartBetCouponSelection(
                  match: match,
                  analysis: result,
                  sportsPick: alternative,
                  sportsBookmaker: marketOdds
                      ?.oddFor(alternative.market)
                      ?.bookmakerName,
                  calibratedProbabilityPercent: alternativeLearning.applied
                      ? alternativeLearning.percent
                      : null,
                  learningSamples: alternativeLearning.applied
                      ? alternativeLearning.samples
                      : 0,
                ),
              );
            }
          }
        }

        if (end < matches.length) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      aiService?.dispose();
    }

    if (analyzed.isEmpty) {
      final commonMessage =
          'Nessuna partita ha superato i controlli sportivi. '
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
      maximumProfileSelections: maximumValueSelections,
      minimumRequired: valueMinimum,
      allowSmartFallback: true,
      strategy: 'VALUE',
    );

    final coupons = SmartBetCouponSet(
      premium: premium,
      balanced: balanced,
      value: value,
      verifiedMarketAlternatives: List.unmodifiable(verifiedMarketAlternatives),
    );

    // Memorizza le previsioni effettivamente selezionate una sola volta
    // per fixture e mercato. SEMPRE la probabilita' originale del modello:
    // una calibrazione non puo' diventare il proprio dato di training.
    await _registerOriginalPredictions(coupons);
    return coupons;
  }

  // ============================================================
  // COSTRUISCE UNA STRATEGIA DA RISULTATI GIÀ ANALIZZATI
  // ============================================================

  Future<void> _registerOriginalPredictions(SmartBetCouponSet coupons) async {
    final unique = <String, SmartBetCouponSelection>{};
    for (final result in [coupons.premium, coupons.balanced, coupons.value]) {
      for (final selection in result.selections) {
        unique.putIfAbsent(
          '${selection.match.fixtureId}|${selection.outcome}',
          () => selection,
        );
      }
    }
    for (final selection in unique.values) {
      try {
        if (registrationProvider != null) {
          await registrationProvider!(selection);
        } else if (analysisProvider == null && oddsProvider == null) {
          await SmartBetAnalysisRegistrationService().registerSelection(
            match: selection.match,
            smartBet: selection.analysis,
            source: SmartBetAnalysisSource.aiCoupon,
            smartBetMarket: selection.outcome,
            smartBetProbabilityPercent: selection.originalProbabilityPercent,
            smartBetOdd: selection.odd,
          );
        }
      } catch (_) {
        // Il salvataggio dello storico non blocca la generazione.
      }
    }
  }

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
            'GoalVdLine non forza eventi deboli.',
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
                'dopo i controlli statistici e di disponibilita.'
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
    return result.smartScore > 0 &&
        result.hasVerifiedSportsAudit &&
        !result.hasSportsAuditVeto;
  }

  // ============================================================
  // CREA CANDIDATO PER PROFILO
  // ============================================================

  _CouponCandidate? _buildCandidate({
    required SmartBetCouponSelection selection,
    required _CouponProfile profile,
  }) {
    final result = selection.analysis;

    if (selection.sportsPick == null ||
        selection.odd < minimumOdd ||
        result.smartScore < profile.minimumSmartScore) {
      return null;
    }

    final probability = _selectionProbability(selection);

    if (probability < profile.minimumAiProbability) {
      return null;
    }

    if (profile.rejectHighRisk && _isHighRisk(result.risk)) {
      return null;
    }

    // Informazioni economiche conservate, non usate nel ranking.
    final impliedProbability = 1.0 / selection.odd;
    final edge = probability - impliedProbability;

    return _CouponCandidate(
      selection: selection,
      aiProbability: probability,
      impliedProbability: impliedProbability,
      edge: edge,
      qualityScore: _calculateQualityScore(
        selection: selection,
        probability: probability,
      ),
    );
  }

  // ============================================================
  // FALLBACK SMART
  // ============================================================

  _CouponCandidate? _buildSmartFallbackCandidate(
    SmartBetCouponSelection selection,
  ) {
    final result = selection.analysis;

    if (selection.sportsPick == null ||
        selection.odd < minimumOdd ||
        result.smartScore < _smartFallbackMinimumScore) {
      return null;
    }

    final probability = _selectionProbability(selection);

    if (probability < _smartFallbackMinimumProbability) {
      return null;
    }

    if (_isHighRisk(result.risk) && result.smartScore < 72) {
      return null;
    }

    final impliedProbability = 1.0 / selection.odd;
    final edge = probability - impliedProbability;

    return _CouponCandidate(
      selection: selection,
      aiProbability: probability,
      impliedProbability: impliedProbability,
      edge: edge,
      qualityScore: _calculateQualityScore(
        selection: selection,
        probability: probability,
      ),
    );
  }

  // ============================================================
  // ORDINA CANDIDATI PER STRATEGIA
  // ============================================================

  void _sortCandidatesForStrategy(
    List<_CouponCandidate> items,
    String strategy,
  ) {
    final mode = strategy.toUpperCase().trim();

    items.sort((a, b) {
      int comparison;

      if (mode == 'PREMIUM') {
        comparison = _riskQuality(
          b.selection.risk,
        ).compareTo(_riskQuality(a.selection.risk));
        if (comparison != 0) return comparison;
      }

      if (mode == 'VALUE') {
        comparison = b.aiProbability.compareTo(a.aiProbability);
        if (comparison != 0) return comparison;
      }

      comparison = b.qualityScore.compareTo(a.qualityScore);
      if (comparison != 0) return comparison;

      comparison = b.aiProbability.compareTo(a.aiProbability);
      if (comparison != 0) return comparison;

      comparison = a.selection.match.fixtureId.compareTo(
        b.selection.match.fixtureId,
      );
      if (comparison != 0) return comparison;

      return a.selection.outcome.compareTo(b.selection.outcome);
    });
  }

  // ============================================================
  // ORDINA CANDIDATI
  // ============================================================

  // ============================================================
  // QUALITY SCORE
  // ============================================================

  double _calculateQualityScore({
    required SmartBetCouponSelection selection,
    required double probability,
  }) {
    final score = (selection.smartScore / 100.0).clamp(0.0, 1.0);
    final chance = probability.clamp(0.0, 1.0);
    final risk = _riskQuality(selection.risk);

    // Pesi provvisori da validare sui risultati storici.
    // Nessuna dipendenza da quota, EV, edge o stake.
    return (score * 0.45 + chance * 0.40 + risk * 0.15) * 100.0;
  }

  // ============================================================
  // QUALITÀ QUOTA
  // ============================================================

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
    final sportsPick = selection.sportsPick;
    if (sportsPick != null) {
      return selection.effectiveProbabilityPercent.clamp(0, 100) / 100.0;
    }

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

    if (combinedProbability < 0.10) {
      return 'Alto';
    }

    if (combinedProbability < 0.18) {
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
    // P18B2F: stake automatico temporaneamente disattivato.
    // La vecchia raccomandazione potrebbe riferirsi
    // a un mercato diverso dal pronostico sportivo.
    return 0.0;
  }

  // ============================================================
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
