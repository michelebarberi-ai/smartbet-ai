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
            return Card(child: ExpansionTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text(coupon.name),
              subtitle: Text('${coupon.selections.length} pronostici'),
              children: [
                for (final pick in coupon.selections)
                  ListTile(
                    title: Text(pick.match),
                    subtitle: Text('${pick.market} · ${pick.source}'),
                    trailing: IconButton(
                      tooltip: 'Rimuovi pronostico',
                      icon: const Icon(Icons.close),
                      onPressed: () => store.removeSelection(
                          coupon.id, pick.fixtureId, pick.market),
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
