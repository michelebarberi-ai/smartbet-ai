import 'sofascore_fixture_service.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - SOFASCORE FIXTURE TEST');
  print('========================================');

  final service = SofaScoreFixtureService();

  try {
    final matches = await service.getUpcomingMatches(
      days: 7,
    );

    print('');
    print('========================================');
    print('RISULTATO');
    print('========================================');

    if (matches.isEmpty) {
      print('NESSUNA PARTITA FUTURA TROVATA');
      return;
    }

    print(
      'PARTITE TROVATE: ${matches.length}',
    );

    print('');

    for (final match in matches.take(30)) {
      print(
        '${match.date} | '
        '${match.homeTeam} - ${match.awayTeam} | '
        '${match.league}',
      );
    }

    print('');
    print('========================================');
    print('TEST COMPLETATO');
    print('========================================');
  } finally {
    service.dispose();
  }
}