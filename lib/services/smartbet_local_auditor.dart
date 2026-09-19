import '../models/analysis_result.dart';

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

    if (odd < 1.25) {
      return const SmartBetLocalAudit(
        status: SmartBetLocalAuditStatus.block,
        reasons: <String>['Quota reale inferiore a 1.25.'],
      );
    }

    if (analysis.smartScore < 50) {
      reasons.add('Smart Score non pienamente solido.');
    }

    final implied = 100.0 / odd;
    if (probability - implied < -12.0) {
      reasons.add('Probabilità SmartBet inferiore alla probabilità implicita.');
    }

    return SmartBetLocalAudit(
      status: reasons.isEmpty
          ? SmartBetLocalAuditStatus.confirm
          : SmartBetLocalAuditStatus.doubt,
      reasons: List<String>.unmodifiable(reasons),
    );
  }
}
