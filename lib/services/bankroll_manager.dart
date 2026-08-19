import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// BANKROLL BET
// ============================================================

class BankrollBet {
  final String id;

  final DateTime createdAt;

  final String matchLabel;

  final String outcome;

  final double odd;

  final String bookmaker;

  final double stakePercent;

  final double stakeAmount;

  final double bankrollBefore;

  final String status;

  final double profitLoss;

  const BankrollBet({
    required this.id,
    required this.createdAt,
    required this.matchLabel,
    required this.outcome,
    required this.odd,
    required this.bookmaker,
    required this.stakePercent,
    required this.stakeAmount,
    required this.bankrollBefore,
    required this.status,
    required this.profitLoss,
  });

  bool get isPending {
    return status == 'PENDING';
  }

  bool get isWin {
    return status == 'WIN';
  }

  bool get isLoss {
    return status == 'LOSS';
  }

  bool get isVoid {
    return status == 'VOID';
  }

  BankrollBet copyWith({String? status, double? profitLoss}) {
    return BankrollBet(
      id: id,
      createdAt: createdAt,
      matchLabel: matchLabel,
      outcome: outcome,
      odd: odd,
      bookmaker: bookmaker,
      stakePercent: stakePercent,
      stakeAmount: stakeAmount,
      bankrollBefore: bankrollBefore,
      status: status ?? this.status,
      profitLoss: profitLoss ?? this.profitLoss,
    );
  }

  // ==========================================================
  // JSON
  // ==========================================================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'matchLabel': matchLabel,
      'outcome': outcome,
      'odd': odd,
      'bookmaker': bookmaker,
      'stakePercent': stakePercent,
      'stakeAmount': stakeAmount,
      'bankrollBefore': bankrollBefore,
      'status': status,
      'profitLoss': profitLoss,
    };
  }

  factory BankrollBet.fromJson(Map<String, dynamic> json) {
    return BankrollBet(
      id: json['id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      matchLabel: json['matchLabel']?.toString() ?? '',
      outcome: json['outcome']?.toString() ?? '',
      odd: _toDoubleStatic(json['odd']),
      bookmaker: json['bookmaker']?.toString() ?? '',
      stakePercent: _toDoubleStatic(json['stakePercent']),
      stakeAmount: _toDoubleStatic(json['stakeAmount']),
      bankrollBefore: _toDoubleStatic(json['bankrollBefore']),
      status: json['status']?.toString() ?? 'PENDING',
      profitLoss: _toDoubleStatic(json['profitLoss']),
    );
  }

  static double _toDoubleStatic(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

// ============================================================
// SNAPSHOT
// ============================================================

class BankrollSnapshot {
  final double initialBankroll;
  final double currentBankroll;

  final double lockedBankroll;
  final double availableBankroll;

  // Tutto lo stake effettivamente piazzato,
  // inclusi VOID e PENDING.
  final double totalStakePlaced;

  // Solo stake concluso con WIN o LOSS.
  // Questo è il denominatore usato per il ROI.
  final double settledStakeForRoi;

  final double totalProfitLoss;

  final int bets;
  final int wins;
  final int losses;
  final int voids;
  final int pending;

  const BankrollSnapshot({
    required this.initialBankroll,
    required this.currentBankroll,
    required this.lockedBankroll,
    required this.availableBankroll,
    required this.totalStakePlaced,
    required this.settledStakeForRoi,
    required this.totalProfitLoss,
    required this.bets,
    required this.wins,
    required this.losses,
    required this.voids,
    required this.pending,
  });

  // Compatibilità con il codice precedente.
  double get totalStaked {
    return settledStakeForRoi;
  }

  double get roi {
    if (settledStakeForRoi <= 0.0) {
      return 0.0;
    }

    return totalProfitLoss / settledStakeForRoi;
  }

  double get roiPercent {
    return roi * 100.0;
  }

  double get bankrollGrowth {
    if (initialBankroll <= 0.0) {
      return 0.0;
    }

    return (currentBankroll - initialBankroll) / initialBankroll;
  }

  double get bankrollGrowthPercent {
    return bankrollGrowth * 100.0;
  }

  double get lockedPercent {
    if (currentBankroll <= 0.0) {
      return 0.0;
    }

    return lockedBankroll / currentBankroll * 100.0;
  }

  double get availablePercent {
    if (currentBankroll <= 0.0) {
      return 0.0;
    }

    return availableBankroll / currentBankroll * 100.0;
  }
}

// ============================================================
// BANKROLL MANAGER
// ============================================================

class BankrollManager {
  static const String _storageKey = 'smartbet_bankroll_state_v1';

  double _initialBankroll;

  double _currentBankroll;

  final List<BankrollBet> _history = [];

  BankrollManager({required double initialBankroll})
    : _initialBankroll = initialBankroll > 0.0 ? initialBankroll : 0.0,
      _currentBankroll = initialBankroll > 0.0 ? initialBankroll : 0.0;

  // ============================================================
  // GETTERS
  // ============================================================

  double get initialBankroll {
    return _initialBankroll;
  }

  double get currentBankroll {
    return _currentBankroll;
  }

  double get lockedBankroll {
    double total = 0.0;

    for (final bet in _history) {
      if (bet.isPending) {
        total += bet.stakeAmount;
      }
    }

    return total;
  }

  double get availableBankroll {
    final available = _currentBankroll - lockedBankroll;

    if (available < 0.0) {
      return 0.0;
    }

    return available;
  }

  List<BankrollBet> get history {
    return List.unmodifiable(_history);
  }

  bool hasBet({
    required String matchLabel,
    required String outcome,
    required double odd,
  }) {
    final normalizedMatch = matchLabel.trim().toLowerCase();
    final normalizedOutcome = outcome.trim().toUpperCase();

    return _history.any((bet) {
      final sameMatch = bet.matchLabel.trim().toLowerCase() == normalizedMatch;
      final sameOutcome = bet.outcome.trim().toUpperCase() == normalizedOutcome;
      final sameOdd = (bet.odd - odd).abs() < 0.0001;
      return sameMatch && sameOutcome && sameOdd;
    });
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<bool> load() async {
    try {
      final prefs = SharedPreferencesAsync();

      final raw = await prefs.getString(_storageKey);

      if (raw == null || raw.trim().isEmpty) {
        print('');
        print('BANKROLL STORAGE: nessun salvataggio trovato.');

        return false;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final initial = _toDouble(decoded['initialBankroll']);

      final current = _toDouble(decoded['currentBankroll']);

      final historyData = decoded['history'];

      _initialBankroll = initial >= 0.0 ? initial : 0.0;

      _currentBankroll = current >= 0.0 ? current : 0.0;

      _history.clear();

      if (historyData is List) {
        for (final item in historyData) {
          if (item is Map<String, dynamic>) {
            _history.add(BankrollBet.fromJson(item));
          } else if (item is Map) {
            _history.add(BankrollBet.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }

      print('');
      print('========================================');
      print('BANKROLL STORAGE - CARICATO');
      print('========================================');

      print(
        'Current: '
        '€${_currentBankroll.toStringAsFixed(2)}',
      );

      print(
        'Locked: '
        '€${lockedBankroll.toStringAsFixed(2)}',
      );

      print(
        'Available: '
        '€${availableBankroll.toStringAsFixed(2)}',
      );

      print('History: ${_history.length}');

      print('========================================');

      return true;
    } catch (e) {
      print('');
      print('BANKROLL STORAGE LOAD ERROR: $e');

      return false;
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<bool> save() async {
    try {
      final prefs = SharedPreferencesAsync();

      final data = {
        'version': 1,
        'initialBankroll': _initialBankroll,
        'currentBankroll': _currentBankroll,
        'updatedAt': DateTime.now().toIso8601String(),
        'history': _history.map((bet) => bet.toJson()).toList(),
      };

      await prefs.setString(_storageKey, jsonEncode(data));

      return true;
    } catch (e) {
      print('');
      print('BANKROLL STORAGE SAVE ERROR: $e');

      return false;
    }
  }

  // ============================================================
  // CLEAR STORAGE
  // ============================================================

  Future<void> clearStorage() async {
    final prefs = SharedPreferencesAsync();

    await prefs.remove(_storageKey);
  }

  // ============================================================
  // RESET
  // ============================================================

  void reset({required double bankroll}) {
    _initialBankroll = bankroll > 0.0 ? bankroll : 0.0;

    _currentBankroll = bankroll > 0.0 ? bankroll : 0.0;

    _history.clear();
  }

  Future<void> resetAndSave({required double bankroll}) async {
    reset(bankroll: bankroll);

    await save();
  }

  // ============================================================
  // PLACE BET
  // ============================================================

  BankrollBet? placeBet({
    required String matchLabel,
    required String outcome,
    required double odd,
    required String bookmaker,
    required double stakePercent,
  }) {
    if (hasBet(matchLabel: matchLabel, outcome: outcome, odd: odd)) {
      return null;
    }

    if (_currentBankroll <= 0.0) {
      return null;
    }

    if (availableBankroll <= 0.0) {
      return null;
    }

    if (odd <= 1.0) {
      return null;
    }

    if (stakePercent <= 0.0) {
      return null;
    }

    final stakeAmount = _currentBankroll * (stakePercent / 100.0);

    if (stakeAmount <= 0.0) {
      return null;
    }

    if (stakeAmount > availableBankroll) {
      return null;
    }

    final now = DateTime.now();

    final bet = BankrollBet(
      id: now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      matchLabel: matchLabel,
      outcome: outcome,
      odd: odd,
      bookmaker: bookmaker,
      stakePercent: stakePercent,
      stakeAmount: stakeAmount,
      bankrollBefore: _currentBankroll,
      status: 'PENDING',
      profitLoss: 0.0,
    );

    _history.add(bet);

    return bet;
  }

  // ============================================================
  // PLACE + SAVE
  // ============================================================

  Future<BankrollBet?> placeBetAndSave({
    required String matchLabel,
    required String outcome,
    required double odd,
    required String bookmaker,
    required double stakePercent,
  }) async {
    final bet = placeBet(
      matchLabel: matchLabel,
      outcome: outcome,
      odd: odd,
      bookmaker: bookmaker,
      stakePercent: stakePercent,
    );

    if (bet != null) {
      await save();
    }

    return bet;
  }

  // ============================================================
  // WIN
  // ============================================================

  bool settleWin(String betId) {
    final index = _findPendingIndex(betId);

    if (index < 0) {
      return false;
    }

    final bet = _history[index];

    final profit = bet.stakeAmount * (bet.odd - 1.0);

    _currentBankroll += profit;

    _history[index] = bet.copyWith(status: 'WIN', profitLoss: profit);

    return true;
  }

  Future<bool> settleWinAndSave(String betId) async {
    final result = settleWin(betId);

    if (result) {
      await save();
    }

    return result;
  }

  // ============================================================
  // LOSS
  // ============================================================

  bool settleLoss(String betId) {
    final index = _findPendingIndex(betId);

    if (index < 0) {
      return false;
    }

    final bet = _history[index];

    final loss = -bet.stakeAmount;

    _currentBankroll += loss;

    _history[index] = bet.copyWith(status: 'LOSS', profitLoss: loss);

    return true;
  }

  Future<bool> settleLossAndSave(String betId) async {
    final result = settleLoss(betId);

    if (result) {
      await save();
    }

    return result;
  }

  // ============================================================
  // VOID
  // ============================================================

  bool settleVoid(String betId) {
    final index = _findPendingIndex(betId);

    if (index < 0) {
      return false;
    }

    final bet = _history[index];

    _history[index] = bet.copyWith(status: 'VOID', profitLoss: 0.0);

    return true;
  }

  Future<bool> settleVoidAndSave(String betId) async {
    final result = settleVoid(betId);

    if (result) {
      await save();
    }

    return result;
  }

  // ============================================================
  // SETTLEMENT / CORREZIONE RISULTATO
  // ============================================================
  //
  // Permette sia di chiudere una giocata PENDING sia di
  // correggere una giocata già chiusa.
  //
  // Prima annulliamo l'effetto economico del risultato
  // precedente, poi applichiamo quello nuovo.
  // ============================================================

  bool settleAs(String betId, String newStatus) {
    final normalized = newStatus.toUpperCase().trim();

    if (normalized != 'WIN' &&
        normalized != 'LOSS' &&
        normalized != 'VOID' &&
        normalized != 'PENDING') {
      return false;
    }

    final index = _history.indexWhere((bet) => bet.id == betId);

    if (index < 0) {
      return false;
    }

    final bet = _history[index];

    // Rimuove dal bankroll l'effetto del vecchio risultato.
    // PENDING e VOID hanno profitLoss = 0.
    _currentBankroll -= bet.profitLoss;

    if (_currentBankroll < 0.0) {
      _currentBankroll = 0.0;
    }

    double newProfitLoss = 0.0;

    if (normalized == 'WIN') {
      newProfitLoss = bet.stakeAmount * (bet.odd - 1.0);
    } else if (normalized == 'LOSS') {
      newProfitLoss = -bet.stakeAmount;
    }

    _currentBankroll += newProfitLoss;

    _history[index] = bet.copyWith(
      status: normalized,
      profitLoss: newProfitLoss,
    );

    return true;
  }

  Future<bool> settleAsAndSave(String betId, String newStatus) async {
    final result = settleAs(betId, newStatus);

    if (result) {
      await save();
    }

    return result;
  }

  // ============================================================
  // ELIMINA GIOCATA
  // ============================================================
  //
  // Se la giocata era già stata chiusa, rimuoviamo prima
  // il suo effetto economico dal bankroll. Se era PENDING,
  // basta eliminarla: lo stake impegnato si libera da solo.
  // ============================================================

  bool deleteBet(String betId) {
    final index = _history.indexWhere((bet) => bet.id == betId);

    if (index < 0) {
      return false;
    }

    final bet = _history[index];

    _currentBankroll -= bet.profitLoss;

    if (_currentBankroll < 0.0) {
      _currentBankroll = 0.0;
    }

    _history.removeAt(index);

    return true;
  }

  Future<bool> deleteBetAndSave(String betId) async {
    final result = deleteBet(betId);

    if (result) {
      await save();
    }

    return result;
  }

  // ============================================================
  // SNAPSHOT
  // ============================================================

  BankrollSnapshot get snapshot {
    double totalStakePlaced = 0.0;

    double settledStakeForRoi = 0.0;

    double totalProfitLoss = 0.0;

    int wins = 0;
    int losses = 0;
    int voids = 0;
    int pending = 0;

    for (final bet in _history) {
      totalStakePlaced += bet.stakeAmount;

      totalProfitLoss += bet.profitLoss;

      if (bet.isWin) {
        wins++;

        settledStakeForRoi += bet.stakeAmount;

        continue;
      }

      if (bet.isLoss) {
        losses++;

        settledStakeForRoi += bet.stakeAmount;

        continue;
      }

      if (bet.isVoid) {
        voids++;
        continue;
      }

      pending++;
    }

    return BankrollSnapshot(
      initialBankroll: _initialBankroll,
      currentBankroll: _currentBankroll,
      lockedBankroll: lockedBankroll,
      availableBankroll: availableBankroll,
      totalStakePlaced: totalStakePlaced,
      settledStakeForRoi: settledStakeForRoi,
      totalProfitLoss: totalProfitLoss,
      bets: _history.length,
      wins: wins,
      losses: losses,
      voids: voids,
      pending: pending,
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int _findPendingIndex(String betId) {
    return _history.indexWhere((bet) => bet.id == betId && bet.isPending);
  }

  double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
