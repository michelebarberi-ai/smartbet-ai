import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class FeralpiSaloTest {
  const FeralpiSaloTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - FERALPISALO HISTORY TEST');
    print('========================================');

    final client = http.Client();

    try {
      await _searchTeam(client);

      await _testFixtures(client: client, season: 2024);
    } finally {
      client.close();
    }

    print('');
    print('========================================');
    print('TEST COMPLETATO');
    print('========================================');
  }

  // ============================================================
  // CERCA FERALPISALO
  // ============================================================

  static Future<void> _searchTeam(http.Client client) async {
    print('');
    print('RICERCA: FeralpiSalò');

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/teams',
    ).replace(queryParameters: {'search': 'FeralpiSalo'});

    try {
      final response = await client.get(uri, headers: _headers);

      print('STATUS CODE: ${response.statusCode}');

      if (response.statusCode != 200) {
        print(response.body);
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        print('RISPOSTA NON VALIDA');
        return;
      }

      final results = decoded['response'];

      if (results is! List || results.isEmpty) {
        print('FERALPISALO NON TROVATA');
        return;
      }

      print('RISULTATI: ${results.length}');

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final team = item['team'];

        if (team is! Map<String, dynamic>) {
          continue;
        }

        print('');
        print('SQUADRA');
        print('ID: ${team['id']}');
        print('Nome: ${team['name']}');
        print('Paese: ${team['country']}');
      }
    } catch (e) {
      print('ERRORE: $e');
    }
  }

  // ============================================================
  // FIXTURE 2024
  // ============================================================

  static Future<void> _testFixtures({
    required http.Client client,
    required int season,
  }) async {
    print('');
    print('----------------------------------------');
    print('RICERCA FIXTURE FERALPISALO');
    print('STAGIONE: $season');
    print('----------------------------------------');

    // L'ID verrà ricavato dalla ricerca sopra.
    final teamId = await _getTeamId(client);

    if (teamId == null) {
      print('IMPOSSIBILE RECUPERARE TEAM ID');
      return;
    }

    print('FERALPISALO TEAM ID: $teamId');

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {'team': teamId.toString(), 'season': season.toString()},
    );

    print('URL: $uri');

    try {
      final response = await client.get(uri, headers: _headers);

      print('FIXTURES STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
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

      final fixtures = decoded['response'];

      if (fixtures is! List || fixtures.isEmpty) {
        print('NESSUNA PARTITA TROVATA');
        return;
      }

      print('');
      print('PARTITE TROVATE: ${fixtures.length}');
      print('');

      int counter = 0;

      for (final item in fixtures) {
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

        counter++;

        print('PARTITA #$counter');
        print('Fixture ID: ${fixture['id']}');
        print('Data: ${fixture['date']}');
        print('Casa: ${home['name']}');
        print('Ospite: ${away['name']}');
        print('League ID: ${leagueData['id']}');
        print('Competizione: ${leagueData['name']}');
        print('Tipo: ${leagueData['type']}');
        print('');

        if (counter >= 20) {
          print('Mostrate le prime 20 partite.');
          break;
        }
      }
    } catch (e) {
      print('ERRORE FIXTURES: $e');
    }
  }

  // ============================================================
  // RECUPERA ID
  // ============================================================

  static Future<int?> _getTeamId(http.Client client) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/teams',
    ).replace(queryParameters: {'search': 'FeralpiSalo'});

    try {
      final response = await client.get(uri, headers: _headers);

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final results = decoded['response'];

      if (results is! List) {
        return null;
      }

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final team = item['team'];

        if (team is! Map<String, dynamic>) {
          continue;
        }

        final name = team['name']?.toString().toLowerCase() ?? '';

        if (name.contains('feralpi')) {
          final id = team['id'];

          if (id is int && id > 0) {
            return id;
          }
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // HEADERS
  // ============================================================

  static Map<String, String> get _headers {
    return {'x-apisports-key': ApiConfig.apiKey, 'Accept': 'application/json'};
  }
}
