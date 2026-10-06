import 'package:flutter/material.dart';

import 'app.dart';
import 'services/bankroll_store.dart';
import 'dart:async';
import 'services/goalvdline_comparison_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BankrollStore.instance.initialize();

  runApp(const SmartBetApp());

  unawaited(GoalVdLineComparisonSyncService.instance.resolveIfDue());
}
