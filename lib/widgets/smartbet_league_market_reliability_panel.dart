import 'package:flutter/material.dart';
import '../services/smartbet_league_market_reliability_service.dart';
import '../services/smartbet_league_market_shadow_service.dart';

/// Local evidence only: does not resolve fixtures or modify the AI.
class SmartBetLeagueMarketReliabilityPanel extends StatelessWidget {
  const SmartBetLeagueMarketReliabilityPanel({
    super.key, required this.report, this.shadowReport,
  });

  final SmartBetLeagueMarketReliabilityReport report;
  final SmartBetLeagueMarketShadowReport? shadowReport;

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
          if (shadowReport != null) ...[
            const SizedBox(height: 12),
            const Text('P21W.4 · Validazione SHADOW prospettica',
              style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Replay offline: per ogni pronostico usa solo risultati già noti '
              'prima della previsione. Nessuna correzione live.'),
            if (!shadowReport!.segments.any((s) => s.evaluatedFixtures > 0))
              const Padding(
                key: Key('p21w4-no-validation'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Campione futuro indipendente insufficiente: confronto non disponibile.'),
              ),
            ...shadowReport!.segments.where((s) => s.evaluatedFixtures > 0).take(8).map((s) {
              final engine = s.engine.name == 'diego'
                  ? 'Diego AI' : 'SmartBet AI';
              final original = s.originalBrier!.toStringAsFixed(4);
              final shadow = s.shadowBrier!.toStringAsFixed(4);
              final improvement = s.brierImprovement!.toStringAsFixed(4);
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s.country} · ${s.league} · ${s.market} · $engine',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Verifica: ${s.evaluatedFixtures} incontri su '
                      '${s.distinctValidationDays} giornate'),
                    Text('Brier originale $original · SHADOW $shadow · differenza $improvement'),
                    Text(s.warrantsFurtherResearch
                      ? 'Miglioramento esplorativo: richiede ulteriore validazione'
                      : 'Nessuna evidenza sufficiente per promuovere correzioni'),
                  ],
                ),
              );
            }),
          ],
          const Text('SHADOW: questi dati non cambiano il pronostico principale.',
            style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
