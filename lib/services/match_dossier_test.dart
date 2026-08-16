import '../models/match_model.dart';
import 'match_dossier_builder.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - MATCH DOSSIER TEST');
  print('========================================');

  // ============================================================
  // PARTITA DI TEST
  // ============================================================

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

  // ============================================================
  // BUILDER
  // ============================================================

  final builder = MatchDossierBuilder();

  final dossier = await builder.build(match);

  // ============================================================
  // RISULTATO
  // ============================================================

  print('');
  print('========================================');
  print('RISULTATO TEST DOSSIER');
  print('========================================');

  if (dossier == null) {
    print('DOSSIER: NON CREATO');
    print('TEST FALLITO');
    print('========================================');
    return;
  }

  print('DOSSIER: CREATO');
  print('');

  print(
    'PARTITA: '
    '${dossier.homeTeam} - ${dossier.awayTeam}',
  );

  print('HOME ID: ${dossier.homeTeamId}');

  print('AWAY ID: ${dossier.awayTeamId}');

  print('COMPETIZIONE: ${dossier.competition}');

  print('COMPETITION ID: ${dossier.competitionId}');

  print('');

  print('DATI CASA:');
  print(dossier.homeStatistics);

  print('');

  print('DATI OSPITE:');
  print(dossier.awayStatistics);

  print('');

  print('RENDIMENTO CASA:');
  print(dossier.homeVenue);

  print('');

  print('RENDIMENTO TRASFERTA:');
  print(dossier.awayVenue);

  print('');

  print(
    'DATA CONFIDENCE: '
    '${dossier.dataConfidence}%',
  );

  print(
    'PRE-MATCH ONLY: '
    '${dossier.preMatchOnly}',
  );

  print('');

  print('========================================');
  print('TEST DOSSIER COMPLETATO');
  print('========================================');
}
