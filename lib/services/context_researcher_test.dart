import '../models/match_model.dart';
import 'context_researcher.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - CONTEXT RESEARCHER TEST');
  print('========================================');

  final match = MatchModel(
    fixtureId: 1227639,

    homeTeamId: 1708,
    awayTeamId: 876,

    homeTeam: 'Vis Pesaro',
    awayTeam: 'Arezzo',

    league: 'Coppa Italia Serie C',
    leagueId: 891,

    country: 'Italy',
    countryCode: 'IT',

    date: '2024-08-11T19:00:00+00:00',

    leagueType: 'cup',

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

  final researcher = ContextResearcher();

  final context = await researcher.research(match);

  print('');
  print('========================================');
  print('RISULTATO CONTEXT RESEARCHER');
  print('========================================');

  print('');
  print('FORMA CASA:');
  print(context.recentMatchesHome);

  print('');
  print('FORMA OSPITE:');
  print(context.recentMatchesAway);

  print('');
  print('HEAD TO HEAD:');
  print(context.headToHead);

  print('');
  print('ASSENZE CASA:');
  print(context.injuriesHome);

  print('');
  print('ASSENZE OSPITE:');
  print(context.injuriesAway);

  print('');
  print('FORMAZIONE CASA:');
  print(context.probableLineupsHome);

  print('');
  print('FORMAZIONE OSPITE:');
  print(context.probableLineupsAway);

  print('');
  print('CONTEXT CONFIDENCE:');
  print('${context.confidence}%');

  print('');
  print('========================================');
  print('TEST COMPLETATO');
  print('========================================');
}