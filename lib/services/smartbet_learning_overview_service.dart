import 'smartbet_analysis_history_store.dart';
import 'smartbet_scorer_learning_service.dart';

/// Conteggi ricavati esclusivamente da record locali realmente presenti.
/// Non sono una stima del vantaggio economico o delle correzioni live applicate.
class SmartBetLearningOverview {
  final int marketRecorded;
  final int marketVerified;
  final int marketCorrect;
  final int marketWrong;
  final int scorerRecorded;
  final int scorerVerified;
  final int scorerScored;
  final int scorerVerifiedFixtures;
  final int scorerVerifiedDays;

  const SmartBetLearningOverview({
    required this.marketRecorded,
    required this.marketVerified,
    required this.marketCorrect,
    required this.marketWrong,
    required this.scorerRecorded,
    required this.scorerVerified,
    required this.scorerScored,
    required this.scorerVerifiedFixtures,
    required this.scorerVerifiedDays,
  });

  int get marketPending => marketRecorded - marketVerified;
  int get scorerPending => scorerRecorded - scorerVerified;
  double? get marketHitRate =>
      marketVerified == 0 ? null : 100.0 * marketCorrect / marketVerified;
  double? get scorerHitRate =>
      scorerVerified == 0 ? null : 100.0 * scorerScored / scorerVerified;

  static SmartBetLearningOverview fromRecords({
    required Iterable<SmartBetAnalysisRecord> marketRecords,
    required Iterable<SmartBetScorerLearningRecord> scorerRecords,
  }) {
    final markets = marketRecords
        .where((r) => r.engine == SmartBetAnalysisEngine.smartBet)
        .toList();
    // Solo record prospettici verificati sono idonei all'accuratezza.
    final marketResolved = markets
        .where(
          (r) =>
              r.prospectiveEligible &&
              (r.status == SmartBetAnalysisStatus.correct ||
                  r.status == SmartBetAnalysisStatus.wrong),
        )
        .toList();
    final scorers = scorerRecords.toList();
    final scorerResolved = scorers.where((r) => r.isResolved).toList();
    final fixtures = scorerResolved.map((r) => r.fixtureId).toSet();
    final days = scorerResolved.map((r) {
      final d = r.predictedAt.toUtc();
      return '${d.year}-${d.month}-${d.day}';
    }).toSet();

    return SmartBetLearningOverview(
      marketRecorded: markets.length,
      marketVerified: marketResolved.length,
      marketCorrect: marketResolved
          .where((r) => r.status == SmartBetAnalysisStatus.correct)
          .length,
      marketWrong: marketResolved
          .where((r) => r.status == SmartBetAnalysisStatus.wrong)
          .length,
      scorerRecorded: scorers.length,
      scorerVerified: scorerResolved.length,
      scorerScored: scorerResolved.where((r) => r.scored).length,
      scorerVerifiedFixtures: fixtures.length,
      scorerVerifiedDays: days.length,
    );
  }
}
