import 'smartbet_live_calibration_service.dart';
import 'smartbet_shared_local_learning_service.dart';

/// Scelta numerica usata da Risultati del giorno.
/// La stima originale e quella visualizzata sono sempre distinguibili.
class SmartBetDailyLearningChoice {
  final int originalPercent;
  final int percent;
  final int samples;
  final double edge;
  final double expectedValue;

  const SmartBetDailyLearningChoice({
    required this.originalPercent,
    required this.percent,
    required this.samples,
    required this.edge,
    required this.expectedValue,
  });

  bool get applied => originalPercent != percent;
}

class SmartBetDailyLearningChoiceService {
  const SmartBetDailyLearningChoiceService._();

  static SmartBetDailyLearningChoice evaluate({
    required SmartBetLiveCalibrationSession? session,
    required String market,
    required int fixtureId,
    required int originalPercent,
    required double odd,
  }) {
    final hasRealOdd = odd.isFinite && odd >= 1.25;
    final correction = SmartBetSharedLocalLearningService.evaluate(
      session: session,
      market: market,
      originalPercent: originalPercent,
      fixtureId: fixtureId,
      hasRealOdd: hasRealOdd,
    );
    final percent = correction.percent;
    final p = percent / 100.0;
    final edge = hasRealOdd ? p - 1.0 / odd : 0.0;
    final ev = hasRealOdd ? p * odd - 1.0 : 0.0;
    return SmartBetDailyLearningChoice(
      originalPercent: correction.originalPercent,
      percent: percent,
      samples: correction.samples,
      edge: edge,
      expectedValue: ev,
    );
  }
}
