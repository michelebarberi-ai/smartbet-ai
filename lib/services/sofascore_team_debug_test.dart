import 'package:flutter/material.dart';

import 'sofascore_team_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('========================================');
  print('SMARTBET - SOFASCORE TEAM TEST');
  print('========================================');

  final service = SofaScoreTeamService();

  try {
    await _testTeam(service, 'Arezzo');

    await _testTeam(service, 'Union Brescia');
  } finally {
    service.dispose();
  }

  print('========================================');
  print('TEST COMPLETATO');
  print('========================================');

  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Test SofaScore completato.\n'
            'Controlla il terminale.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

Future<void> _testTeam(SofaScoreTeamService service, String name) async {
  print('');
  print('RICERCA: $name');

  final team = await service.findTeam(name);

  if (team == null) {
    print('NESSUNA SQUADRA TROVATA');
    return;
  }

  print('SQUADRA TROVATA');
  print('Nome: ${team.name}');
  print('ID SofaScore: ${team.id}');
  print('Slug: ${team.slug}');
  print('Paese: ${team.country}');

  if (team.logo != null) {
    print('Logo: ${team.logo}');
  }
}
