import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class UnionBresciaFixtureTest {
  const UnionBresciaFixtureTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - UNION BRESCIA FIXTURE TEST');
    print('========================================');

    final client = http.Client();

    try {
      await _testSeason(client: client, season: 2024);
    } finally {
      client.close();
    }

    print('');
    print('========================================');
    print('TEST COMPLETATO');
    print('========================================');
  }

  static Future<void> _testSeason({
    required http.Client client,
    required int season,
  }) async {
    print('');
    print('----------------------------------------');
    print('UNION BRESCIA');
    print('TEAM ID: 26356');
    print('STAGIONE: $season');
    print('----------------------------------------');

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/fixtures',
    ).replace(queryParameters: {'team': '26356', 'season': season.toString()});

    print('URL: $uri');

    try {
      final response = await client.get(
        uri,
        headers: {
          'x-apisports-key': ApiConfig.apiKey,
          'Accept': 'application/json',
        },
      );

      print('STATUS CODE: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('ERRORE HTTP');
        print(response.body);
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        print('RISPOSTA NON VALIDA');
        return;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('API ERROR:');
        print(errors);
        return;
      }

      final results = decoded['response'];

      if (results is! List || results.isEmpty) {
        print('');
        print('NESSUNA PARTITA TROVATA');
        return;
      }

      print('');
      print('PARTITE TROVATE: ${results.length}');

      int counter = 0;

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final fixture = item['fixture'];
        final teams = item['teams'];
        final league = item['league'];

        if (fixture is! Map<String, dynamic>) {
          continue;
        }

        if (teams is! Map<String, dynamic>) {
          continue;
        }

        final home = teams['home'];
        final away = teams['away'];

        if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
          continue;
        }

        final leagueData = league is Map<String, dynamic>
            ? league
            : <String, dynamic>{};

        final fixtureId = fixture['id'];

        final date = fixture['date']?.toString() ?? '';

        final homeName = home['name']?.toString() ?? '';

        final awayName = away['name']?.toString() ?? '';

        final leagueId = leagueData['id'];

        final leagueName = leagueData['name']?.toString() ?? '';

        final leagueType = leagueData['type']?.toString() ?? '';

        counter++;

        print('');
        print('PARTITA #$counter');
        print('  Fixture ID: $fixtureId');
        print('  Data: $date');
        print('  Casa: $homeName');
        print('  Ospite: $awayName');
        print('  League ID: $leagueId');
        print('  Competizione: $leagueName');
        print('  Tipo: $leagueType');

        if (counter >= 20) {
          print('');
          print('Mostrate le prime 20 partite.');
          break;
        }
      }
    } catch (e) {
      print('');
      print('ECCEZIONE: $e');
    }
  }
}
