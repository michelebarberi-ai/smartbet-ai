import 'bankroll_manager.dart';

class BankrollManagerTest {
  const BankrollManagerTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - BANKROLL LOCK TEST');
    print('========================================');

    final manager = BankrollManager(initialBankroll: 1000.0);

    _printBankroll(manager, title: 'STATO INIZIALE');

    // ==========================================================
    // BET 1 - 1%
    // ==========================================================

    final bet1 = manager.placeBet(
      matchLabel: 'Cagliari - Arezzo',
      outcome: '1',
      odd: 1.62,
      bookmaker: 'Betano',
      stakePercent: 1.00,
    );

    if (bet1 == null) {
      print('ERRORE BET 1');
      return;
    }

    _printBankroll(manager, title: 'DOPO BET 1 PENDING');

    // ==========================================================
    // BET 2 - 2%
    // ==========================================================

    final bet2 = manager.placeBet(
      matchLabel: 'Team A - Team B',
      outcome: 'X',
      odd: 3.40,
      bookmaker: 'Superbet',
      stakePercent: 2.00,
    );

    if (bet2 == null) {
      print('ERRORE BET 2');
      return;
    }

    _printBankroll(manager, title: 'DOPO BET 2 PENDING');

    // ==========================================================
    // BET 3 - 3%
    // ==========================================================

    final bet3 = manager.placeBet(
      matchLabel: 'Team C - Team D',
      outcome: '2',
      odd: 4.50,
      bookmaker: 'TestBook',
      stakePercent: 3.00,
    );

    if (bet3 == null) {
      print('ERRORE BET 3');
      return;
    }

    _printBankroll(manager, title: 'DOPO BET 3 PENDING');

    // ==========================================================
    // BET 1 WIN
    // ==========================================================

    manager.settleWin(bet1.id);

    _printBankroll(manager, title: 'DOPO BET 1 WIN');

    // ==========================================================
    // BET 2 LOSS
    // ==========================================================

    manager.settleLoss(bet2.id);

    _printBankroll(manager, title: 'DOPO BET 2 LOSS');

    // ==========================================================
    // BET 3 ANCORA PENDING
    // ==========================================================

    print('');
    print('BET 3 ANCORA PENDING');

    print(
      'Stake bloccato BET 3: '
      '€${bet3.stakeAmount.toStringAsFixed(2)}',
    );

    // ==========================================================
    // BET 3 VOID
    // ==========================================================

    manager.settleVoid(bet3.id);

    _printBankroll(manager, title: 'DOPO BET 3 VOID');

    // ==========================================================
    // SNAPSHOT FINALE
    // ==========================================================

    final snapshot = manager.snapshot;

    print('');
    print('========================================');
    print('SNAPSHOT FINALE');
    print('========================================');

    print(
      'Initial: '
      '€${snapshot.initialBankroll.toStringAsFixed(2)}',
    );

    print(
      'Current: '
      '€${snapshot.currentBankroll.toStringAsFixed(2)}',
    );

    print(
      'Locked: '
      '€${snapshot.lockedBankroll.toStringAsFixed(2)}',
    );

    print(
      'Available: '
      '€${snapshot.availableBankroll.toStringAsFixed(2)}',
    );

    print(
      'Total staked: '
      '€${snapshot.totalStaked.toStringAsFixed(2)}',
    );

    print(
      'P/L: '
      '${snapshot.totalProfitLoss >= 0 ? '+' : ''}'
      '€${snapshot.totalProfitLoss.toStringAsFixed(2)}',
    );

    print(
      'ROI: '
      '${snapshot.roiPercent.toStringAsFixed(2)}%',
    );

    print(
      'Bankroll growth: '
      '${snapshot.bankrollGrowthPercent.toStringAsFixed(2)}%',
    );

    print('Win: ${snapshot.wins}');

    print('Loss: ${snapshot.losses}');

    print('Void: ${snapshot.voids}');

    print('Pending: ${snapshot.pending}');

    print('');
    print('========================================');
    print('BANKROLL LOCK TEST COMPLETATO');
    print('========================================');
  }

  static void _printBankroll(BankrollManager manager, {required String title}) {
    print('');
    print('========================================');
    print(title);
    print('========================================');

    print(
      'Current bankroll: '
      '€${manager.currentBankroll.toStringAsFixed(2)}',
    );

    print(
      'Locked bankroll: '
      '€${manager.lockedBankroll.toStringAsFixed(2)}',
    );

    print(
      'Available bankroll: '
      '€${manager.availableBankroll.toStringAsFixed(2)}',
    );
  }
}

Future<void> main() async {
  await BankrollManagerTest.run();
}
