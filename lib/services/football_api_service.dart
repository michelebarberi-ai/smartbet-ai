import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class FootballApiService {
  // ============================================================
  // PARTITE DI OGGI
  // ============================================================

  Future<List<dynamic>> getNextMatches() async {
    final now = DateTime.now();

    return getMatchesByDate(now);
  }

  // ============================================================
  // PARTITE PER DATA SPECIFICA
  // ============================================================

  Future<List<dynamic>> getMatchesByDate(DateTime selectedDate) async {
    final date =
        "${selectedDate.year.toString().padLeft(4, '0')}-"
        "${selectedDate.month.toString().padLeft(2, '0')}-"
        "${selectedDate.day.toString().padLeft(2, '0')}";

    final uri = Uri.parse(
      "${ApiConfig.baseUrl}/fixtures",
    ).replace(queryParameters: {"date": date, "timezone": "Europe/Rome"});

    print('');
    print('========================================');
    print('SMARTBET - TEST PARTITE');
    print('DATA: $date');
    print('URL: $uri');
    print('========================================');

    final response = await http.get(
      uri,
      headers: {"x-apisports-key": ApiConfig.apiKey},
    );

    print("STATUS CODE: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception(
        "Errore API ${response.statusCode}\n"
        "${response.body}",
      );
    }

    final data = jsonDecode(response.body);

    print("ERRORS API: ${data["errors"]}");

    final fixtures = (data["response"] as List<dynamic>?) ?? [];

    print(
      "PARTITE RESTITUITE DA API: "
      "${fixtures.length}",
    );

    for (final fixture in fixtures.take(10)) {
      print(
        "${fixture["teams"]?["home"]?["name"]} - "
        "${fixture["teams"]?["away"]?["name"]}",
      );
    }

    print('========================================');

    return fixtures;
  }
}
