import 'package:flutter/material.dart';

import '../services/goalvdline_coupon_risk_service.dart';

/// Does not alter the number of events, markets, or odds in a coupon.
class GoalVdLineCouponRiskNotice extends StatelessWidget {
  final GoalVdLineCouponRiskReport report;
  final bool compact;

  const GoalVdLineCouponRiskNotice({
    super.key,
    required this.report,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (report.events < 2) return const SizedBox.shrink();
    final attention = report.requiresAttention;
    final themeColor = attention
        ? Colors.orangeAccent : Colors.white60;

    return Container(
      key: const Key('b78-coupon-risk-notice'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: attention ? Colors.orangeAccent.withValues(alpha: 0.45)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: themeColor, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Rischio multipla · ${report.events} eventi',
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 12, fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (report.longMultiple)
            Text(
              report.veryLongMultiple
                  ? 'Multipla molto lunga: anche eventi apparentemente '
                    'facili possono far fallire l’intera schedina.'
                  : 'Multipla lunga: aggiungere eventi aumenta le '
                    'possibilità che almeno una scelta sia errata.',
              style: const TextStyle(
                color: Colors.orangeAccent, fontSize: 11,
              ),
            ),
          if (report.hasRepeatRisk)
            Text(
              '${report.repeatedFixtureSelections} selezioni riferite '
              'a partite già presenti: gli esiti non sono indipendenti.',
              style: const TextStyle(
                color: Colors.orangeAccent, fontSize: 11,
              ),
            ),
          if (report.independenceScenarioPercent != null)
            Text(
              'Solo scenario teorico con stime esatte ed eventi '
              'indipendenti: ${report.independenceScenarioPercent!.toStringAsFixed(1)}%.',
              key: const Key('b78-coupon-independence-scenario'),
              style: const TextStyle(
                color: Colors.white70, fontSize: 11,
              ),
            )
          else
            const Text(
              'Scenario matematico non calcolabile: probabilità '
              'mancanti/non valide o eventi ripetuti.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (report.lowOrUnknownOdds > 0)
            Text(
              '${report.lowOrUnknownOdds} selezioni con quota mancante, '
              'non valida o non superiore a 1,20.',
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          const Text(
            'Non è una probabilità reale né una garanzia: '
            'le stime AI possono essere sovrastimate o correlate. '
            'Non aggiungere partite soltanto per aumentare la quota.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
