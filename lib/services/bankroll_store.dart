import 'package:flutter/foundation.dart';

import 'bankroll_manager.dart';

class BankrollStore extends ChangeNotifier {
  BankrollStore._();

  static final BankrollStore instance = BankrollStore._();

  final BankrollManager manager = BankrollManager(initialBankroll: 0.0);

  bool _initialized = false;

  bool get initialized => _initialized;

  bool get hasConfiguredBankroll => manager.initialBankroll > 0.0;

  double get initialBankroll => manager.initialBankroll;

  double get currentBankroll => manager.currentBankroll;

  double get lockedBankroll => manager.lockedBankroll;

  double get availableBankroll => manager.availableBankroll;

  BankrollSnapshot get snapshot => manager.snapshot;

  List<BankrollBet> get history => manager.history;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await manager.load();

    // Se non esiste ancora un capitale salvato,
    // NON impostiamo nessun valore automatico.
    // L'utente lo sceglierà dalla Home.

    _initialized = true;

    notifyListeners();
  }

  // ============================================================
  // IMPOSTA CAPITALE
  // ============================================================

  Future<void> setInitialBankroll(double bankroll) async {
    if (bankroll <= 0.0) {
      return;
    }

    await manager.resetAndSave(bankroll: bankroll);

    notifyListeners();
  }

  // ============================================================
  // RESET / MODIFICA CAPITALE
  // ============================================================

  Future<void> resetBankroll(double bankroll) async {
    if (bankroll <= 0.0) {
      return;
    }

    await manager.resetAndSave(bankroll: bankroll);

    notifyListeners();
  }

  // ============================================================
  // PLACE BET
  // ============================================================

  Future<BankrollBet?> placeBet({
    required String matchLabel,
    required String outcome,
    required double odd,
    required String bookmaker,
    required double stakePercent,
  }) async {
    if (!hasConfiguredBankroll) {
      return null;
    }

    final bet = await manager.placeBetAndSave(
      matchLabel: matchLabel,
      outcome: outcome,
      odd: odd,
      bookmaker: bookmaker,
      stakePercent: stakePercent,
    );

    if (bet != null) {
      notifyListeners();
    }

    return bet;
  }

  // ============================================================
  // SETTLEMENT
  // ============================================================

  Future<bool> settleWin(String betId) async {
    final result = await manager.settleWinAndSave(betId);

    if (result) {
      notifyListeners();
    }

    return result;
  }

  Future<bool> settleLoss(String betId) async {
    final result = await manager.settleLossAndSave(betId);

    if (result) {
      notifyListeners();
    }

    return result;
  }

  Future<bool> settleVoid(String betId) async {
    final result = await manager.settleVoidAndSave(betId);

    if (result) {
      notifyListeners();
    }

    return result;
  }
}
