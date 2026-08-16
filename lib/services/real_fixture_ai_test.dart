import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/match_model.dart';
import 'smartbet_ai_service.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - FUTURE FIXTURE AI TEST');
  print('========================================');

  const teamId = 876;

  final now = DateTime.now().toUtc();

  final client = http.Client();

  try {
    // ==========================================================
    // 1. CERCHIAMO LE FIXTURE DEL TEAM
    // ==========================================================

    final season = now.year;

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {'team': teamId.toString(), 'season': season.toString()},
    );

    print('');
    print('RICERCA FIXTURE');
    print('Team ID: $teamId');
    print('Stagione: $season');
    print('URL: $uri');

    final response = await client.get(
      uri,
      headers: {'x-apisports-key': ApiConfig.apiKey},
    );

    print('STATUS CODE: ${response.statusCode}');

    if (response.statusCode != 200) {
      print('');
      print('ERRORE API-FOOTBALL');
      print(response.body);
      return;
    }

    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic>) {
      print('RISPOSTA API NON VALIDA');
      return;
    }

    final errors = data['errors'];

    if (errors is Map && errors.isNotEmpty) {
      print('');
      print('API ERROR');
      print(errors);
      return;
    }

    final responseData = data['response'];

    if (responseData is! List || responseData.isEmpty) {
      print('');
      print('NESSUNA FIXTURE TROVATA');
      return;
    }

    print('');
    print(
      'FIXTURE TOTALI TROVATE: '
      '${responseData.length}',
    );

    // ==========================================================
    // 2. FILTRIAMO SOLO LE PARTITE FUTURE
    // ==========================================================

    final futureFixtures = <Map<String, dynamic>>[];

    for (final item in responseData) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final fixture = item['fixture'];

      if (fixture is! Map<String, dynamic>) {
        continue;
      }

      final dateString = fixture['date']?.toString();

      final fixtureDate = DateTime.tryParse(dateString ?? '');

      if (fixtureDate == null) {
        continue;
      }

      if (fixtureDate.toUtc().isAfter(now)) {
        futureFixtures.add(item);
      }
    }

    if (futureFixtures.isEmpty) {
      print('');
      print('NESSUNA FIXTURE FUTURA TROVATA');
      print('');
      print(
        'Il piano API potrebbe non rendere '
        'disponibile la stagione corrente.',
      );
      return;
    }

    // ==========================================================
    // 3. ORDINIAMO PER DATA
    // ==========================================================

    futureFixtures.sort((a, b) {
      final aDate = DateTime.parse(a['fixture']['date'].toString());

      final bDate = DateTime.parse(b['fixture']['date'].toString());

      return aDate.compareTo(bDate);
    });

    print('');
    print(
      'FIXTURE FUTURE TROVATE: '
      '${futureFixtures.length}',
    );

    // ==========================================================
    // 4. PRENDIAMO LA PROSSIMA PARTITA
    // ==========================================================

    final fixtureJson = futureFixtures.first;

    final match = MatchModel.fromApi(
      fixtureJson,
      country: 'Italy',
      countryCode: 'IT',
      leagueType: 'domestic',
      aiWeight: 0.70,
    );

    print('');
    print('========================================');
    print('PROSSIMA FIXTURE REALE');
    print('========================================');
    print('Fixture ID: ${match.fixtureId}');
    print('Casa: ${match.homeTeam}');
    print('Casa ID: ${match.homeTeamId}');
    print('Ospite: ${match.awayTeam}');
    print('Ospite ID: ${match.awayTeamId}');
    print('Competizione: ${match.league}');
    print('League ID: ${match.leagueId}');
    print('Data: ${match.date}');
    print('========================================');

    // ==========================================================
    // 5. AVVIO PIPELINE SMARTBET
    // ==========================================================

    final aiService = SmartBetAiService();

    try {
      final result = await aiService.analyzeMatch(match);

      print('');
      print('========================================');
      print('RISULTATO SMARTBET AI');
      print('========================================');
      print('SMART SCORE: ${result.smartScore}');
      print('1: ${result.homeProbability}%');
      print('X: ${result.drawProbability}%');
      print('2: ${result.awayProbability}%');
      print('PRONOSTICO: ${result.prediction}');
      print('VALUE BET: ${result.valueBet}');
      print('RISCHIO: ${result.risk}');
      print('');

      print('========================================');
      print('ANALISI COMPLETA');
      print('========================================');

      print(result.explanation);

      print('');
      print('========================================');
      print('TEST COMPLETATO');
      print('========================================');
    } finally {
      aiService.dispose();
    }
  } catch (e) {
    print('');
    print('========================================');
    print('ERRORE TEST');
    print('========================================');
    print(e);
  } finally {
    client.close();
  }
}
