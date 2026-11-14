import 'package:flutter/material.dart';

import '../models/match_model.dart';
import '../services/goalvdline_competition_order.dart';
import '../services/goalvdline_market_relation_service.dart';
import '../services/goalvdline_three_coupon_system.dart';

/// Solo presentazione: le tre varianti sono gia' state validate e non
/// vengono mai ricalcolate o modificate da questa schermata.
class GoalVdLineThreeCouponViewer extends StatefulWidget {
  const GoalVdLineThreeCouponViewer({
    super.key,
    required this.coupons,
    required this.matchesById,
    required this.onShareAll,
  });

  final List<List<GoalVdLineSystemSelection>> coupons;
  final Map<int, MatchModel> matchesById;
  final VoidCallback onShareAll;

  @override
  State<GoalVdLineThreeCouponViewer> createState() =>
      _GoalVdLineThreeCouponViewerState();
}

class _GoalVdLineThreeCouponViewerState
    extends State<GoalVdLineThreeCouponViewer> {
  static const _names = ['ORIGINALE', 'ALTERNATIVA 1', 'ALTERNATIVA 2'];
  int _selectedIndex = 0;

  Widget _couponSummary(List<GoalVdLineSystemSelection> coupon) {
    final totalOdd = coupon.fold<double>(1.0, (value, pick) => value * pick.odd);
    final meanProbability = coupon.isEmpty
        ? 0.0
        : coupon.fold<int>(0, (sum, pick) => sum + pick.probability) /
            coupon.length;
    final originalMarket = <int, String>{
      for (final pick in widget.coupons.first) pick.fixtureId: pick.market,
    };
    final changed = coupon.where((pick) =>
        originalMarket[pick.fixtureId] != pick.market).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _names[_selectedIndex],
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metric('PARTITE', '${coupon.length}'),
              ),
              Expanded(
                child: _metric('QUOTA TOTALE', totalOdd.toStringAsFixed(2)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Probabilità media dei mercati: '
            '${meanProbability.toStringAsFixed(1)}% · '
            '${changed == 1 ? '1 mercato cambiato' : '$changed mercati cambiati'}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sono stime per singola partita, non una probabilità '
            'garantita dell’intera schedina. Quote soggette a variazioni.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );

  Widget _matchCard(GoalVdLineSystemSelection pick, int position) {
    final match = widget.matchesById[pick.fixtureId];
    final originalMarkets = <int, String>{
      for (final base in widget.coupons.first) base.fixtureId: base.market,
    };
    final originalMarket = originalMarkets[pick.fixtureId];
    final changed = originalMarket != null && originalMarket != pick.market;
    final name = match == null
        ? 'Partita ${pick.fixtureId}'
        : '${match.homeTeam} - ${match.awayTeam}';

    return Container(
      key: ValueKey('b50-three-coupon-pick-${pick.fixtureId}'),
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: changed
              ? Colors.orangeAccent.withValues(alpha: 0.45)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$position. $name',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            match == null
                ? 'Campionato non disponibile'
                : GoalVdLineCompetitionOrder.matchCompetitionLabel(
                    match.country, match.league),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (changed) ...[
            const SizedBox(height: 8),
            Text(
              'MERCATO ALTERNATIVO · originale: '
              '${GoalVdLineMarketRelationService.displayMarket(originalMarket!)}',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRONOSTICO IN SCHEDINA',
                      style: TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      GoalVdLineMarketRelationService.displayMarket(
                        pick.market,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'PROBABILITÀ',
                    style: TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pick.probability}%',
                    style: const TextStyle(
                      color: Color(0xFF69F0AE),
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.show_chart,
                  color: Colors.orangeAccent,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Text(
                  '@ ${pick.odd.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pick.bookmaker.trim().isEmpty
                        ? 'Bookmaker non indicato'
                        : pick.bookmaker,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coupons.length != 3 || widget.coupons.any((c) => c.isEmpty)) {
      return const Center(child: Text('Tre schedine non disponibili.'));
    }
    final current = widget.coupons[_selectedIndex];
    return Column(
      children: [
        const SizedBox(height: 12),
        const Text(
          '3 SCHEDINE — STESSE PARTITE',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Apri una schedina alla volta. Le alternative cambiano '
            'solo dove esistono mercati e quote validi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: List.generate(3, (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                key: ValueKey('b50-three-coupon-tab-$index'),
                label: Text(_names[index]),
                selected: _selectedIndex == index,
                selectedColor: const Color(0xFF00C853),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: _selectedIndex == index
                      ? const Color(0xFF111827)
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                onSelected: (_) => setState(() => _selectedIndex = index),
              ),
            )),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            key: ValueKey('b50-three-coupon-list-$_selectedIndex'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: current.length + 1,
            itemBuilder: (context, index) => index == 0
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _couponSummary(current),
                  )
                : _matchCard(current[index - 1], index),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: widget.onShareAll,
              icon: const Icon(Icons.ios_share),
              label: const Text('CONDIVIDI LE 3 SCHEDINE'),
            ),
          ),
        ),
      ],
    );
  }
}
