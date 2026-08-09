import 'historical_team_service.dart';

class HistoricalTeamDebugTest {
  const HistoricalTeamDebugTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - HISTORICAL TEAM TEST');
    print('========================================');

    final service = HistoricalTeamService();

    try {
      // --------------------------------------------------------
      // FERALPISALO 2024
      // --------------------------------------------------------

      final data = await service.getHistoricalData(
        teamId: 884,
        teamName: 'Feralpisalo',
        season: 2024,
        leagueId: 138,
        leagueName: 'Serie C - Girone A',
      );

      print('');

      if (data == null) {
        print('❌ NESSUN DATO STORICO');
        return;
      }

      print('========================================');
      print('STORICO TROVATO');
      print('========================================');

      print(
        'Squadra originale: '
        '${data.originalTeamName}',
      );

      print(
        'Team ID: '
        '${data.originalTeamId}',
      );

      print(
        'Stagione: '
        '${data.season}',
      );

      print(
        'Campionato: '
        '${data.leagueName}',
      );

      print('');
      print('PARTITE: ${data.matchesPlayed}');
      print('VITTORIE: ${data.wins}');
      print('PAREGGI: ${data.draws}');
      print('SCONFITTE: ${data.losses}');

      print('');
      print('GOL FATTI: ${data.goalsFor}');
      print(
        'GOL SUBITI: '
        '${data.goalsAgainst}',
      );

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
        'WIN RATE: '
        '${(data.winRate * 100).toStringAsFixed(1)}%',
      );

      print(
        'HOME WIN RATE: '
        '${(data.homeWinRate * 100).toStringAsFixed(1)}%',
      );

      print(
        'AWAY WIN RATE: '
        '${(data.awayWinRate * 100).toStringAsFixed(1)}%',
      );

      print('');
      print('========================================');
      print('TEST OK');
      print('========================================');
    } finally {
      service.dispose();
    }
  }
}
