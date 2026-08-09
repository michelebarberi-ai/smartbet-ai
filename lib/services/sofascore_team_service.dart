import 'dart:convert';

import 'package:http/http.dart' as http;

class SofaScoreTeam {
  final int id;
  final String name;
  final String slug;
  final String country;
  final String? logo;

  const SofaScoreTeam({
    required this.id,
    required this.name,
    required this.slug,
    required this.country,
    required this.logo,
  });
}

class SofaScoreTeamService {
  final http.Client _client;

  SofaScoreTeamService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://www.sofascore.com/api/v1';

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<String, SofaScoreTeam?> _cache = {};

  // ============================================================
  // CERCA SQUADRA
  // ============================================================

  Future<SofaScoreTeam?> findTeam(String teamName) async {
    final normalizedName = _normalizeTeamName(teamName);

    if (normalizedName.isEmpty) {
      print('SOFASCORE DEBUG: nome squadra vuoto');
      return null;
    }

    if (_cache.containsKey(normalizedName)) {
      print('SOFASCORE DEBUG: risultato preso dalla cache per "$teamName"');
      return _cache[normalizedName];
    }

    final encodedName = Uri.encodeComponent(teamName);

    final uri = Uri.parse('$_baseUrl/search/all?q=$encodedName');

    print('');
    print('========================================');
    print('SOFASCORE DEBUG');
    print('Squadra richiesta: $teamName');
    print('Nome normalizzato: $normalizedName');
    print('URL: $uri');
    print('========================================');

    try {
      final response = await _client.get(uri, headers: _headers);

      print('SOFASCORE STATUS CODE: ${response.statusCode}');
      print('SOFASCORE RESPONSE LENGTH: ${response.body.length}');

      print('SOFASCORE RESPONSE:');
      print(response.body);

      if (response.statusCode != 200) {
        print('SOFASCORE ERRORE HTTP: ${response.statusCode}');

        _cache[normalizedName] = null;
        return null;
      }

      dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (e) {
        print('SOFASCORE ERRORE JSON: $e');

        _cache[normalizedName] = null;
        return null;
      }

      print('SOFASCORE JSON TYPE: ${decoded.runtimeType}');

      if (decoded is! Map<String, dynamic>) {
        print('SOFASCORE: risposta non è una Map');

        _cache[normalizedName] = null;
        return null;
      }

      print('SOFASCORE JSON KEYS: ${decoded.keys.toList()}');

      final results = decoded['results'];

      print('SOFASCORE RESULTS TYPE: ${results.runtimeType}');

      if (results is! List) {
        print(
          'SOFASCORE: campo "results" non trovato '
          'o non è una lista',
        );

        _cache[normalizedName] = null;
        return null;
      }

      print('SOFASCORE RISULTATI TROVATI: ${results.length}');

      SofaScoreTeam? bestTeam;
      double bestScore = 0;

      for (final item in results) {
        print('');
        print('--- RISULTATO SOFASCORE ---');
        print(item);

        if (item is! Map<String, dynamic>) {
          print('Elemento ignorato: non è una Map');
          continue;
        }

        print('TYPE: ${item['type']}');

        final entity = item['entity'];

        if (entity is! Map<String, dynamic>) {
          print('Elemento ignorato: entity non presente');
          continue;
        }

        print('ENTITY: $entity');

        final type = item['type']?.toString();

        if (type != null && type != 'team') {
          print('Elemento ignorato: type = $type');
          continue;
        }

        final team = _parseTeam(entity);

        if (team == null) {
          print('Elemento ignorato: impossibile creare SofaScoreTeam');
          continue;
        }

        final score = _calculateTeamScore(teamName, team);

        print('SQUADRA CANDIDATA: ${team.name}');

        print('ID: ${team.id}');

        print('PAESE: ${team.country}');

        print('SCORE MATCHING: $score');

        if (score > bestScore) {
          bestScore = score;
          bestTeam = team;
        }
      }

      print('');
      print('========================================');
      print('SOFASCORE MIGLIOR RISULTATO');
      print('Squadra richiesta: $teamName');
      print('Miglior score: $bestScore');

      if (bestTeam != null) {
        print('Migliore squadra: ${bestTeam.name}');
        print('Migliore ID: ${bestTeam.id}');
      } else {
        print('Nessun candidato trovato');
      }

      print('========================================');

      if (bestTeam == null || bestScore < 0.70) {
        print('SOFASCORE: NESSUNA SQUADRA VALIDA');

        _cache[normalizedName] = null;
        return null;
      }

      _cache[normalizedName] = bestTeam;

      return bestTeam;
    } catch (e, stackTrace) {
      print('========================================');
      print('SOFASCORE ECCEZIONE');
      print(e);
      print(stackTrace);
      print('========================================');

      _cache[normalizedName] = null;
      return null;
    }
  }

  // ============================================================
  // PARSING
  // ============================================================

  SofaScoreTeam? _parseTeam(Map<String, dynamic> data) {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return null;
    }

    final name = data['name']?.toString().trim() ?? '';

    if (name.isEmpty) {
      return null;
    }

    final slug = data['slug']?.toString() ?? '';

    String country = '';

    final countryData = data['country'];

    if (countryData is Map<String, dynamic>) {
      country = countryData['name']?.toString() ?? '';
    }

    final logo = data['image']?.toString();

    return SofaScoreTeam(
      id: id,
      name: name,
      slug: slug,
      country: country,
      logo: logo,
    );
  }

  // ============================================================
  // SCORE DEL NOME
  // ============================================================

  double _calculateTeamScore(String requestedName, SofaScoreTeam team) {
    final requested = _normalizeTeamName(requestedName);

    final candidate = _normalizeTeamName(team.name);

    if (requested.isEmpty || candidate.isEmpty) {
      return 0;
    }

    if (requested == candidate) {
      return 1.0;
    }

    if (requested.contains(candidate) || candidate.contains(requested)) {
      return 0.90;
    }

    final requestedWords = requested.split(' ');

    final candidateWords = candidate.split(' ');

    int commonWords = 0;

    for (final word in requestedWords) {
      if (word.length < 3) {
        continue;
      }

      if (candidateWords.contains(word)) {
        commonWords++;
      }
    }

    if (commonWords >= 2) {
      return 0.85;
    }

    if (commonWords == 1) {
      return 0.70;
    }

    return 0;
  }

  // ============================================================
  // NORMALIZZAZIONE
  // ============================================================

  String _normalizeTeamName(String value) {
    var result = value.toLowerCase().trim();

    result = result
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');

    result = result
        .replaceAll(RegExp(r'\bfc\b'), '')
        .replaceAll(RegExp(r'\bafc\b'), '')
        .replaceAll(RegExp(r'\bac\b'), '')
        .replaceAll(RegExp(r'\bsc\b'), '')
        .replaceAll(RegExp(r'\bcalcio\b'), '')
        .replaceAll(RegExp(r'\bfootball club\b'), '')
        .replaceAll(RegExp(r'\bclub\b'), '');

    result = result
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return result;
  }

  // ============================================================
  // HEADERS
  // ============================================================

  Map<String, String> get _headers {
    return const {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 '
          '(iPhone; CPU iPhone OS 18_0 like Mac OS X) '
          'AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) '
          'Version/18.0 Mobile/15E148 Safari/604.1',
    };
  }

  // ============================================================
  // CONVERSIONE
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  // ============================================================
  // CACHE
  // ============================================================

  static void clearCache() {
    _cache.clear();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}
