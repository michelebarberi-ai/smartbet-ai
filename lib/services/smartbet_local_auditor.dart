import '../models/analysis_result.dart';
import 'goalvdline_quote_policy.dart';

enum SmartBetLocalAuditStatus { confirm, doubt, block }

class SmartBetLocalAudit {
  final SmartBetLocalAuditStatus status;
  final List<String> reasons;

  const SmartBetLocalAudit({required this.status, required this.reasons});

  bool get isBlocked => status == SmartBetLocalAuditStatus.block;
  bool get isDoubt => status == SmartBetLocalAuditStatus.doubt;
  bool get isConfirmed => status == SmartBetLocalAuditStatus.confirm;

  bool blocksMarket(String market) => false;
}

class SmartBetLocalAuditor {
  const SmartBetLocalAuditor._();

  static SmartBetLocalAudit evaluate({
    required AnalysisResult analysis,
    required String market,
    required int probability,
    required double odd,
  }) {
    final reasons = <String>[];

    if (probability <= 0 || analysis.smartScore <= 0) {
      return const SmartBetLocalAudit(
        status: SmartBetLocalAuditStatus.block,
        reasons: <String>['Dati probabilistici insufficienti.'],
      );
    }

    // B47: un'unica soglia in app, esclusivamente quote finite > 1.20.
    if (!GoalVdLineQuotePolicy.isPlayable(odd)) {
      return const SmartBetLocalAudit(
        status: SmartBetLocalAuditStatus.block,
        reasons: <String>['Quota reale assente o non superiore a 1.20.'],
      );
    }

    // Se l'audit sportivo remoto e' stato effettivamente eseguito,
    // il suo eventuale veto ha precedenza sul controllo locale.
    if (analysis.hasSportsAuditVeto ||
        analysis.sportsAuditBlockedMarkets.any(
          (blocked) => blocked.trim().toUpperCase() ==
              market.trim().toUpperCase(),
        )) {
      return const SmartBetLocalAudit(
        status: SmartBetLocalAuditStatus.block,
        reasons: <String>['Mercato escluso dall’Auditor sportivo.'],
      );
    }

    if (analysis.smartScore < 50) {
      reasons.add('Smart Score non pienamente solido.');
    }

    final implied = 100.0 / odd;
    final positiveGap = probability - implied;

    // B79: a very large positive gap is NOT evidence of a valuable bet.
    // It may indicate an inverted Asian handicap sign, the wrong line,
    // a stale/provider quote, or a badly calibrated sports estimate.
    // Quarantine the *quoted selection*, not the sports prediction itself.
    // This check runs only after the model has ranked its markets.
    if (probability >= 65 && positiveGap > 35.0) {
      return const SmartBetLocalAudit(
        status: SmartBetLocalAuditStatus.block,
        reasons: <String>[
          'Quota e probabilità fortemente divergenti: verificare '
              'mercato, segno handicap e quota del bookmaker.',
        ],
      );
    }

    if (positiveGap > 25.0) {
      reasons.add(
        'Probabilità AI molto superiore a quella implicita nella quota: '
            'mercato da verificare.',
      );
    }

    if (positiveGap < -12.0) {
      reasons.add(
        'Probabilità GoalVdLine inferiore alla probabilità implicita.',
      );
    }

    return SmartBetLocalAudit(
      status: reasons.isEmpty
          ? SmartBetLocalAuditStatus.confirm
          : SmartBetLocalAuditStatus.doubt,
      reasons: List<String>.unmodifiable(reasons),
    );
  }
}
