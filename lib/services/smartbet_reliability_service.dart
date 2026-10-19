import '../models/analysis_result.dart';

/// Reliability sportiva di uno specifico mercato.
///
/// IMPORTANTE:
/// - non usa quote;
/// - non usa probabilità implicite bookmaker;
/// - non usa edge;
/// - non usa expected value.
///
/// Probability e Reliability restano due concetti distinti.
class SmartBetReliabilityService {
  const SmartBetReliabilityService._();

  static int? score({
    required AnalysisResult analysis,
    required String market,
    required int probability,
  }) {
    final dataConfidence = analysis.dataConfidence.clamp(0, 100);

    // Non inventiamo qualità dati quando non è disponibile.
    if (dataConfidence <= 0 || probability <= 0) {
      return null;
    }

    final key = market.trim().toUpperCase();

    // ============================================================
    // 1X2
    // ============================================================
    //
    // La reliability deve essere specifica del singolo esito.
    //
    // Usiamo la stessa struttura validata nel Match Engine:
    // - 35% qualità dati
    // - 25% chiarezza della probabilità
    // - 40% separazione dall'alternativa più forte
    //
    // Nessuna quota entra nel calcolo.
    if (key == '1' || key == 'X' || key == '2') {
      final selectedProbability = probability / 100.0;

      final otherProbabilities = switch (key) {
        '1' => <double>[
          analysis.drawProbability / 100.0,
          analysis.awayProbability / 100.0,
        ],
        'X' => <double>[
          analysis.homeProbability / 100.0,
          analysis.awayProbability / 100.0,
        ],
        _ => <double>[
          analysis.homeProbability / 100.0,
          analysis.drawProbability / 100.0,
        ],
      };

      final strongestAlternative =
          otherProbabilities[0] >= otherProbabilities[1]
          ? otherProbabilities[0]
          : otherProbabilities[1];

      final probabilityClarity =
          (((selectedProbability - (1.0 / 3.0)) / (2.0 / 3.0)) * 100.0)
              .clamp(0.0, 100.0)
              .toDouble();

      final separationClarity =
          (((selectedProbability - strongestAlternative) / 0.40) * 100.0)
              .clamp(0.0, 100.0)
              .toDouble();

      final reliability =
          (dataConfidence * 0.35) +
          (probabilityClarity * 0.25) +
          (separationClarity * 0.40);

      return reliability.round().clamp(1, 95);
    }

    // ============================================================
    // MERCATI BINARI
    // ============================================================
    //
    // 50% = nessun vantaggio predittivo sul mercato selezionato.
    //
    // Sopra il 50% la chiarezza cresce progressivamente.
    // Sotto il 50% NON premiamo la distanza dal 50%:
    // significherebbe infatti essere confidenti nel contrario
    // del mercato che stiamo valutando.
    final normalizedProbability = probability.clamp(0, 100).toDouble();

    final marketClarity = (((normalizedProbability - 50.0) / 50.0) * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    // Formula già utilizzata nel progetto per la market confidence:
    //
    // 35% qualità dati
    // 65% chiarezza dello specifico mercato
    final reliability = (dataConfidence * 0.35) + (marketClarity * 0.65);

    return reliability.round().clamp(1, 95);
  }
}
