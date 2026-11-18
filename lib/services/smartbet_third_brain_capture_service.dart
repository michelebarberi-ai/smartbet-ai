import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_service.dart';
import 'goalvdline_third_brain_service.dart';
import 'smartbet_analysis_history_store.dart';

/// B66: captures the uncalibrated mathematical simulator as prospective
/// evidence only. It cannot generate, promote or change live selections.
class SmartBetThirdBrainCaptureService {
  final SmartBetAnalysisHistoryStore _store;

  SmartBetThirdBrainCaptureService({SmartBetAnalysisHistoryStore? store})
      : _store = store ?? SmartBetAnalysisHistoryStore.instance;

  /// Only unambiguous full-time markets settled by final match scores.
  /// The seven markets are recorded independently; they MUST NOT be treated
  /// as seven independent fixtures in an aggregate comparison.
  static const supportedMarkets = <String>[
    '1', 'X', '2', 'GOAL', 'NO GOAL', 'OVER 2.5', 'UNDER 2.5',
  ];

  Future<List<SmartBetAnalysisRecord>> capture({
    required MatchModel match,
    required AnalysisResult smartBet,
    required SmartBetAnalysisSource source,
    DiegoAiAnalysis? diego,
    DateTime? recordedAt,
  }) async {
    final kickoff = DateTime.tryParse(match.date)?.toUtc();
    final observedAt = (recordedAt ?? DateTime.now()).toUtc();

    // Never backfill new predictions from old match results.
    if (match.fixtureId <= 0 || kickoff == null ||
        !observedAt.isBefore(kickoff)) {
      return const <SmartBetAnalysisRecord>[];
    }

    final report = const GoalVdLineThirdBrainService().evaluate(
      smartBet: smartBet,
      diego: diego?.match.fixtureId == match.fixtureId ? diego : null,
    );
    if (report == null) return const <SmartBetAnalysisRecord>[];

    final probabilities = <String, double>{};
    for (final market in supportedMarkets) {
      final result = report.forMarket(market);
      if (result == null ||
          !result.probability.isFinite ||
          result.probability < 0 ||
          result.probability > 1) {
        continue;
      }
      probabilities[market] = result.probability;
    }
    if (probabilities.isEmpty) return const <SmartBetAnalysisRecord>[];

    return _store.registerMarketBundle(
      engine: SmartBetAnalysisEngine.simulator,
      source: source,
      fixtureId: match.fixtureId,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      league: match.league,
      country: match.country,
      matchDate: kickoff,
      markets: probabilities,
      classification: report.sharesDiegoInputs
          ? 'SIMULATOR_XG_FROM_DIEGO'
          : 'SIMULATOR_XG_FROM_SMARTBET',
      recordedAt: observedAt,
    );
  }
}
