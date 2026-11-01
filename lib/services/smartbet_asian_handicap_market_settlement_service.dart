import 'smartbet_asian_handicap_settlement_service.dart';

/// Riconosce esclusivamente i mercati asiatici full-time
/// nel formato interno canonico SmartBet.
class SmartBetAsianHandicapMarketSettlementService {
  const SmartBetAsianHandicapMarketSettlementService._();

  static SmartBetAsianSettlement? evaluate({
    required String market,
    required int homeGoals,
    required int awayGoals,
  }) {
    final normalized = market.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (normalized == 'DNB CASA' || normalized == 'DRAW NO BET CASA') {
      return SmartBetAsianHandicapSettlementService.drawNoBet(
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        side: SmartBetAsianSide.home,
      );
    }

    if (normalized == 'DNB OSPITE' || normalized == 'DRAW NO BET OSPITE') {
      return SmartBetAsianHandicapSettlementService.drawNoBet(
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        side: SmartBetAsianSide.away,
      );
    }

    final match = RegExp(
      r'^HCP ASIA (CASA|OSPITE) ([+-]?[0-9]+(?:\.[0-9]+)?)$',
    ).firstMatch(normalized);

    if (match == null) return null;

    final handicap = double.tryParse(match.group(2)!);

    if (handicap == null) return null;

    final settlement = SmartBetAsianHandicapSettlementService.evaluate(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      side: match.group(1) == 'CASA'
          ? SmartBetAsianSide.home
          : SmartBetAsianSide.away,
      handicap: handicap,
    );

    if (settlement == SmartBetAsianSettlement.unsupported) {
      return null;
    }

    return settlement;
  }
}
