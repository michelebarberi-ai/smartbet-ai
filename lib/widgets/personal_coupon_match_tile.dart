import 'package:flutter/material.dart';

import '../services/personal_coupon_store.dart';
import '../services/smartbet_analysis_history_store.dart';

/// A saved prediction expands into the original fixture summary.
/// Never requests new AI analysis, odds or live data to render old coupons.
class PersonalCouponMatchTile extends StatelessWidget {
  const PersonalCouponMatchTile({
    super.key,
    required this.selection,
    required this.onRemove,
    this.archivedMatch,
  });

  final PersonalSelection selection;
  final SmartBetAnalysisRecord? archivedMatch;
  final VoidCallback onRemove;

  String _firstKnown(String? saved, String? historic) {
    final first = saved?.trim() ?? '';
    if (first.isNotEmpty) return first;
    return historic?.trim() ?? '';
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _detail(String name, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 98,
          child: Text(name, style: const TextStyle(
            color: Colors.white54, fontSize: 11,
          )),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 12,
          )),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final country = _firstKnown(selection.country, archivedMatch?.country);
    final league = _firstKnown(selection.league, archivedMatch?.league);
    final kickoff = selection.kickoffAt ?? archivedMatch?.matchDate;
    final metadata = [
      if (country.isNotEmpty) country,
      if (league.isNotEmpty) league,
    ].join(' · ');
    final probability = selection.probability;
    final odds = selection.odds;
    final oddsValid = odds != null && odds.isFinite && odds > 1.20;
    final prediction = [
      selection.market,
      if (probability != null && probability.isFinite &&
          probability >= 0 && probability <= 100)
        'AI ${probability.toStringAsFixed(1)}%',
      if (oddsValid) 'Quota ${odds!.toStringAsFixed(2)}',
    ].join(' · ');

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('personal-match-${selection.fixtureId}-${selection.market}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        childrenPadding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
        iconColor: const Color(0xFF95D5B2),
        collapsedIconColor: const Color(0xFF95D5B2),
        title: Text(
          selection.match,
          style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              metadata.isEmpty
                  ? 'Paese e campionato non disponibili'
                  : metadata,
              key: const Key('personal-match-competition'),
              style: const TextStyle(
                color: Color(0xFF95D5B2), fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              prediction,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        children: [
          Container(
            key: const Key('personal-match-details'),
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF101E2C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scheda della partita',
                  style: TextStyle(
                    color: Color(0xFF95D5B2),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 11),
                _detail('Partita', selection.match),
                _detail('Paese', country.isEmpty ? 'Non disponibile' : country),
                _detail('Campionato', league.isEmpty ? 'Non disponibile' : league),
                if (kickoff != null)
                  _detail('Inizio', _date(kickoff)),
                _detail('Pronostico', selection.market),
                _detail(
                  'Probabilità AI',
                  probability != null && probability.isFinite &&
                      probability >= 0 && probability <= 100
                      ? '${probability.toStringAsFixed(1)}%'
                      : 'Non disponibile',
                ),
                _detail('Quota',
                  oddsValid ? odds!.toStringAsFixed(2) : 'Non disponibile'),
                if (selection.bookmaker?.trim().isNotEmpty == true)
                  _detail('Bookmaker', selection.bookmaker!.trim()),
                _detail('Origine', selection.source),
                _detail('Salvato il', _date(selection.capturedAt)),
                const SizedBox(height: 5),
                const Text(
                  'Dati del pronostico al momento del salvataggio. '
                  'Le quote non sono aggiornate in tempo reale.',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Rimuovi pronostico'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
