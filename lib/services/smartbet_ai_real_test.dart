import '../models/match_model.dart';
import 'smartbet_ai_service.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - REAL AI INTEGRATION TEST');
  print('========================================');

  final match = MatchModel(
    fixtureId: 0,

    homeTeamId: 876,
    awayTeamId: 26356,

    homeTeam: 'Arezzo',
    awayTeam: 'Union Brescia',

    league: 'Coppa Italia Serie C',
    leagueId: 891,

    country: 'Italy',
    countryCode: 'IT',

    date: '2026-08-11',

    leagueType: 'Cup',

    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,

    aiWeight: 0.70,

    smartScore: 0,
    homeWin: 0,
    draw: 0,
    awayWin: 0,

    valueBet: '',

    odd: 0,
  );

  print('');
  print('PARTITA: ${match.homeTeam} - ${match.awayTeam}');
  print('HOME ID: ${match.homeTeamId}');
  print('AWAY ID: ${match.awayTeamId}');
  print('');

  final service = SmartBetAiService();

  try {
    final result = await service.analyzeMatch(match);

    print('');
    print('========================================');
    print('SMARTBET AI - RISULTATO FINALE');
    print('========================================');

    print('');
    print('SMART SCORE: ${result.smartScore}');
    print('1: ${result.homeProbability}%');
    print('X: ${result.drawProbability}%');
    print('2: ${result.awayProbability}%');
    print('PRONOSTICO: ${result.prediction}');
    print('VALUE BET: ${result.valueBet}');
    print('RISCHIO: ${result.risk}');

    print('');
    print('========================================');
    print('SPIEGAZIONE AI');
    print('========================================');
    print(result.explanation);

    print('');
    print('========================================');
    print('TEST COMPLETATO');
    print('========================================');
  } catch (e) {
    print('');
    print('========================================');
    print('ERRORE TEST AI');
    print('========================================');
    print(e);
  } finally {
    service.dispose();
  }
}
