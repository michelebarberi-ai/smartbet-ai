import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_dossier.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/european_league_strength_service.dart';
import 'package:smartbet_ai_new/services/match_dossier_builder.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

final _match = MatchModel(
  fixtureId: 981001,
  homeTeamId: 301,
  awayTeamId: 302,
  homeTeam: 'Squadra Casa',
  awayTeam: 'Squadra Ospite',
  league: 'Serie A',
  leagueId: 135,
  country: 'Italia',
  countryCode: 'IT',
  date: '2026-11-17T18:00:00Z',
  leagueType: 'domestic',
  isEuropeanCup: false,
  isFriendly: false,
  isNational: false,
  aiWeight: 0.90,
  smartScore: 0,
  homeWin: 0,
  draw: 0,
  awayWin: 0,
  valueBet: '',
  odd: 0.0,
);

const _homeStatistics = <String, dynamic>{
  'matchesPlayed': 12,
  'wins': 7,
  'draws': 3,
  'goalsPerMatch': 1.7,
  'concededPerMatch': 0.9,
  'confidence': 80,
};
const _awayStatistics = <String, dynamic>{
  'matchesPlayed': 12,
  'wins': 3,
  'draws': 4,
  'goalsPerMatch': 1.1,
  'concededPerMatch': 1.5,
  'confidence': 80,
};
const _dossier = MatchDossier(
  fixtureId: 981001,
  homeTeam: 'Squadra Casa',
  awayTeam: 'Squadra Ospite',
  homeTeamId: 301,
  awayTeamId: 302,
  matchDate: '2026-11-17T18:00:00Z',
  competition: 'Serie A',
  competitionId: 135,
  country: 'Italia',
  homeCurrentLeague: 'Serie A',
  homeCurrentLeagueId: 135,
  awayCurrentLeague: 'Serie A',
  awayCurrentLeagueId: 135,
  homeStatistics: _homeStatistics,
  homeForm: <String, dynamic>{},
  homeVenue: <String, dynamic>{'matches': 6, 'wins': 4, 'draws': 1},
  awayStatistics: _awayStatistics,
  awayForm: <String, dynamic>{},
  awayVenue: <String, dynamic>{'matches': 6, 'wins': 1, 'draws': 2},
  news: <String>[],
  injuries: <String>[],
  suspensions: <String>[],
  probableLineups: <String>[],
  marketInformation: <String>[],
  headToHead: <String>[],
  dataConfidence: 80,
  preMatchOnly: true,
);

class _UnusedLeagueStrength extends Fake implements EuropeanLeagueStrengthService {}

class _StaticDossier extends Fake implements MatchDossierBuilder {
  @override
  Future<MatchDossier?> build(
    MatchModel match, {
    bool backtestSafe = false,
    int backtestCurrentSeasonMinMatches = 3,
  }) async => _dossier;
}

class _QuotesStub extends Fake implements OddsService {
  _QuotesStub({this.throwError = false, this.odds});
  final bool throwError;
  final FixtureMarketOdds? odds;
  String? requestedBookmaker;
  int calls = 0;

  @override
  Future<FixtureMarketOdds?> getFixtureMarketOdds({
    required int fixtureId,
    String? bookmakerName,
  }) async {
    calls++;
    requestedBookmaker = bookmakerName;
    if (throwError) throw StateError('Feed quote fuori servizio');
    return odds;
  }
}

FixtureMarketOdds _quoted(double price) => FixtureMarketOdds(
  fixtureId: _match.fixtureId,
  matchWinner: null,
  bookmakerCount: 1,
  bestByOutcome: {
    '1': BestOdd(
      outcome: '1',
      odd: price,
      bookmakerId: 900,
      bookmakerName: 'Bookmaker di prova',
    ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B55: Diego mantiene previsione e mercati quando il feed quote fallisce', () async {
    final odds = _QuotesStub(throwError: true);
    final engine = DiegoAiService(
      dossierBuilder: _StaticDossier(),
      leagueStrengthService: _UnusedLeagueStrength(),
      oddsService: odds,
    );
    final result = await engine.analyze(_match, simulations: 1000);
    expect(result, isNotNull);
    expect(result!.marketOdds, isNull);
    expect(result.markets, isNotEmpty);
    expect(result.homeProbability.isFinite, isTrue);
    expect(result.drawProbability.isFinite, isTrue);
    expect(result.awayProbability.isFinite, isTrue);
    expect(result.homeProbability + result.drawProbability + result.awayProbability,
        closeTo(1, 1e-10));
    expect(odds.calls, 1);
    expect(odds.requestedBookmaker, isNull);
  });

  test('B55: cambiare solo la quota non cambia neanche una probabilita Diego', () async {
    final low = _QuotesStub(odds: _quoted(1.08));
    final high = _QuotesStub(odds: _quoted(4.50));
    final first = await DiegoAiService(
      dossierBuilder: _StaticDossier(),
      leagueStrengthService: _UnusedLeagueStrength(),
      oddsService: low,
    ).analyze(_match, simulations: 1000);
    final second = await DiegoAiService(
      dossierBuilder: _StaticDossier(),
      leagueStrengthService: _UnusedLeagueStrength(),
      oddsService: high,
    ).analyze(_match, simulations: 1000);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.homeProbability, second!.homeProbability);
    expect(first.drawProbability, second.drawProbability);
    expect(first.awayProbability, second.awayProbability);
    for (var i = 0; i < first.markets.length; i++) {
      expect(first.markets[i].market, second.markets[i].market);
      expect(first.markets[i].probability, second.markets[i].probability);
    }
    expect(low.requestedBookmaker, isNull);
    expect(high.requestedBookmaker, isNull);
    expect(first.marketOdds!.bestByOutcome['1']!.odd, 1.08);
    expect(second.marketOdds!.bestByOutcome['1']!.odd, 4.50);
  });
}
