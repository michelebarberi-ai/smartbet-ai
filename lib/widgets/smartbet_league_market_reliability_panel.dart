import 'package:flutter/material.dart';
import '../services/smartbet_league_market_reliability_service.dart';

/// Local evidence only: does not resolve fixtures or modify the AI.
class SmartBetLeagueMarketReliabilityPanel extends StatelessWidget {
  const SmartBetLeagueMarketReliabilityPanel({
    super.key, required this.report,
  });

  final SmartBetLeagueMarketReliabilityReport report;

  String _level(SmartBetLeagueMarketEvidenceLevel level) => switch (level) {
    SmartBetLeagueMarketEvidenceLevel.insufficient => 'Dati insufficienti',
    SmartBetLeagueMarketEvidenceLevel.exploratory => 'Campione esplorativo',
    SmartBetLeagueMarketEvidenceLevel.signal => 'Segnale da validare',
    SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate =>
      'Candidato SHADOW, non attivo',
  };

  @override
  Widget build(BuildContext context) {
    final segments = report.segments;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: const Key('p21w-reliability'),
        initiallyExpanded: false,
        title: const Text('Affidabilità per campionato e mercato',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        subtitle: Text('${report.uniqueEligibleRecords} pronostici verificati · ${segments.length} gruppi'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text('Solo pronostici prepartita realmente risolti. '
            'Frequenze storiche, non probabilità garantite. '
            'Nessuna modifica a pronostici o schedine.'),
          const SizedBox(height: 8),
          Text('Esclusi: ${report.skippedUnsafeRecords} · Duplicati: '
            '${report.duplicateRecords} · Conflitti: ${report.conflictingFixtureMarkets}'),
          if (segments.isEmpty)
            const Padding(
              key: Key('p21w-no-results'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nessuna evidenza utilizzabile: affidabilità non determinabile.'),
            ),
          ...segments.take(12).map((s) {
            final engine = s.engine.name == 'diego' ? 'Diego AI' : 'SmartBet AI';
            final accuracy = s.observedAccuracyPercent.toStringAsFixed(1);
            final lower = s.wilsonLower95Percent.toStringAsFixed(1);
            final upper = s.wilsonUpper95Percent.toStringAsFixed(1);
            final predicted = s.averagePredictedPercent == null
              ? 'N/D' : '${s.averagePredictedPercent!.toStringAsFixed(1)}%';
            final gap = s.calibrationGapPoints == null
              ? 'N/D' : '${s.calibrationGapPoints!.toStringAsFixed(1)} punti';
            final brier = s.brierScore?.toStringAsFixed(4) ?? 'N/D';
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.country} · ${s.league} · ${s.market} · $engine',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Successi osservati: ${s.correct}/${s.sampleSize} ($accuracy%)'),
                  Text('Intervallo 95%: $lower%–$upper%'),
                  Text('Probabilità originale media: $predicted · scostamento: $gap'),
                  Text('Brier: $brier · ${s.distinctMatchDays} giornate'),
                  Text(_level(s.evidenceLevel)),
                  if (s.evidenceLevel == SmartBetLeagueMarketEvidenceLevel.insufficient)
                    const Text('Affidabilità non determinabile con questo campione.'),
                  const Divider(),
                ],
              ),
            );
          }),
          if (segments.length > 12)
            Text('Mostrati 12 su ${segments.length} gruppi, ordinati per numerosità.'),
          const Text('SHADOW: questi dati non cambiano il pronostico principale.',
            style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
