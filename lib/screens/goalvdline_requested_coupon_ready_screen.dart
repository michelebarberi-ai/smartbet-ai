import 'package:flutter/material.dart';

import '../services/goalvdline_ready_coupon_local_store.dart';

/// Read-only view of the latest on-demand coupon saved on this device.
/// Does not fetch or generate a server-side daily AutoSchedina.
class GoalVdLineRequestedCouponReadyScreen extends StatelessWidget {
  const GoalVdLineRequestedCouponReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('La tua schedina pronta')),
      body: FutureBuilder<String?>(
        future: const GoalVdLineReadyCouponLocalStore().load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final text = snapshot.data;
          if (text == null) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nessuna schedina completata è salvata su questo '
                  'iPhone. Crea una nuova schedina nell’app.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('ULTIMA SCHEDINA CREATA SU RICHIESTA',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 9),
              const Text('Risultato salvato sul dispositivo. '
                  'Le quote sono quelle raccolte al momento '
                  'della generazione e possono cambiare.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              SelectableText(text, key: const Key('b45-local-ready-summary')),
            ],
          );
        },
      ),
    );
  }
}
