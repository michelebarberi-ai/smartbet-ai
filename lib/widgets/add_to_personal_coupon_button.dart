import 'package:flutter/material.dart';
import '../services/personal_coupon_store.dart';

/// Reusable action: choose a destination slip without altering AI outputs.
class AddToPersonalCouponButton extends StatelessWidget {
  final String fixtureId;
  final String match;
  final String market;
  final String source;
  final double? odds;
  const AddToPersonalCouponButton({
    super.key, required this.fixtureId, required this.match,
    required this.market, required this.source, this.odds,
  });

  Future<void> _add(BuildContext context) async {
    final store = PersonalCouponStore.instance;
    await store.initialize();
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Aggiungi alla mia schedina',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('$match · $market', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              for (final coupon in store.coupons)
                ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: Text(coupon.name),
                  subtitle: Text('${coupon.selections.length} pronostici'),
                  onTap: () => Navigator.pop(sheetContext, coupon.id),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Crea nuova schedina'),
                onTap: () async {
                  final controller = TextEditingController();
                  final name = await showDialog<String>(
                    context: sheetContext,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Nome della schedina'),
                      content: TextField(controller: controller, autofocus: true,
                        maxLength: 60),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Annulla')),
                        FilledButton(onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                          child: const Text('Crea')),
                      ],
                    ),
                  );
                  controller.dispose();
                  if (name == null || name.isEmpty) return;
                  await store.create(name);
                  if (sheetContext.mounted && store.coupons.isNotEmpty) {
                    Navigator.pop(sheetContext, store.coupons.last.id);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
    if (selected == null) return;
    await store.addSelection(selected, PersonalSelection(
      fixtureId: fixtureId, match: match, market: market,
      source: source, odds: odds, capturedAt: DateTime.now(),
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pronostico aggiunto alla schedina personale')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _add(context),
    icon: const Icon(Icons.add_circle_outline),
    label: const Text('Aggiungi alla mia schedina'),
  );
}
