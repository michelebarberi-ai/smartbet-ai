import 'package:flutter/material.dart';
import '../services/personal_coupon_store.dart';

class PersonalCouponsScreen extends StatefulWidget {
  const PersonalCouponsScreen({super.key});
  @override
  State<PersonalCouponsScreen> createState() => _PersonalCouponsScreenState();
}

class _PersonalCouponsScreenState extends State<PersonalCouponsScreen> {
  final store = PersonalCouponStore.instance;

  @override
  void initState() {
    super.initState();
    store.initialize();
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
      final odd = pick.odds;
      if (odd == null || !odd.isFinite || odd <= 1.20) return null;
      result *= odd;
    }
    return result.isFinite ? result : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Le mie schedine')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final name = await _askName();
        if (name != null) await store.create(name);
      },
      icon: const Icon(Icons.add),
      label: const Text('Nuova schedina'),
    ),
    body: AnimatedBuilder(
      animation: store,
      builder: (context, _) {
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
            return Card(child: ExpansionTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text(coupon.name),
              subtitle: Text(
                '${coupon.selections.length} pronostici'
                '${total == null ? '' : ' · Quota indicativa ${total.toStringAsFixed(2)}'}',
              ),
              children: [
                for (final pick in coupon.selections)
                  ListTile(
                    title: Text(pick.match),
                    subtitle: Text([
                      pick.market,
                      pick.source,
                      if (pick.probability != null)
                        'AI ${pick.probability!.toStringAsFixed(1)}%',
                      if (pick.odds != null && pick.odds!.isFinite)
                        'Quota ${pick.odds!.toStringAsFixed(2)}',
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Rimuovi pronostico',
                      icon: const Icon(Icons.close),
                      onPressed: () => store.removeSelection(
                          coupon.id, pick.fixtureId, pick.market),
                    ),
                  ),
                if (coupon.selections.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Quote indicative: verifica sempre mercati e disponibilità. '
                      'Mercati diversi della stessa partita non si moltiplicano.',
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
