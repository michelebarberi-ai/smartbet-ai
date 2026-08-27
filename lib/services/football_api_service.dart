import 'dart:convert';

import 'package:http/http.dart' as http;

class FootballApiService {
  static const String _backendUrl = 'https://smartbet-ai-y6gw.onrender.com';

  Future<List<dynamic>> getNextMatches() async {
    final now = DateTime.now();

    return getMatchesByDate(now);
  }

  Future<List<dynamic>> getMatchesByDate(DateTime selectedDate) async {
    final date =
        '${selectedDate.year.toString().padLeft(4, '0')}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '$_backendUrl/football/fixtures',
    ).replace(queryParameters: {'date': date, 'timezone': 'Europe/Rome'});

    print('');
    print('========================================');
    print('SMARTBET - PARTITE VIA BACKEND');
    print('DATA: $date');
    print('URL: $uri');
    print('========================================');

    final response = await http.get(uri);

    print('STATUS BACKEND: ${response.statusCode}');

    print(
      'CACHE BACKEND: '
      '${response.headers['x-smartbet-cache'] ?? 'N/D'}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Errore backend ${response.statusCode}\n'
        '${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic>) {
      throw Exception('Risposta backend fixtures non valida.');
    }

    final errors = data['errors'];

    if (errors is Map && errors.isNotEmpty) {
      throw Exception('Errore API-Football: $errors');
    }

    final fixtures = (data['response'] as List<dynamic>?) ?? <dynamic>[];

    print(
      'PARTITE RESTITUITE: '
      '${fixtures.length}',
    );

    print('========================================');

    return fixtures;
  }
}
