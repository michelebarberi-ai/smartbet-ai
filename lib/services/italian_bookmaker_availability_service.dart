import 'dart:convert';

import 'package:http/http.dart' as http;

class ItalianBookmakerAvailability {
  final Set<int> quotedFixtureIds;
  final bool complete;
  final int pagesRead;
  final int pagesTotal;
  final DateTime verifiedAt;

  const ItalianBookmakerAvailability({
    required this.quotedFixtureIds,
    required this.complete,
    required this.pagesRead,
    required this.pagesTotal,
    required this.verifiedAt,
  });
}

/// La verifica è separata dall'analisi sportiva.
/// Presenza di un marchio nel feed NON garantisce che la stessa quota
/// sia effettivamente disponibile nell'account italiano del bookmaker.
class ItalianBookmakerAvailabilityService {
  const ItalianBookmakerAvailabilityService();

  static const _backend =
      'https://smartbet-ai-y6gw.onrender.com/football/italian-quoted-fixtures';
  static final _cache = <String, ItalianBookmakerAvailability>{};
  static final _inFlight = <String, Future<ItalianBookmakerAvailability>>{};

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<ItalianBookmakerAvailability> forDate(DateTime date) {
    final key = _day(date);
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.verifiedAt) <
            const Duration(hours: 3)) {
      return Future.value(cached);
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _load(key);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<ItalianBookmakerAvailability> _load(String key) async {
    final uri = Uri.parse(_backend).replace(queryParameters: {'date': key});
    final response = await http.get(uri).timeout(const Duration(seconds: 55));
    if (response.statusCode != 200) {
      throw StateError('Verifica palinsesto HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['success'] != true ||
        body['fixtureIds'] is! List) {
      throw const FormatException('Risposta palinsesto non valida');
    }
    final verifiedAt = DateTime.tryParse(body['verifiedAt']?.toString() ?? '');
    if (verifiedAt == null) {
      throw const FormatException('Manca data verifica quote');
    }
    final data = ItalianBookmakerAvailability(
      quotedFixtureIds: Set.unmodifiable({
        for (final x in body['fixtureIds'] as List)
          if (x is num && x.toInt() > 0) x.toInt(),
      }),
      complete: body['complete'] == true,
      pagesRead: (body['pagesRead'] as num?)?.toInt() ?? 0,
      pagesTotal: (body['pagesTotal'] as num?)?.toInt() ?? 0,
      verifiedAt: verifiedAt.toUtc(),
    );
    _cache[key] = data;
    return data;
  }
}
