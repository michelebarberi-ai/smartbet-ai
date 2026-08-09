import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'team_profile_service.dart';

class TeamProfileDebugTest {
  const TeamProfileDebugTest._();

  static Future<void> run() async {
    print('');
    print('========================================');
    print('SMARTBET - TEAM PROFILE REAL TEST');
    print('========================================');

    final client = http.Client();
    final profileService = TeamProfileService(client: client);

    try {
      await _testTeam(
        client: client,
        profileService: profileService,
        teamId: 876,
        teamName: 'Arezzo',
      );

      await _testTeam(
        client: client,
        profileService: profileService,
        teamId: 26356,
        teamName: 'Union Brescia',
      );
    } finally {
      profileService.dispose();
    }

    print('');
    print('========================================');
    print('TEST COMPLETATO');
    print('========================================');
  }

  // ============================================================
  // TEST SQUADRA
  // ============================================================

  static Future<void> _testTeam({
    required http.Client client,
    required TeamProfileService profileService,
    required int teamId,
    required String teamName,
  }) async {
    print('');
    print('========================================');
    print('SQUADRA: $teamName');
    print('TEAM ID: $teamId');
    print('========================================');

    // ----------------------------------------------------------
    // CERCA COMPETIZIONE
    // ----------------------------------------------------------

    final league = await _findLeague(
      client: client,
      teamId: teamId,
      teamName: teamName,
    );

    if (league == null) {
      print('');
      print('NESSUNA COMPETIZIONE TROVATA');
      print('Impossibile eseguire le statistiche.');
      return;
    }

    final leagueId = league['id'] ?? 0;
    final leagueName = league['name']?.toString() ?? '';

    final country = league['country']?.toString() ?? '';

    print('');
    print('COMPETIZIONE TROVATA');
    print('League ID: $leagueId');
    print('League: $leagueName');
    print('Paese: $country');

    // ----------------------------------------------------------
    // RECUPERA PROFILO
    // ----------------------------------------------------------

    print('');
    print('RECUPERO TEAM PROFILE...');
    print('');

    final profile = await profileService.getTeamProfile(
      teamId: teamId,
      leagueId: leagueId is int
          ? leagueId
          : int.tryParse(leagueId.toString()) ?? 0,
      season: 2026,
      country: country,
      league: leagueName,
    );

    if (profile == null) {
      print('');
      print('❌ TEAM PROFILE NON DISPONIBILE');
      return;
    }

    // ----------------------------------------------------------
    // RISULTATO
    // ----------------------------------------------------------

    print('');
    print('========================================');
    print('TEAM PROFILE TROVATO');
    print('========================================');

    print('Nome: ${profile.teamName}');
    print('Team ID: ${profile.teamId}');
    print('Paese: ${profile.country}');
    print('Campionato: ${profile.league}');

    print('');
    print('----------- FORZA SQUADRA -----------');

    print('Forza generale: ${profile.strength}');

    print('Forza rosa: ${profile.squadStrength}');

    print('Attacco: ${profile.attackStrength}');

    print('Difesa: ${profile.defenseStrength}');

    print('');
    print('----------- PRESTAZIONI -----------');

    print('Forma: ${profile.form}');

    print('Forza casa: ${profile.homeStrength}');

    print('Forza trasferta: ${profile.awayStrength}');

    print('');
    print('----------- STORICO -----------');

    print(
      'Forza storica: '
      '${profile.historicalStrength}',
    );

    print(
      'Forza campionato: '
      '${profile.leagueStrength}',
    );

    print('');
    print('----------- DISPONIBILITÀ -----------');

    print(
      'Infortunati: '
      '${profile.injuredPlayers}',
    );

    print(
      'Squalificati: '
      '${profile.suspendedPlayers}',
    );

    print(
      'Assenti totali: '
      '${profile.unavailablePlayers}',
    );

    print('');
    print('----------- AFFIDABILITÀ -----------');

    print(
      'Data confidence: '
      '${profile.dataConfidence}',
    );

    print(
      'Dati recenti: '
      '${profile.hasRecentData}',
    );

    print(
      'Dati sufficienti: '
      '${profile.hasEnoughData}',
    );

    print('');
    print('========================================');
  }

  // ============================================================
  // CERCA LEAGUE
  // ============================================================

  static Future<Map<String, dynamic>?> _findLeague({
    required http.Client client,
    required int teamId,
    required String teamName,
  }) async {
    print('');
    print('RICERCA COMPETIZIONI');
    print('Squadra: $teamName');
    print('Team ID: $teamId');
    print('Stagione: 2026');

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/leagues',
    ).replace(queryParameters: {'team': teamId.toString(), 'season': '2026'});

    print('URL: $uri');

    try {
      final response = await client.get(
        uri,
        headers: {
          'x-apisports-key': ApiConfig.apiKey,
          'Accept': 'application/json',
        },
      );

      print(
        'LEAGUES STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        print('ERRORE LEAGUES:');
        print(response.body);
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        print('RISPOSTA LEAGUES NON VALIDA');
        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('LEAGUES API ERROR:');
        print(errors);
        return null;
      }

      final results = decoded['response'];

      if (results is! List || results.isEmpty) {
        print('NESSUNA COMPETIZIONE');
        return null;
      }

      print(
        'COMPETIZIONI TROVATE: '
        '${results.length}',
      );

      // --------------------------------------------------------
      // STAMPA TUTTE LE COMPETIZIONI
      // --------------------------------------------------------

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final league = item['league'];

        if (league is! Map<String, dynamic>) {
          continue;
        }

        final id = league['id'];
        final name = league['name'];
        final type = league['type'];

        final leagueCountry = league['country']?.toString() ?? '';

        print(
          'LEAGUE → '
          'ID: $id | '
          'Nome: $name | '
          'Tipo: $type | '
          'Paese: $leagueCountry',
        );
      }

      // --------------------------------------------------------
      // CERCA UNA COMPETIZIONE VALIDA
      // --------------------------------------------------------

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final league = item['league'];

        if (league is! Map<String, dynamic>) {
          continue;
        }

        final id = league['id'];

        if (id is! int || id <= 0) {
          continue;
        }

        final name = league['name']?.toString() ?? '';

        final leagueCountry = league['country']?.toString() ?? '';

        if (name.isEmpty) {
          continue;
        }

        return {'id': id, 'name': name, 'country': leagueCountry};
      }

      return null;
    } catch (e) {
      print('LEAGUES EXCEPTION: $e');
      return null;
    }
  }
}
