import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'bankroll_manager.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // SHARED PREFERENCES MOCK
  // ============================================================

  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  print('');
  print('========================================');
  print('SMARTBET - BANKROLL PERSISTENCE TEST');
  print('========================================');

  // ============================================================
  // FASE 1
  // ============================================================

  final manager1 = BankrollManager(initialBankroll: 1000.0);

  await manager1.clearStorage();

  manager1.reset(bankroll: 1000.0);

  final bet1 = manager1.placeBet(
    matchLabel: 'Cagliari - Arezzo',
    outcome: '1',
    odd: 1.62,
    bookmaker: 'Betano',
    stakePercent: 0.50,
  );

  final bet2 = manager1.placeBet(
    matchLabel: 'Team A - Team B',
    outcome: 'X',
    odd: 4.20,
    bookmaker: 'Superbet',
    stakePercent: 1.00,
  );

  if (bet1 == null || bet2 == null) {
    print('ERRORE: impossibile creare le bet.');

    return;
  }

  await manager1.settleWinAndSave(bet1.id);

  await manager1.save();

  print('');
  print('========================================');
  print('PRIMA DEL RIAVVIO');
  print('========================================');

  print(
    'Initial: '
    '€${manager1.initialBankroll.toStringAsFixed(2)}',
  );

  print(
    'Current: '
    '€${manager1.currentBankroll.toStringAsFixed(2)}',
  );

  print(
    'Locked: '
    '€${manager1.lockedBankroll.toStringAsFixed(2)}',
  );

  print(
    'Available: '
    '€${manager1.availableBankroll.toStringAsFixed(2)}',
  );

  print(
    'History: '
    '${manager1.history.length}',
  );

  print(
    'Win: '
    '${manager1.snapshot.wins}',
  );

  print(
    'Pending: '
    '${manager1.snapshot.pending}',
  );

  print(
    'Total stake placed: '
    '€${manager1.snapshot.totalStakePlaced.toStringAsFixed(2)}',
  );

  print(
    'Settled stake ROI: '
    '€${manager1.snapshot.settledStakeForRoi.toStringAsFixed(2)}',
  );

  // ============================================================
  // SIMULAZIONE RIAVVIO
  // ============================================================

  print('');
  print('========================================');
  print('SIMULAZIONE RIAVVIO APP');
  print('========================================');

  final manager2 = BankrollManager(initialBankroll: 0.0);

  final loaded = await manager2.load();

  print('Caricamento riuscito: $loaded');

  if (!loaded) {
    print('ERRORE: caricamento fallito.');

    return;
  }

  // ============================================================
  // DOPO RIAVVIO
  // ============================================================

  print('');
  print('========================================');
  print('DOPO RIAVVIO');
  print('========================================');

  print(
    'Initial: '
    '€${manager2.initialBankroll.toStringAsFixed(2)}',
  );

  print(
    'Current: '
    '€${manager2.currentBankroll.toStringAsFixed(2)}',
  );

  print(
    'Locked: '
    '€${manager2.lockedBankroll.toStringAsFixed(2)}',
  );

  print(
    'Available: '
    '€${manager2.availableBankroll.toStringAsFixed(2)}',
  );

  print(
    'History: '
    '${manager2.history.length}',
  );

  print(
    'Win: '
    '${manager2.snapshot.wins}',
  );

  print(
    'Pending: '
    '${manager2.snapshot.pending}',
  );

  print(
    'Total stake placed: '
    '€${manager2.snapshot.totalStakePlaced.toStringAsFixed(2)}',
  );

  print(
    'Settled stake ROI: '
    '€${manager2.snapshot.settledStakeForRoi.toStringAsFixed(2)}',
  );

  // ============================================================
  // CERCHIAMO LA BET PENDING
  // ============================================================

  BankrollBet? pendingBet;

  for (final bet in manager2.history) {
    if (bet.isPending) {
      pendingBet = bet;
      break;
    }
  }

  if (pendingBet == null) {
    print('ERRORE: bet pending non ripristinata.');

    return;
  }

  print('');
  print('========================================');
  print('BET PENDING RIPRISTINATA');
  print('========================================');

  print(
    'Partita: '
    '${pendingBet.matchLabel}',
  );

  print(
    'Esito: '
    '${pendingBet.outcome}',
  );

  print(
    'Quota: '
    '${pendingBet.odd.toStringAsFixed(2)}',
  );

  print(
    'Bookmaker: '
    '${pendingBet.bookmaker}',
  );

  print(
    'Stake: '
    '€${pendingBet.stakeAmount.toStringAsFixed(2)}',
  );

  print(
    'Status: '
    '${pendingBet.status}',
  );

  // ============================================================
  // SETTLEMENT DOPO RIAVVIO
  // ============================================================

  final settled = await manager2.settleLossAndSave(pendingBet.id);

  print('');
  print('Settlement pending riuscito: $settled');

  // ============================================================
  // STATO FINALE
  // ============================================================

  print('');
  print('========================================');
  print('DOPO SETTLEMENT BET PENDING');
  print('========================================');

  print(
    'Current: '
    '€${manager2.currentBankroll.toStringAsFixed(2)}',
  );

  print(
    'Locked: '
    '€${manager2.lockedBankroll.toStringAsFixed(2)}',
  );

  print(
    'Available: '
    '€${manager2.availableBankroll.toStringAsFixed(2)}',
  );

  print(
    'Win: '
    '${manager2.snapshot.wins}',
  );

  print(
    'Loss: '
    '${manager2.snapshot.losses}',
  );

  print(
    'Pending: '
    '${manager2.snapshot.pending}',
  );

  print(
    'P/L: '
    '${manager2.snapshot.totalProfitLoss >= 0 ? '+' : ''}'
    '€${manager2.snapshot.totalProfitLoss.toStringAsFixed(2)}',
  );

  print(
    'ROI: '
    '${manager2.snapshot.roiPercent >= 0 ? '+' : ''}'
    '${manager2.snapshot.roiPercent.toStringAsFixed(2)}%',
  );

  print('');
  print('========================================');
  print('PERSISTENCE TEST COMPLETATO');
  print('========================================');
}
