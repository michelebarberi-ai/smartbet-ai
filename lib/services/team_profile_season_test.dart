import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class TeamProfileSeasonTest {
  const TeamProfileSeasonTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - SEASON ACCESS TEST');
    print('========================================');

    final client = http.Client();

    try {
      await _testTeam(client: client, teamId: 876, teamName: 'Arezzo');

      await _testTeam(client: client, teamId: 26356, teamName: 'Union Brescia');
    } finally {
      client.close();
    }

    print('');
    print('========================================');
    print('TEST STAGIONI COMPLETATO');
    print('========================================');
  }

  // ============================================================
  // TEST SQUADRA
  // ============================================================

  static Future<void> _testTeam({
    required http.Client client,
    required int teamId,
    required String teamName,
  }) async {
    print('');
    print('========================================');
    print('SQUADRA: $teamName');
    print('TEAM ID: $teamId');
    print('========================================');

    await _testSeason(
      client: client,
      teamId: teamId,
      teamName: teamName,
      season: 2025,
    );

    await _testSeason(
      client: client,
      teamId: teamId,
      teamName: teamName,
      season: 2024,
    );
  }

  // ============================================================
  // TEST SINGOLA STAGIONE
  // ============================================================

  static Future<void> _testSeason({
    required http.Client client,
    required int teamId,
    required String teamName,
    required int season,
  }) async {
    print('');
    print('----------------------------------------');
    print('STAGIONE: $season');
    print('SQUADRA: $teamName');
    print('----------------------------------------');

    final uri = Uri.parse('${ApiConfig.baseUrl}/leagues').replace(
      queryParameters: {'team': teamId.toString(), 'season': season.toString()},
    );

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
        print('NESSUNA COMPETIZIONE TROVATA');
        return;
      }

      print('COMPETIZIONI TROVATE: ${results.length}');

      int validLeagues = 0;

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final league = item['league'];

        if (league is! Map<String, dynamic>) {
          continue;
        }

        final id = league['id'];

        final name = league['name']?.toString() ?? '';

        final type = league['type']?.toString() ?? '';

        final country = league['country']?.toString() ?? '';

        if (id is! int || id <= 0) {
          continue;
        }

        validLeagues++;

        print('');
        print('COMPETIZIONE #$validLeagues');
        print('  League ID: $id');
        print('  Nome: $name');
        print('  Tipo: $type');
        print('  Paese: $country');
      }

      if (validLeagues == 0) {
        print('');
        print('NESSUN LEAGUE VALIDO');
      } else {
        print('');
        print('STAGIONE $season DISPONIBILE');
      }
    } catch (e) {
      print('');
      print('ECCEZIONE: $e');
    }
  }
}
