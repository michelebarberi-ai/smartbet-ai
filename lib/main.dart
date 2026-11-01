import 'package:flutter/material.dart';

import 'app.dart';
import 'services/bankroll_store.dart';
import 'dart:async';
import 'services/goalvdline_comparison_sync_service.dart';
import 'services/smartbet_shadow_model_startup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BankrollStore.instance.initialize();
  // Preparazione shadow prima delle nuove analisi.
  await SmartBetShadowModelStartupService.instance.run();

  runApp(const SmartBetApp());

  unawaited(GoalVdLineComparisonSyncService.instance.resolveIfDue());
}
