import 'dart:convert';
import 'dart:io';

import 'saved_prediction_store.dart';
import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_device_learning_preferences.dart';
import 'smartbet_learning_snapshot_store.dart';
import 'smartbet_scorer_learning_service.dart';
import 'smartbet_shadow_learning_store.dart';

/// Esporta esclusivamente record diagnostici esplicitamente selezionati.
/// Nessun dump di SharedPreferences, token, profilo personale o backend.
class SmartBetDiagnosticExportService {
  const SmartBetDiagnosticExportService();

  Future<File> generateFile() async {
    final history = SmartBetAnalysisHistoryStore.instance;
    final comparisons = SmartBetAnalysisComparisonStore.instance;
    final shadows = SmartBetShadowLearningStore.instance;
    final snapshots = SmartBetLearningSnapshotStore.instance;
    final scorers = SmartBetScorerLearningStore();
    final saved = SavedPredictionStore.instance;

    // Solo caricamento locale. Nessun resolver, recupero esiti, rete o scrittura
    // degli archivi esistenti. Se un archivio e' illeggibile, non esportiamo
    // un report parziale presentato come completo.
    await history.initialize();
    await comparisons.initialize();
    await shadows.initialize();
    await snapshots.initialize();
    await scorers.initialize();
    await saved.initialize();
    final consent = await const SmartBetDeviceLearningPreferences()
        .loadEnabled();

    final data = SmartBetDiagnosticPayloadBuilder.build(
      generatedAt: DateTime.now().toUtc(),
      learningEnabled: consent,
      markets: history.records.map((r) => r.toJson()).toList(),
      comparisons: comparisons.links.map((r) => r.toJson()).toList(),
      shadow: shadows.predictions.map((r) => r.toJson()).toList(),
      snapshots: snapshots.snapshots.map((r) => r.toJson()).toList(),
      scorers: scorers.records.map((r) => r.toJson()).toList(),
      savedPredictions: saved.items
          .map(
            (r) => <String, dynamic>{
              'fixtureId': r.fixtureId,
              'matchLabel': r.matchLabel,
              'league': r.league,
              'matchDate': r.matchDate.toUtc().toIso8601String(),
              'createdAt': r.createdAt.toUtc().toIso8601String(),
              'smartScore': r.smartScore,
              'homeProbability': r.homeProbability,
              'drawProbability': r.drawProbability,
              'awayProbability': r.awayProbability,
              'prediction': r.prediction,
              'valueBet': r.valueBet,
              'risk': r.risk,
              'shouldBet': r.shouldBet,
              'recommendedStakePercent': r.recommendedStakePercent,
              'stakeOutcome': r.stakeOutcome,
              'stakeOdd': r.stakeOdd,
              'stakeBookmaker': r.stakeBookmaker,
              'stakeRecommendation': r.stakeRecommendation,
            },
          )
          .toList(),
    );

    final dir = await Directory.systemTemp.createTemp('smartbet_diagnostic_');
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9A-Za-z]'),
      '_',
    );
    final file = File('${dir.path}/smartbet_diagnostica_$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file;
  }
}

/// Builder puro, testabile senza telefono, dati utente, rete o plugin nativi.
class SmartBetDiagnosticPayloadBuilder {
  const SmartBetDiagnosticPayloadBuilder._();

  static Map<String, dynamic> build({
    required DateTime generatedAt,
    required bool learningEnabled,
    required List<Map<String, dynamic>> markets,
    required List<Map<String, dynamic>> comparisons,
    required List<Map<String, dynamic>> shadow,
    required List<Map<String, dynamic>> snapshots,
    required List<Map<String, dynamic>> scorers,
    required List<Map<String, dynamic>> savedPredictions,
  }) {
    final resolved = markets.where(
      (r) =>
          r['prospectiveEligible'] == true &&
          (r['status'] == 'correct' || r['status'] == 'wrong'),
    );

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in resolved) {
      if (r['engine'] != 'smartBet') continue;
      final market = (r['market'] ?? '').toString();
      grouped.putIfAbsent(market, () => []).add(r);
    }
    final byMarket = <Map<String, dynamic>>[];
    for (final entry in grouped.entries) {
      final rows = entry.value;
      final withProb = rows
          .where(
            (r) =>
                r['probability'] is num &&
                (r['probability'] as num).toDouble().isFinite &&
                (r['probability'] as num) >= 0 &&
                (r['probability'] as num) <= 1,
          )
          .toList();
      final correct = rows.where((r) => r['status'] == 'correct').length;
      double? averageProbability;
      double? brier;
      if (withProb.isNotEmpty) {
        averageProbability =
            withProb.fold<double>(
              0.0,
              (s, r) => s + (r['probability'] as num).toDouble(),
            ) /
            withProb.length;
        brier =
            withProb.fold<double>(0.0, (s, r) {
              final p = (r['probability'] as num).toDouble();
              final actual = r['status'] == 'correct' ? 1.0 : 0.0;
              return s + (p - actual) * (p - actual);
            }) /
            withProb.length;
      }
      byMarket.add({
        'market': entry.key,
        'verified': rows.length,
        'correct': correct,
        'wrong': rows.length - correct,
        'observedFrequency': correct / rows.length,
        'averageOriginalProbability': averageProbability,
        'brierOriginal': brier,
        'probabilitySampleSize': withProb.length,
      });
    }
    byMarket.sort(
      (a, b) => (b['verified'] as int).compareTo(a['verified'] as int),
    );

    final validScorers = scorers
        .where((r) => r['resolvedAt'] != null && r['actualGoals'] is num)
        .toList();
    final scorersScored = validScorers
        .where((r) => (r['actualGoals'] as num) > 0)
        .length;

    final marketKeys = markets
        .map((r) => '${r['engine']}|${r['fixtureId']}|${r['market']}')
        .toList();
    final duplicateKeys = marketKeys.length - marketKeys.toSet().length;

    // Brier shadow: solo coppie nate prima del risultato, abbinate allo
    // stesso evento. Non confondere questo backtest con prove di rendimento.
    final historyByKey = <String, Map<String, dynamic>>{
      for (final r in markets)
        '${r['engine']}|${r['fixtureId']}|${r['market']}': r,
    };
    var shadowPairs = 0;
    var originalBrierTotal = 0.0;
    var calibratedBrierTotal = 0.0;
    for (final s in shadow) {
      final h = historyByKey[s['key']?.toString() ?? ''];
      if (h == null ||
          h['prospectiveEligible'] != true ||
          (h['status'] != 'correct' && h['status'] != 'wrong') ||
          s['originalProbability'] is! num ||
          s['calibratedProbability'] is! num)
        continue;
      final raw = (s['originalProbability'] as num).toDouble();
      final cal = (s['calibratedProbability'] as num).toDouble();
      if (!raw.isFinite ||
          !cal.isFinite ||
          raw < 0 ||
          raw > 1 ||
          cal < 0 ||
          cal > 1)
        continue;
      final actual = h['status'] == 'correct' ? 1.0 : 0.0;
      originalBrierTotal += (raw - actual) * (raw - actual);
      calibratedBrierTotal += (cal - actual) * (cal - actual);
      shadowPairs++;
    }

    return <String, dynamic>{
      'schema': 'smartbet-diagnostica-v1',
      'generatedAtUtc': generatedAt.toUtc().toIso8601String(),
      'learningEnabledOnThisDevice': learningEnabled,
      'privacy': {
        'contains':
            'Nomi squadre/giocatori, ID partite, pronostici, quote, '
            'probabilita e risultati verificati',
        'excludes':
            'Password, token, chiavi API, dati account, '
            'archivi generici delle preferenze',
        'transfer': 'Solo condivisione volontaria tramite foglio iOS',
      },
      'limitations': [
        'Gli archivi storici non contengono necessariamente tutti i fattori '
            'pre-partita usati dal modello (formazioni, assenze, forma).',
        'Non tutte le analisi visualizzate sono necessariamente state '
            'registrate nello storico.',
        'Le probabilita shadow non dimostrano che la medesima correzione '
            'sia stata applicata in tempo reale.',
        'Brier Score inferiore indica una calibrazione migliore, '
            'ma non dimostra da solo redditivita o affidabilita futura.',
      ],
      'summary': {
        'marketPredictions': markets.length,
        'marketProspectiveVerified': resolved.length,
        'marketProspectiveCorrect': resolved
            .where((r) => r['status'] == 'correct')
            .length,
        'marketProspectiveWrong': resolved
            .where((r) => r['status'] == 'wrong')
            .length,
        'scorerPredictions': scorers.length,
        'scorerVerified': validScorers.length,
        'scorerScored': scorersScored,
        'shadowSnapshots': shadow.length,
        'shadowMatchedVerified': shadowPairs,
        'savedPredictions': savedPredictions.length,
        'missingOriginalProbability': markets
            .where((r) => r['probability'] == null)
            .length,
        'missingQuotedOdds': markets
            .where((r) => r['quotedOdd'] == null)
            .length,
        'nonProspectiveMarketRecords': markets
            .where((r) => r['prospectiveEligible'] != true)
            .length,
        'duplicateHistoryKeys': duplicateKeys,
      },
      'shadowBrierOnMatchedVerified': {
        'sampleSize': shadowPairs,
        'original': shadowPairs == 0 ? null : originalBrierTotal / shadowPairs,
        'calibrated': shadowPairs == 0
            ? null
            : calibratedBrierTotal / shadowPairs,
        'method': 'Stessa previsione e risultato; sola diagnostica shadow',
      },
      'byMarket': byMarket,
      'data': {
        'analysisHistory': markets,
        'comparisonLinks': comparisons,
        'shadowCalibrationPredictions': shadow,
        'learningSnapshots': snapshots,
        'scorerHistory': scorers,
        'savedPredictions': savedPredictions,
      },
    };
  }
}
