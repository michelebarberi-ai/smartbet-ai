import '../models/analysis_result.dart';
import 'smartbet_match_simulation_service.dart';

/// Valutazione della X, indipendente da quote e mercati bookmaker.
/// `priority` e' un'etichetta operativa, non una promessa di successo.
class SmartBetXPremiumAssessment {
  final int fixtureId;
  final double? simulatedDraw;
  final double? nativeDraw;
  final double? dataQuality;
  final Map<String, double> alternatives;
  final bool priority;
  final String reason;

  const SmartBetXPremiumAssessment({
    required this.fixtureId,
    required this.simulatedDraw,
    required this.nativeDraw,
    required this.dataQuality,
    required this.alternatives,
    required this.priority,
    required this.reason,
  });

  bool get hasSimulation => simulatedDraw != null;

  static SmartBetXPremiumAssessment unavailable({
    required int fixtureId,
    String reason = 'Analisi non disponibile: riprova manualmente.',
  }) => SmartBetXPremiumAssessment(
    fixtureId: fixtureId,
    simulatedDraw: null,
    nativeDraw: null,
    dataQuality: null,
    alternatives: const <String, double>{},
    priority: false,
    reason: reason,
  );
}

/// Valuta soltanto le fixture passate dal chiamante; non legge dati esterni,
/// non interroga API e non utilizza quote.
class SmartBetXPremiumService {
  final SmartBetMatchSimulationService simulator;

  const SmartBetXPremiumService({
    this.simulator = const SmartBetMatchSimulationService(),
  });

  static const double minimumDrawProbability = 0.30;
  static const double minimumDataQuality = 0.60;

  SmartBetXPremiumAssessment assess({
    required int fixtureId,
    required AnalysisResult analysis,
  }) {
    if (fixtureId <= 0) throw ArgumentError.value(fixtureId, 'fixtureId');

    final nativeTotal =
        analysis.homeProbability +
        analysis.drawProbability +
        analysis.awayProbability;
    final nativeDraw =
        nativeTotal >= 98 &&
            nativeTotal <= 102 &&
            analysis.drawProbability >= 0 &&
            analysis.drawProbability <= 100
        ? analysis.drawProbability / 100.0
        : null;

    final qualityValue = analysis.dataConfidence;
    // 0 significa "qualita non disponibile" nei risultati legacy:
    // non lo trasformiamo in una falsa misura di qualita.
    final quality = qualityValue > 0 && qualityValue <= 100
        ? qualityValue / 100.0
        : null;

    final h = analysis.expectedHomeGoals;
    final a = analysis.expectedAwayGoals;
    if (!h.isFinite || !a.isFinite || h <= 0 || a <= 0 || h > 6 || a > 6) {
      return SmartBetXPremiumAssessment(
        fixtureId: fixtureId,
        simulatedDraw: null,
        nativeDraw: nativeDraw,
        dataQuality: quality,
        alternatives: const <String, double>{},
        priority: false,
        reason: 'Gol attesi assenti o non validi: X non simulabile.',
      );
    }

    final simulation = simulator.simulate(
      SmartBetMatchSimulationInput(
        expectedHomeGoals: h,
        expectedAwayGoals: a,
        dataQuality: quality ?? 0.0,
      ),
    );
    final draw = simulation.draw;
    final priority =
        draw >= minimumDrawProbability &&
        quality != null &&
        quality >= minimumDataQuality;

    final reason = quality == null
        ? 'Qualita dati non misurata: valutazione provvisoria.'
        : quality < minimumDataQuality
        ? 'Qualita dati sotto la soglia operativa.'
        : draw < minimumDrawProbability
        ? 'Probabilita X inferiore alla soglia operativa.'
        : 'Probabilita X e qualita dati sopra le soglie.';

    // Sono alternative statistiche, NON consigli di puntata: senza quote
    // non possiamo stimare il valore economico. Usano la stessa distribuzione.
    const options = <String>[
      '1X',
      'X2',
      '12',
      'GOAL',
      'NO GOAL',
      'OVER 1.5',
      'UNDER 2.5',
      'UNDER 3.5',
      'UNDER 4.5',
    ];
    final sorted =
        <MapEntry<String, double>>[
          for (final key in options)
            MapEntry(key, simulation.probabilityFor(key)),
        ]..sort((a, b) {
          final score = b.value.compareTo(a.value);
          return score != 0 ? score : a.key.compareTo(b.key);
        });

    return SmartBetXPremiumAssessment(
      fixtureId: fixtureId,
      simulatedDraw: draw,
      nativeDraw: nativeDraw,
      dataQuality: quality,
      alternatives: Map.unmodifiable(Map.fromEntries(sorted.take(3))),
      priority: priority,
      reason: reason,
    );
  }

  /// Non elimina nessuna fixture. Le non simulabili restano in coda.
  List<SmartBetXPremiumAssessment> rank(
    Iterable<SmartBetXPremiumAssessment> assessments,
  ) {
    final items = assessments.toList();
    if (items.map((item) => item.fixtureId).toSet().length != items.length) {
      throw ArgumentError('Fixture duplicate in X Premium.');
    }
    items.sort((a, b) {
      if (a.priority != b.priority) return a.priority ? -1 : 1;
      final probA = a.simulatedDraw;
      final probB = b.simulatedDraw;
      if (probA == null && probB != null) return 1;
      if (probA != null && probB == null) return -1;
      final p = (probB ?? -1).compareTo(probA ?? -1);
      if (p != 0) return p;
      final q = (b.dataQuality ?? -1).compareTo(a.dataQuality ?? -1);
      return q != 0 ? q : a.fixtureId.compareTo(b.fixtureId);
    });
    return List.unmodifiable(items);
  }
}
