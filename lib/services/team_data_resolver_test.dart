import 'team_data_resolver.dart';

class TeamDataResolverTest {
  const TeamDataResolverTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - TEAM DATA RESOLVER TEST');
    print('========================================');

    final resolver = TeamDataResolver();

    try {
      await _test(resolver: resolver, teamId: 876, teamName: 'Arezzo');

      await _test(resolver: resolver, teamId: 26356, teamName: 'Union Brescia');
    } finally {
      resolver.dispose();
    }

    print('');
    print('========================================');
    print('RESOLVER TEST COMPLETATO');
    print('========================================');
  }

  static Future<void> _test({
    required TeamDataResolver resolver,
    required int teamId,
    required String teamName,
  }) async {
    print('');
    print('========================================');
    print('TEST: $teamName');
    print('ID: $teamId');
    print('========================================');

    final data = await resolver.resolveTeam(teamId: teamId, teamName: teamName);

    if (data == null) {
      print('');
      print('❌ NESSUN DATO RISOLTO');
      return;
    }

    print('');
    print('----------------------------------------');
    print('RISULTATO RESOLVER');
    print('----------------------------------------');

    print('Squadra: ${data.teamName}');
    print('Team ID: ${data.teamId}');

    print('');
    print('FONTE DATI:');
    print(data.dataSource);

    print('');
    print('SQUADRA ORIGINALE:');
    print(data.sourceTeamName);

    print('SOURCE ID:');
    print(data.sourceTeamId);

    print('');
    print('STAGIONE: ${data.season}');
    print('LEAGUE ID: ${data.leagueId}');
    print('CAMPIONATO: ${data.leagueName}');

    print('');
    print('PARTITE: ${data.matchesPlayed}');
    print('VITTORIE: ${data.wins}');
    print('PAREGGI: ${data.draws}');
    print('SCONFITTE: ${data.losses}');

    print('');
    print('GOL FATTI: ${data.goalsFor}');
    print('GOL SUBITI: ${data.goalsAgainst}');

    print('');
    print(
      'MEDIA GOL: '
      '${data.goalsPerMatch.toStringAsFixed(2)}',
    );

    print(
      'MEDIA GOL SUBITI: '
      '${data.concededPerMatch.toStringAsFixed(2)}',
    );

    print('');
    print(
      'CASA: '
      '${data.homeWins} V / '
      '${data.homeDraws} X / '
      '${data.homeLosses} S',
    );

    print(
      'TRASFERTA: '
      '${data.awayWins} V / '
      '${data.awayDraws} X / '
      '${data.awayLosses} S',
    );

    print('');
    print(
      'CONFIDENCE: '
      '${(data.confidence * 100).toStringAsFixed(0)}%',
    );

    print(
      'AFFIDABILE: '
      '${data.isReliable}',
    );

    print('----------------------------------------');
  }
}
