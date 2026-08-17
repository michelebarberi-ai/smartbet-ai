import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static const String baseUrl = 'https://v3.football.api-sports.io';

  static String get apiKey {
    final key = dotenv.env['FOOTBALL_API_KEY'];

    if (key != null && key.trim().isNotEmpty) {
      return key.trim();
    }

    throw Exception('FOOTBALL_API_KEY non configurata.');
  }
}
