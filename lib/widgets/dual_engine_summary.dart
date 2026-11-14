import 'package:flutter/material.dart';

import '../services/dual_engine_analysis_service.dart';
import '../services/goalvdline_market_relation_service.dart';

class DualEngineSummary extends StatelessWidget {
  final DualEngineAnalysis analysis;

  const DualEngineSummary({super.key, required this.analysis});

  Color _statusColor() {
    switch (analysis.comparison.status) {
      case DualEngineAgreement.agree:
        return Colors.greenAccent;

      case DualEngineAgreement.partial:
        return Colors.amberAccent;

      case DualEngineAgreement.diverge:
        return Colors.redAccent;

      case DualEngineAgreement.noSelection:
        return Colors.blueGrey;

      case DualEngineAgreement.unavailable:
        return Colors.white54;
    }
  }

  IconData _statusIcon() {
    switch (analysis.comparison.status) {
      case DualEngineAgreement.agree:
        return Icons.check_circle_outline;

      case DualEngineAgreement.partial:
        return Icons.compare_arrows;

      case DualEngineAgreement.diverge:
        return Icons.call_split;

      case DualEngineAgreement.noSelection:
        return Icons.remove_circle_outline;

      case DualEngineAgreement.unavailable:
        return Icons.info_outline;
    }
  }

  String _percent(double? value) {
    if (value == null) {
      return 'N/D';
    }

    return '${(value.clamp(0.0, 1.0) * 100).round()}%';
  }

  Widget _engineBox({
    required String title,
    required String market,
    required double? probability,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              market,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: market.startsWith('HANDICAP EUROPEO') ? 12 : 15,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _percent(probability),
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comparison = analysis.comparison;

    // P19B2B — preview statistica separata dal confronto verificato.
    final previewMarket = comparison.statisticalSmartBetMarket;
    final previewProbability = comparison.statisticalSmartBetProbability;

    final hasStatisticalPreview =
        comparison.status == DualEngineAgreement.unavailable &&
        previewMarket != null &&
        previewProbability != null;

    final sameStatisticalMarket =
        previewMarket != null &&
        dualEngineMarketLabel(previewMarket) ==
            dualEngineMarketLabel(comparison.diegoMarket);

    // P19B2C - raffronto logico tra mercati dei due motori.
    final reading = GoalVdLineMarketRelationService.compare(
      goalVdLineMarket: hasStatisticalPreview
          ? previewMarket
          : comparison.smartBetMarket,
      diegoMarket: comparison.diegoMarket,
    );

    final firstProbability = hasStatisticalPreview
        ? previewProbability
        : comparison.smartBetProbability;
    final secondProbability = comparison.diegoProbability;

    final probabilityGap = firstProbability != null && secondProbability != null
        ? (firstProbability - secondProbability).abs() * 100
        : null;

    final diego = analysis.diego;

    final statusColor = _statusColor();

    final diegoMeta = <String>[];

    if (comparison.diegoMarketConfidence != null) {
      diegoMeta.add(
        'Confidence mercato '
        '${comparison.diegoMarketConfidence}/100',
      );
    }

    final classification = comparison.diegoClassification;

    if (classification != null && classification.isNotEmpty) {
      diegoMeta.add(classification);
    }

    if (comparison.diegoOdd != null) {
      diegoMeta.add(
        'Quota '
        '${comparison.diegoOdd!.toStringAsFixed(2)}',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // P19B2D - titolo e stato su righe distinte, senza sovrapposizioni.
          Row(
            children: [
              Icon(_statusIcon(), color: statusColor, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'RAFFRONTO TRA LE DUE IA',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            hasStatisticalPreview
                ? 'AUDITOR SPORTIVO NON ESEGUITO'
                : comparison.label,
            style: TextStyle(
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 11),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _engineBox(
                title: hasStatisticalPreview ? 'GOALVDLINE' : 'SMARTBET',
                market: GoalVdLineMarketRelationService.displayMarket(
                  dualEngineMarketLabel(
                    hasStatisticalPreview
                        ? previewMarket
                        : comparison.smartBetMarket,
                  ),
                ),
                probability: hasStatisticalPreview
                    ? previewProbability
                    : comparison.smartBetProbability,
                color: const Color(0xFF00C853),
              ),
              const SizedBox(width: 8),
              _engineBox(
                title: comparison.status == DualEngineAgreement.noSelection ||
                        comparison.diegoClassification == 'STATISTICAL ONLY'
                    ? 'DIEGO AI • LETTURA'
                    : 'DIEGO AI',
                market: GoalVdLineMarketRelationService.displayMarket(
                  dualEngineMarketLabel(comparison.diegoMarket),
                ),
                probability: comparison.diegoProbability,
                color: Colors.cyanAccent,
              ),
            ],
          ),

          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RELAZIONE LOGICA: ${reading.title}',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  reading.explanation,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                if (reading.kind == GoalVdLineMarketRelationKind.same &&
                    probabilityGap != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Differenza fra le stime: '
                    '${probabilityGap.toStringAsFixed(1)} punti percentuali.',
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Raffronto logico dei mercati, non verifica '
                  'indipendente delle probabilità o dell’Auditor.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          if (diegoMeta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'DiegoAI • '
              '${diegoMeta.join(' • ')}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],

          if (diego != null) ...[
            const SizedBox(height: 5),
            Text(
              'Base 1X2 Diego • '
              '1 ${_percent(diego.homeProbability)}  '
              'X ${_percent(diego.drawProbability)}  '
              '2 ${_percent(diego.awayProbability)}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9.5,
                height: 1.35,
              ),
            ),
            if (hasStatisticalPreview && previewMarket == 'X') ...[
              const SizedBox(height: 6),
              Text(
                'Stima X (solo statistica) • '
                'GoalVdLine ${_percent(previewProbability)} · '
                'Diego AI ${_percent(diego.drawProbability)}. '
                'Non indica che Diego abbia scelto X né '
                'che esista una quota utilizzabile.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ],

          const SizedBox(height: 8),

          Text(
            hasStatisticalPreview
                ? (comparison.diegoMarket == 'N/D'
                      ? 'Lettura GoalVdLine disponibile. '
                            'Diego AI non disponibile. '
                            'Auditor sportivo SmartBet non eseguito.'
                      : sameStatisticalMarket
                      ? 'Stesso mercato statistico. '
                            'Auditor sportivo SmartBet non eseguito: '
                            'non è una conferma verificata.'
                      : 'Mercati statistici differenti. '
                            'Auditor sportivo SmartBet non eseguito: '
                            'confronto non verificato.')
                : comparison.description,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
