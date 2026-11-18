import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_service.dart';
import 'goalvdline_third_brain_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_match_simulation_service.dart';

/// Raccolta prospettica SHADOW del terzo motore, separata dalla scelta
/// SmartBet e da Diego. Registra solo mercati binari liquidabili,
/// determinati PRIMA del risultato e scelti senza guardare le quote.
///
/// Importante: la simulazione usa xG SmartBet o Diego quando il primo
/// non è disponibile. Si conserva la provenienza per non scambiare una
/// diversa matematica per un insieme completamente indipendente di dati.
class GoalVdLineThirdBrainHistoryCaptureService {
  final SmartBetAnalysisHistoryStore _store;

  GoalVdLineThirdBrainHistoryCaptureService({
    required SmartBetAnalysisHistoryStore store,
  }) : _store = store;

  static const int minimumDataConfidence = 40;

  /// Un solo mercato preselezionato per famiglia. Non registriamo tutti
  /// gli esiti opposti come se il cervello li avesse pronosticati insieme.
  /// Le famiglie e il tie-break sono fissi, prima di guardare la partita.
  static const List<List<String>> marketFamilies = [
    ['1', 'X', '2'],
    ['1X', 'X2', '12'],
    ['GOAL', 'NO GOAL'],
    ['OVER 1.5', 'UNDER 1.5'],
    ['OVER 2.5', 'UNDER 2.5'],
  ];

  Future<List<SmartBetAnalysisRecord>> capture({
    required MatchModel match,
    required AnalysisResult smartBet,
    DiegoAiAnalysis? diego,
    required SmartBetAnalysisSource source,
    DateTime? recordedAt,
  }) async {
    final kickoff = DateTime.tryParse(match.date)?.toUtc();
    final now = (recordedAt ?? DateTime.now()).toUtc();
    if (kickoff == null || !now.isBefore(kickoff) ||
        match.fixtureId <= 0 || match.league.trim().isEmpty ||
        match.country.trim().isEmpty) {
      return const [];
    }

    // Blocca la scelta delle famiglie sulla PRIMA lettura della fixture.
    // Un aggiornamento degli xG nella stessa partita non deve creare un
    // sesto mercato o scegliere retrospettivamente quello piu' facile.
    // Si accodano solo le fonti, mantenendo probabilita' e metadati originali.
    await _store.initialize();
    final frozen = _store.records
        .where((r) => r.engine == SmartBetAnalysisEngine.thirdBrain &&
            r.fixtureId == match.fixtureId)
        .toList(growable: false);
    if (frozen.isNotEmpty) {
      final linked = <SmartBetAnalysisRecord>[];
      for (final previous in frozen) {
        final updated = await _store.registerAnalysis(
          engine: SmartBetAnalysisEngine.thirdBrain,
          source: source,
          fixtureId: match.fixtureId,
          homeTeam: previous.homeTeam,
          awayTeam: previous.awayTeam,
          league: previous.league,
          country: previous.country,
          matchDate: previous.matchDate,
          market: previous.market,
          probability: previous.probability,
          confidence: previous.confidence,
          inputSource: previous.inputSource,
          modelVersion: previous.modelVersion,
          recordedAt: now,
        );
        if (updated != null) linked.add(updated);
      }
      return List.unmodifiable(linked);
    }

    final report = const GoalVdLineThirdBrainService().evaluate(
      smartBet: smartBet,
      diego: diego,
    );
    if (report == null || report.dataConfidence == null ||
        report.dataConfidence! < minimumDataConfidence) {
      return const [];
    }

    final saved = <SmartBetAnalysisRecord>[];
    for (final family in marketFamilies) {
      GoalVdLineThirdBrainMarket? best;
      for (final name in family) {
        final candidate = report.forMarket(name);
        if (candidate == null || !candidate.probability.isFinite ||
            candidate.probability < 0 || candidate.probability > 1) {
          continue;
        }
        // '>': ties keep first predetermined market, never choose by odds.
        if (best == null || candidate.probability > best.probability) {
          best = candidate;
        }
      }
      if (best == null) continue;
      final record = await _store.registerAnalysis(
        engine: SmartBetAnalysisEngine.thirdBrain,
        source: source,
        fixtureId: match.fixtureId,
        homeTeam: match.homeTeam,
        awayTeam: match.awayTeam,
        league: match.league,
        country: match.country,
        matchDate: kickoff,
        market: best.market,
        probability: best.probability,
        confidence: report.dataConfidence,
        inputSource: report.inputSource,
        modelVersion: 'third-brain-${SmartBetMatchSimulationService.modelVersion}',
        // Nessuna quota inventata e nessuna esecuzione di schedina.
        quotedOdd: null,
        recordedAt: now,
      );
      if (record != null) saved.add(record);
    }
    return List.unmodifiable(saved);
  }
}
