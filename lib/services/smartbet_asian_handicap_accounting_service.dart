import 'smartbet_asian_handicap_settlement_service.dart';

/// Ripartizione di una puntata unitaria.
/// Non modifica lo storico né i risultati del learning.
class SmartBetAsianHandicapAccounting {
  final SmartBetAsianSettlement settlement;
  final double winningFraction;
  final double refundedFraction;
  final double losingFraction;

  const SmartBetAsianHandicapAccounting({
    required this.settlement,
    required this.winningFraction,
    required this.refundedFraction,
    required this.losingFraction,
  });

  /// Profitto netto per una puntata unitaria.
  /// La quota deve provenire dallo snapshot del pronostico.
  double? profitUnitsForDecimalOdd(double? odd) {
    if (odd == null || !odd.isFinite || odd <= 1.0) {
      return null;
    }

    return winningFraction * (odd - 1.0) - losingFraction;
  }

  /// Ritorno totale, inclusa la quota di capitale restituita.
  double? returnedUnitsForDecimalOdd(double? odd) {
    final profit = profitUnitsForDecimalOdd(odd);
    return profit == null ? null : 1.0 + profit;
  }
}

class SmartBetAsianHandicapAccountingService {
  const SmartBetAsianHandicapAccountingService._();

  static SmartBetAsianHandicapAccounting? fromSettlement(
    SmartBetAsianSettlement settlement,
  ) {
    switch (settlement) {
      case SmartBetAsianSettlement.win:
        return const SmartBetAsianHandicapAccounting(
          settlement: SmartBetAsianSettlement.win,
          winningFraction: 1.0,
          refundedFraction: 0.0,
          losingFraction: 0.0,
        );
      case SmartBetAsianSettlement.halfWin:
        return const SmartBetAsianHandicapAccounting(
          settlement: SmartBetAsianSettlement.halfWin,
          winningFraction: 0.5,
          refundedFraction: 0.5,
          losingFraction: 0.0,
        );
      case SmartBetAsianSettlement.push:
        return const SmartBetAsianHandicapAccounting(
          settlement: SmartBetAsianSettlement.push,
          winningFraction: 0.0,
          refundedFraction: 1.0,
          losingFraction: 0.0,
        );
      case SmartBetAsianSettlement.halfLoss:
        return const SmartBetAsianHandicapAccounting(
          settlement: SmartBetAsianSettlement.halfLoss,
          winningFraction: 0.0,
          refundedFraction: 0.5,
          losingFraction: 0.5,
        );
      case SmartBetAsianSettlement.loss:
        return const SmartBetAsianHandicapAccounting(
          settlement: SmartBetAsianSettlement.loss,
          winningFraction: 0.0,
          refundedFraction: 0.0,
          losingFraction: 1.0,
        );
      case SmartBetAsianSettlement.unsupported:
        return null;
    }
  }

  static SmartBetAsianHandicapAccounting? evaluate({
    required int homeGoals,
    required int awayGoals,
    required SmartBetAsianSide side,
    required double handicap,
  }) {
    final settlement = SmartBetAsianHandicapSettlementService.evaluate(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      side: side,
      handicap: handicap,
    );

    return fromSettlement(settlement);
  }
}
