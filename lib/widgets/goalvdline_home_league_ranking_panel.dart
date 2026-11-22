import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_league_market_reliability_service.dart';

/// Read-only Home view of the same prospective, settled evidence used by
/// the detailed league/market reliability screen. Never affects AI picks.
class GoalVdLineHomeLeagueRanking {
  final List<SmartBetLeagueMarketReliability> established;
  final List<SmartBetLeagueMarketReliability> observing;

  const GoalVdLineHomeLeagueRanking({
    required this.established,
    required this.observing,
  });

  static const int minimumObservingPredictions = 10;
  static const int minimumObservingMatchDays = 3;

  factory GoalVdLineHomeLeagueRanking.fromRecords(
    Iterable<SmartBetAnalysisRecord> records, {
    DateTime? asOf,
  }) {
    final report = const SmartBetLeagueMarketReliabilityService().evaluate(
      records: records.where((r) =>
          r.actualHomeGoals != null && r.actualAwayGoals != null),
      asOf: (asOf ?? DateTime.now()).toUtc(),
    );

    bool supportedEngine(SmartBetLeagueMarketReliability item) =>
        item.engine == SmartBetAnalysisEngine.smartBet ||
        item.engine == SmartBetAnalysisEngine.diego;

    bool qualified(SmartBetLeagueMarketReliability item) =>
        item.sampleSize >=
            SmartBetLeagueMarketReliabilityService.minimumExploratoryFixtures &&
        item.distinctMatchDays >=
            SmartBetLeagueMarketReliabilityService.minimumDistinctMatchDays;

    List<SmartBetLeagueMarketReliability> bestPerLeague(
      Iterable<SmartBetLeagueMarketReliability> candidates,
    ) {
      final ordered = candidates.toList()
        ..sort((a, b) {
          final confidence =
              b.wilsonLower95Percent.compareTo(a.wilsonLower95Percent);
          if (confidence != 0) return confidence;
          final n = b.sampleSize.compareTo(a.sampleSize);
          if (n != 0) return n;
          final country = a.country.compareTo(b.country);
          if (country != 0) return country;
          final league = a.league.compareTo(b.league);
          if (league != 0) return league;
          final engine = a.engine.index.compareTo(b.engine.index);
          if (engine != 0) return engine;
          return a.market.compareTo(b.market);
        });
      final seen = <String>{};
      return List.unmodifiable(ordered.where((item) =>
          seen.add('${item.country.toLowerCase()}|${item.league.toLowerCase()}')));
    }

    final valid = report.segments.where(supportedEngine).toList();
    final established = bestPerLeague(valid.where(qualified));
    final establishedKeys = established
        .map((item) =>
            '${item.country.toLowerCase()}|${item.league.toLowerCase()}')
        .toSet();
    final observing = bestPerLeague(valid.where((item) =>
        !qualified(item) &&
        item.sampleSize >= minimumObservingPredictions &&
        item.distinctMatchDays >= minimumObservingMatchDays &&
        !establishedKeys.contains(
          '${item.country.toLowerCase()}|${item.league.toLowerCase()}',
        )));

    return GoalVdLineHomeLeagueRanking(
      established: established,
      observing: observing,
    );
  }
}

/// Three leading leagues are visible directly on Home; detailed breakdown
/// and extra leagues are optional. No network, extra analysis or background job.
class GoalVdLineHomeLeagueRankingPanel extends StatelessWidget {
  const GoalVdLineHomeLeagueRankingPanel({
    super.key,
    required this.records,
    this.asOf,
  });

  final List<SmartBetAnalysisRecord> records;
  final DateTime? asOf;

  String _engine(SmartBetAnalysisEngine engine) =>
      engine == SmartBetAnalysisEngine.diego ? 'Diego AI' : 'SmartBet';

  Widget _league(SmartBetLeagueMarketReliability item, int index) {
    return Padding(
      key: Key('b77-home-league-row-$index'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${index + 1}. ${item.league} · ${item.country}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.observedAccuracyPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFF69F0AE),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${_engine(item.engine)} · ${item.market} · '
            '${item.correct}/${item.sampleSize} corretti · '
            '${item.distinctMatchDays} giornate',
            style: const TextStyle(color: Colors.white60, fontSize: 10.5),
          ),
          Text(
            'Limite prudenziale 95%: '
            '${item.wilsonLower95Percent.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranking = GoalVdLineHomeLeagueRanking.fromRecords(
      records, asOf: asOf,
    );
    final hasEstablished = ranking.established.isNotEmpty;
    final visible = hasEstablished ? ranking.established : ranking.observing;
    final watchingOnly = !hasEstablished && ranking.observing.isNotEmpty;

    return Column(
      key: const Key('b77-home-league-ranking'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text(
          'Campionati più affidabili',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        if (hasEstablished)
          const Text(
            'Classifica storica per campionato, mercato e motore '
            '(almeno 50 esiti e 14 giornate).',
            style: TextStyle(color: Colors.white60, fontSize: 10.5),
          )
        else if (watchingOnly)
          const Text(
            'Prime osservazioni: campione ancora insufficiente '
            'per una classifica affidabile.',
            key: Key('b77-home-league-observing-warning'),
            style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
          )
        else
          const Text(
            'Nessun campionato con dati sufficienti per una classifica. '
            'Le prime osservazioni compariranno dopo 10 esiti '
            'e 3 giornate per lo stesso mercato e motore.',
            key: Key('b77-home-league-no-evidence'),
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
        for (var index = 0; index < visible.take(3).length; index++)
          _league(visible[index], index),
        if (visible.length > 3)
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              unselectedWidgetColor: Colors.white60,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Mostra altri campionati (${visible.length - 3})',
                style: const TextStyle(color: Color(0xFF95D5B2), fontSize: 11),
              ),
              children: [
                for (var index = 3; index < visible.length; index++)
                  _league(visible[index], index),
              ],
            ),
          ),
        const SizedBox(height: 7),
        const Text(
          'Ordine basato sul limite inferiore Wilson al 95%, '
          'non sulla sola percentuale. I mercati e i motori '
          'non vengono fusi. Storico locale prepartita, '
          'nessuna garanzia per le prossime partite.',
          style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.3),
        ),
      ],
    );
  }
}
