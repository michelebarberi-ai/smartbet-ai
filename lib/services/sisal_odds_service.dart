import 'odds_service.dart';
import 'goalvdline_quote_policy.dart';

/// Boundary dedicato alle quote Sisal.
///
/// La schermata Schedina AI dipende solo da questo servizio. L'implementazione
/// attuale usa il provider quote esistente e richiede esplicitamente Sisal.
/// Quando verrà collegato un provider che espone realmente Sisal, la modifica
/// resterà confinata qui e non richiederà cambi al motore della schedina.
class SisalOddsService {
  static const String bookmakerName = GoalVdLineQuotePolicy.bookmaker;

  final OddsService _oddsService;

  SisalOddsService({OddsService? oddsService})
    : _oddsService = oddsService ?? OddsService();

  Future<FixtureMarketOdds?> getFixtureMarketOdds({required int fixtureId}) async {
    final quotes = await _oddsService.getFixtureMarketOdds(
      fixtureId: fixtureId, bookmakerName: bookmakerName,
    );
    if (quotes == null) return null;
    // Defense-in-depth, including injected providers. Never relabel
    // a different bookmaker's quote as Sisal or fabricate missing values.
    if (quotes.bestByOutcome.values.any((odd) =>
        !GoalVdLineQuotePolicy.isSisal(odd.bookmakerName))) return null;
    return quotes;
  }

  void dispose() {
    _oddsService.dispose();
  }
}
