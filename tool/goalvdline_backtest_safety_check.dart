// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  final now = DateTime.now();

  // Prendiamo una giornata abbastanza indietro da avere
  // sicuramente partite successive nella stessa stagione.
  final targetDate = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 14));

  print('');
  print('============================================================');
  print('GOALVDLINE - BACKTEST SAFETY CHECK');
  print('Data storica: ${targetDate.toIso8601String()}');
  print('============================================================');

  final matches = await MatchRepository.getMatchesByDate(targetDate);

  final candidates =
      matches
          .where(
            (match) =>
                match.fixtureId > 0 && match.hasTeamIds && !match.isFriendly,
          )
          .toList()
        ..sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

  if (candidates.isEmpty) {
    print('Nessuna partita storica utilizzabile.');
    return;
  }

  MatchModel? selected;

  // Preferiamo una partita di campionato con peso elevato.
  for (final match in candidates) {
    if (match.aiWeight >= 0.85) {
      selected = match;
      break;
    }
  }

  selected ??= candidates.first;

  final match = selected;

  print('');
  print('PARTITA SELEZIONATA');
  print('Fixture: ${match.fixtureId}');
  print('${match.homeTeam} - ${match.awayTeam}');
  print('${match.league} (${match.country})');
  print('Data: ${match.date}');
  print('AI weight: ${match.aiWeight}');

  print('');
  print('============================================================');
  print('COSTRUZIONE DOSSIER STORICO');
  print('============================================================');

  final builder = MatchDossierBuilder();

  try {
    final dossier = await builder.build(match);

    if (dossier == null) {
      print('');
      print('Dossier storico non disponibile.');
      return;
    }

    print('');
    print('============================================================');
    print('BACKTEST SNAPSHOT COSTRUITO');
    print('============================================================');

    print(
      'Partita: '
      '${dossier.homeTeam} - ${dossier.awayTeam}',
    );

    print(
      'Data confidence: '
      '${dossier.dataConfidence}/100',
    );

    print(
      'Partite forma casa: '
      '${dossier.homeForm['count'] ?? 0}',
    );

    print(
      'Partite forma ospite: '
      '${dossier.awayForm['count'] ?? 0}',
    );

    print('');
    print('CERCA NEL LOG SOPRA LE RIGHE:');

    print('"Ignorate successive alla data riferimento: X"');

    print('');
    print(
      'Se X > 0, il filtro anti-data-leakage '
      'sta funzionando.',
    );
  } finally {
    builder.dispose();
  }
}
