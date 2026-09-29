import 'package:flutter/material.dart';

import 'app.dart';
import 'services/bankroll_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BankrollStore.instance.initialize();

  runApp(const SmartBetApp());
}
