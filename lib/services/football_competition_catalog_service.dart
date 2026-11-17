import 'dart:convert';

import 'package:http/http.dart' as http;

/// Catalogo stagionale API-Football: NON rappresenta le partite oggi,
/// le quote disponibili, né una previsione idonea.
class FootballCompetitionCatalogEntry {
  final int id;
  final String name;
  final String country;
  final String type;

  const FootballCompetitionCatalogEntry({
    required this.id,
    required this.name,
    required this.country,
    required this.type,
  });

  String get selectionKey => 'id:$id';
}

class FootballCompetitionCatalogService {
  const FootballCompetitionCatalogService();

  static const _endpoint =
      'https://smartbet-ai-y6gw.onrender.com/football/leagues';

  static List<FootballCompetitionCatalogEntry>? _cached;
  static DateTime? _cachedAt;

  Future<List<FootballCompetitionCatalogEntry>> load() async {
    final now = DateTime.now().toUtc();
    if (_cached != null && _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(hours: 24)) {
      return _cached!;
    }

    final response = await http.get(Uri.parse(_endpoint))
        .timeout(const Duration(seconds: 16));
    if (response.statusCode != 200) {
      throw StateError('Catalogo campionati HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['success'] != true ||
        decoded['response'] is! List) {
      throw const FormatException('Catalogo competizioni non valido');
    }

    final result = <FootballCompetitionCatalogEntry>[];
    final seen = <int>{};
    for (final item in decoded['response'] as List) {
      if (item is! Map) continue;
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final name = item['name']?.toString().trim() ?? '';
      final country = item['country']?.toString().trim() ?? '';
      final type = item['type']?.toString().trim() ?? '';
      if (id <= 0 || name.isEmpty || !seen.add(id)) continue;
      result.add(FootballCompetitionCatalogEntry(
        id: id, name: name,
        country: country.isEmpty ? 'World' : country, type: type,
      ));
    }
    if (result.isEmpty) throw const FormatException('Catalogo senza competizioni');
    _cached = List.unmodifiable(result);
    _cachedAt = now;
    return _cached!;
  }
}
