enum SmartBetAsianSide { home, away }

enum SmartBetAsianSettlement { win, halfWin, push, halfLoss, loss, unsupported }

/// Liquidazione Handicap asiatico full-time.
/// Le linee ai quarti sono suddivise in due mezze puntate.
class SmartBetAsianHandicapSettlementService {
  const SmartBetAsianHandicapSettlementService._();

  static SmartBetAsianSettlement evaluate({
    required int homeGoals,
    required int awayGoals,
    required SmartBetAsianSide side,
    required double handicap,
  }) {
    if (homeGoals < 0 ||
        awayGoals < 0 ||
        !handicap.isFinite ||
        handicap.abs() > 5) {
      return SmartBetAsianSettlement.unsupported;
    }

    final quarterValue = handicap * 4;
    final quarterUnits = quarterValue.round();

    // Accettiamo esclusivamente linee multiple di 0.25.
    if ((quarterValue - quarterUnits).abs() > 1e-8) {
      return SmartBetAsianSettlement.unsupported;
    }

    final difference = side == SmartBetAsianSide.home
        ? homeGoals - awayGoals
        : awayGoals - homeGoals;

    // Le linee dispari in quarti, per esempio -0.75,
    // diventano due mezze puntate: -0.5 e -1.0.
    final lines = quarterUnits.isOdd
        ? <int>[quarterUnits - 1, quarterUnits + 1]
        : <int>[quarterUnits];

    var total = 0;

    for (final line in lines) {
      final adjusted = difference * 4 + line;

      if (adjusted > 0) {
        total++;
      } else if (adjusted < 0) {
        total--;
      }
    }

    if (lines.length == 1) {
      if (total > 0) return SmartBetAsianSettlement.win;
      if (total < 0) return SmartBetAsianSettlement.loss;
      return SmartBetAsianSettlement.push;
    }

    switch (total) {
      case 2:
        return SmartBetAsianSettlement.win;
      case 1:
        return SmartBetAsianSettlement.halfWin;
      case 0:
        return SmartBetAsianSettlement.push;
      case -1:
        return SmartBetAsianSettlement.halfLoss;
      case -2:
        return SmartBetAsianSettlement.loss;
      default:
        return SmartBetAsianSettlement.unsupported;
    }
  }

  /// Draw No Bet: handicap asiatico zero.
  static SmartBetAsianSettlement drawNoBet({
    required int homeGoals,
    required int awayGoals,
    required SmartBetAsianSide side,
  }) {
    return evaluate(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      side: side,
      handicap: 0,
    );
  }
}
