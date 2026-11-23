import 'package:flutter/material.dart';
import '../services/personal_coupon_store.dart';
import '../services/personal_coupon_review_service.dart';
import '../services/smartbet_analysis_history_store.dart';
import '../widgets/personal_coupon_match_tile.dart';

class PersonalCouponsScreen extends StatefulWidget {
  const PersonalCouponsScreen({super.key});
  @override
  State<PersonalCouponsScreen> createState() => _PersonalCouponsScreenState();
}

class _PersonalCouponsScreenState extends State<PersonalCouponsScreen> {
  final store = PersonalCouponStore.instance;
  final history = SmartBetAnalysisHistoryStore.instance;
  final reviewService = const PersonalCouponReviewService();
  bool _refreshing = false;

  Future<void> _editMarket(PersonalCoupon coupon, PersonalSelection pick) async {
    final controller = TextEditingController(text: pick.currentMarket);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica il mercato scelto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proposta iniziale: ${pick.market}'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLength: 90,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Mercato della tua scelta',
                hintText: 'Es. UNDER 3.5, 1X, GOAL',
              ),
            ),
            const Text(
              'La previsione iniziale resta salvata. '
              'La quota e la probabilità originarie '
              'non valgono per un mercato modificato.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salva scelta'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (chosen == null || chosen.isEmpty) return;
    final changed = await store.changeSelectionMarket(
      coupon.id, pick.fixtureId, pick.market, chosen,
    );
    if (!mounted) return;
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Scelta non salvata: controlla il mercato o i duplicati.',
        )),
      );
    }
  }

  Future<void> _refreshResults() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await history.initialize();
      final report = await reviewService.fetchFinished(
        selections: store.coupons.expand((coupon) => coupon.selections),
        history: history.records,
      );
      final updated = await store.registerVerifiedResults(report.scores);
      if (!mounted) return;
      final message = [
        'Risultati aggiornati: $updated selezioni.',
        if (report.fixturesNotFinal > 0)
          '${report.fixturesNotFinal} partite ancora non verificate.',
        if (report.missingKickoff > 0)
          'Alcuni vecchi pronostici non hanno la data per la ricerca.',
        if (report.apiErrors > 0)
          'Impossibile recuperare ${report.apiErrors} giornate.',
      ].join(' ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Aggiornamento non riuscito. Nessun risultato è stato inventato.',
        )),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Previous versions saved no country or league; recover those fields
  /// from the already persisted prediction archive without any network call.
  SmartBetAnalysisRecord? _archivedMatch(PersonalSelection selection) {
    for (final record in history.records) {
      if (record.fixtureId.toString() == selection.fixtureId &&
          (record.country.trim().isNotEmpty ||
           record.league.trim().isNotEmpty)) {
        return record;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    store.initialize();
    history.initialize();
  }

  Future<String?> _askName({String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial == null ? 'Nuova schedina' : 'Rinomina schedina'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Nome della schedina'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Salva')),
        ],
      ),
    );
    controller.dispose();
    return result?.isNotEmpty == true ? result : null;
  }

  /// Multiplication is informative only for different fixtures with real odds.
  /// A second market on the same match must never inflate a total.
  double? _combinedOdds(PersonalCoupon coupon) {
    if (coupon.selections.isEmpty) return null;
    final ids = coupon.selections.map((e) => e.fixtureId).toSet();
    if (ids.length != coupon.selections.length) return null;
    var result = 1.0;
    for (final pick in coupon.selections) {
      final odd = pick.currentOdds;
      if (odd == null || !odd.isFinite || odd <= 1.20) return null;
      result *= odd;
    }
    return result.isFinite ? result : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Le mie schedine'),
      actions: [
        IconButton(
          tooltip: 'Aggiorna gli esiti delle partite concluse',
          onPressed: _refreshing ? null : _refreshResults,
          icon: _refreshing
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final name = await _askName();
        if (name != null) await store.create(name);
      },
      icon: const Icon(Icons.add),
      label: const Text('Nuova schedina'),
    ),
    body: AnimatedBuilder(
      animation: Listenable.merge([store, history]),
      builder: (context, _) {
        final records = history.records;
        final repeated = reviewService.repeatedSelections(store.coupons);
        if (store.coupons.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('Crea la tua prima schedina personale. Qui potrai raccogliere pronostici da tutte le sezioni dell’app.',
              textAlign: TextAlign.center),
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: store.coupons.length,
          itemBuilder: (context, index) {
            final coupon = store.coupons[index];
            final total = _combinedOdds(coupon);
            final summary = reviewService.summarize(coupon, records);
            return Card(child: ExpansionTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text(coupon.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${coupon.selections.length} pronostici'
                    '${total == null ? '' : ' · Quota indicativa ${total.toStringAsFixed(2)}'}',
                  ),
                  if (coupon.selections.isNotEmpty)
                    Text(
                      'Esiti: ${summary.correct} corretti · '
                      '${summary.wrong} errati · '
                      '${summary.pending} in attesa'
                      '${summary.unsupported == 0 ? '' : ' · ${summary.unsupported} da verificare'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
              children: [
                for (final pick in coupon.selections)
                  PersonalCouponMatchTile(
                    key: ValueKey('personal-selection-${coupon.id}-'
                        '${pick.fixtureId}-${pick.market}'),
                    selection: pick,
                    archivedMatch: _archivedMatch(pick),
                    review: reviewService.review(pick, records),
                    repeatedAcrossCoupons: reviewService.repeatedInCoupons(
                      pick, repeated,
                    ),
                    onEditMarket: () => _editMarket(coupon, pick),
                    onRemove: () => store.removeSelection(
                        coupon.id, pick.fixtureId, pick.market),
                  ),
                if (coupon.selections.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Revisione basata su risultati finali verificati, '
                      'non sulle probabilità dichiarate. Premi Aggiorna per '
                      'controllare gli esiti disponibili (massimo 5 giornate). '
                      'Mercati non riconosciuti restano da verificare sul bookmaker. '
                      'Se cambi mercato, la quota iniziale non viene riutilizzata.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () async {
                      final name = await _askName(initial: coupon.name);
                      if (name != null) await store.rename(coupon.id, name);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rinomina'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminare la schedina?'),
                          content: Text('Eliminare "${coupon.name}" e tutte le sue selezioni?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annulla')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Elimina')),
                          ],
                        ),
                      );
                      if (yes == true) await store.delete(coupon.id);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Elimina'),
                  ),
                ]),
              ],
            ));
          },
        );
      },
    ),
  );
}
