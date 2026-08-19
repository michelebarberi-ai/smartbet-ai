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

  bool hasBet({
    required String matchLabel,
    required String outcome,
    required double odd,
  }) {
    return manager.hasBet(matchLabel: matchLabel, outcome: outcome, odd: odd);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await manager.load();

    _initialized = true;

    notifyListeners();
  }

  Future<void> setInitialBankroll(double bankroll) async {
    if (bankroll <= 0.0) {
      return;
    }

    await manager.resetAndSave(bankroll: bankroll);

    notifyListeners();
  }

  Future<void> resetBankroll(double bankroll) async {
    if (bankroll <= 0.0) {
      return;
    }

    await manager.resetAndSave(bankroll: bankroll);

    notifyListeners();
  }

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

  Future<bool> settleWin(String betId) async {
    return settleAs(betId, 'WIN');
  }

  Future<bool> settleLoss(String betId) async {
    return settleAs(betId, 'LOSS');
  }

  Future<bool> settleVoid(String betId) async {
    return settleAs(betId, 'VOID');
  }

  Future<bool> setPending(String betId) async {
    return settleAs(betId, 'PENDING');
  }

  Future<bool> settleAs(String betId, String status) async {
    final result = await manager.settleAsAndSave(betId, status);

    if (result) {
      notifyListeners();
    }

    return result;
  }

  Future<bool> deleteBet(String betId) async {
    final result = await manager.deleteBetAndSave(betId);

    if (result) {
      notifyListeners();
    }

    return result;
  }
}
