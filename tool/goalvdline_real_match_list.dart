// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';

Future<void> main() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  print('');
  print('============================================================');
  print('GOALVDLINE - PARTITE REALI DISPONIBILI');
  print('============================================================');

  final all = <MatchModel>[];

  try {
    final todayMatches = await MatchRepository.getTodayMatches();
    all.addAll(todayMatches);
  } catch (e) {
    print('Errore recupero partite di oggi: $e');
  }

  try {
    final tomorrowMatches = await MatchRepository.getMatchesByDate(tomorrow);
    all.addAll(tomorrowMatches);
  } catch (e) {
    print('Errore recupero partite di domani: $e');
  }

  final unique = <int, MatchModel>{};

  for (final match in all) {
    if (match.fixtureId <= 0 || !match.hasTeamIds) {
      continue;
    }

    DateTime date;

    try {
      date = DateTime.parse(match.date).toLocal();
    } catch (_) {
      continue;
    }

    if (!date.isAfter(now)) {
      continue;
    }

    unique[match.fixtureId] = match;
  }

  final matches = unique.values.toList()
    ..sort((a, b) {
      try {
        return DateTime.parse(a.date).compareTo(DateTime.parse(b.date));
      } catch (_) {
        return 0;
      }
    });

  if (matches.isEmpty) {
    print('');
    print('Nessuna partita futura disponibile oggi o domani.');
    return;
  }

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];

    DateTime date;

    try {
      date = DateTime.parse(match.date).toLocal();
    } catch (_) {
      continue;
    }

    final day =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';

    final time =
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    print('');
    print('#${i + 1}');
    print('Fixture: ${match.fixtureId}');
    print('$day $time');
    print('${match.homeTeam} - ${match.awayTeam}');
    print('${match.league} (${match.country})');
    print('AI weight: ${match.aiWeight.toStringAsFixed(2)}');
  }

  print('');
  print('============================================================');
  print('Totale: ${matches.length}');
  print('============================================================');
}
