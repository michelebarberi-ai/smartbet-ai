import 'dart:convert';
import 'package:http/http.dart' as http;

class FootballApiService {
  Future<List<dynamic>> getTodayMatches() async {
    // Per ora è un placeholder.
    // Nel prossimo step metteremo l'URL reale.

    final response = await http.get(Uri.parse("https://example.com"));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    return [];
  }
}
