import 'smartbet_device_learning_preferences.dart';
import 'smartbet_live_calibration_service.dart';

/// Risultato per una singola previsione. La probabilità originale deve
/// essere registrata nello storico, non quella usata per la visualizzazione.
class SmartBetSharedLearningProbability {
  final int originalPercent;
  final int percent;
  final int samples;

  const SmartBetSharedLearningProbability({
    required this.originalPercent,
    required this.percent,
    this.samples = 0,
  });

  bool get applied => percent != originalPercent;
}

/// Ponte opt-in tra le diverse schermate: stessa preferenza sul dispositivo,
/// stesso gate di sicurezza; nessuna scrittura nello storico né rete aggiuntiva.
class SmartBetSharedLocalLearningService {
  const SmartBetSharedLocalLearningService();

  /// Uno snapshot immutabile per generazione: esclude qualsiasi risultato
  /// che diventi noto dopo l'inizio della scansione.
  Future<SmartBetLiveCalibrationSession?> prepare() async {
    try {
      final enabled = await const SmartBetDeviceLearningPreferences()
          .loadEnabled();
      if (!enabled) return null;
      return await const SmartBetLiveCalibrationService().prepare(
        optedIn: true,
      );
    } catch (_) {
      // Se il telefono non può leggere lo storico, nessuna correzione.
      return null;
    }
  }

  static SmartBetSharedLearningProbability evaluate({
    required SmartBetLiveCalibrationSession? session,
    required String market,
    required int originalPercent,
    required int fixtureId,
    required bool hasRealOdd,
  }) {
    final original = SmartBetSharedLearningProbability(
      originalPercent: originalPercent,
      percent: originalPercent,
    );

    // Non tentiamo di calibrare mercati rimborsabili o non-binari senza
    // un modello di apprendimento dedicato alle rispettive liquidazioni.
    final normalized = market.trim().toUpperCase();
    if (session == null ||
        !hasRealOdd ||
        originalPercent < 0 ||
        originalPercent > 100 ||
        fixtureId <= 0 ||
        normalized == 'COMBO CHANCE' ||
        normalized.startsWith('DNB ') ||
        normalized.startsWith('HCP ASIA ') ||
        normalized.startsWith('HCP EURO ')) {
      return original;
    }

    try {
      final calibrated = session.evaluate(
        market: market,
        originalPercent: originalPercent,
        fixtureId: fixtureId,
      );
      return SmartBetSharedLearningProbability(
        originalPercent: originalPercent,
        percent: calibrated.percent,
        samples: calibrated.applied ? calibrated.historicalSamples : 0,
      );
    } catch (_) {
      return original;
    }
  }
}
