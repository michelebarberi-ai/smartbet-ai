import 'odds_service.dart';

/// Boundary dedicato alle quote Sisal.
///
/// La schermata Schedina AI dipende solo da questo servizio. L'implementazione
/// attuale usa il provider quote esistente e richiede esplicitamente Sisal.
/// Quando verrà collegato un provider che espone realmente Sisal, la modifica
/// resterà confinata qui e non richiederà cambi al motore della schedina.
class SisalOddsService {
  static const String bookmakerName = 'Sisal';

  final OddsService _oddsService;

  SisalOddsService({OddsService? oddsService})
    : _oddsService = oddsService ?? OddsService();

  Future<FixtureMarketOdds?> getFixtureMarketOdds({required int fixtureId}) {
    return _oddsService.getFixtureMarketOdds(
      fixtureId: fixtureId,
      bookmakerName: bookmakerName,
    );
  }

  void dispose() {
    _oddsService.dispose();
  }
}
