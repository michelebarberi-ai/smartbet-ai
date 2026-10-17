import 'package:flutter/material.dart';

import '../services/dual_engine_analysis_service.dart';

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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 15,
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
          Row(
            children: [
              Icon(_statusIcon(), color: statusColor, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  comparison.status == DualEngineAgreement.noSelection
                      ? 'LETTURA INDIPENDENTE DEI MOTORI'
                      : 'SCELTA INDIPENDENTE DEI MOTORI',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.35,
                  ),
                ),
              ),
              Text(
                comparison.label,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 11),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _engineBox(
                title: 'SMARTBET',
                market: dualEngineMarketLabel(comparison.smartBetMarket),
                probability: comparison.smartBetProbability,
                color: const Color(0xFF00C853),
              ),
              const SizedBox(width: 8),
              _engineBox(
                title: comparison.status == DualEngineAgreement.noSelection
                    ? 'DIEGO AI • LETTURA'
                    : 'DIEGO AI',
                market: dualEngineMarketLabel(comparison.diegoMarket),
                probability: comparison.diegoProbability,
                color: Colors.cyanAccent,
              ),
            ],
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
          ],

          const SizedBox(height: 8),

          Text(
            comparison.description,
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
