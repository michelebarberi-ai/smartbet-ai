import 'dart:convert';

import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_outbox.dart';
import 'goalvdline_historical_learning_review.dart';

/// Trasporto manuale in HTTPS. Il token può essere conservato solo nel Portachiavi, a scelta dell’utente.
/// Il token amministratore NON deve mai essere utilizzato su un dispositivo.
/// Lo storico P23B3 non viene mai letto da questa classe.
class GoalVdLineCentralLearningMobileSync {
  GoalVdLineCentralLearningMobileSync({
    GoalVdLineCentralLearningOutbox? outbox,
    http.Client? client,
  }) : _outbox = outbox ?? GoalVdLineCentralLearningOutbox.instance,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final GoalVdLineCentralLearningOutbox _outbox;
  final http.Client _client;
  final bool _ownsClient;

  static const defaultServerUrl =
      'https://goalvdline-learning-api.onrender.com';
  static const _timeout = Duration(seconds: 12);
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// Solo la radice di un server HTTPS. Non accetta credenziali o query nell'URL.
  static Uri serverOrigin(String value) {
    final url = Uri.tryParse(value.trim());
    if (url == null ||
        url.scheme.toLowerCase() != 'https' ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException(
        'Inserisci soltanto l\'indirizzo HTTPS del server.',
      );
    }
    return url;
  }

  static Uri _endpoint(Uri origin, String path) =>
      origin.replace(path: path, query: null, fragment: null);

  Future<bool> mobileAvailable(String baseUrl) async {
    final origin = serverOrigin(baseUrl);
    try {
      final request = http.Request(
        'GET',
        _endpoint(origin, '/learning/v1/status'),
      )..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(_timeout);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map &&
          decoded['enabled'] == true &&
          decoded['mobileIngestEnabled'] == true &&
          decoded['liveCalibration'] == false;
    } catch (_) {
      return false;
    }
  }

  /// Un invio al massimo: 20 previsioni, su non più di 5 partite.
  /// Unicamente un success=true con accepted+duplicates==inviate autorizza
  /// la rimozione della singola fotografia locale (invio idempotente).
  Future<GoalVdLineUploadResult> uploadOnce({
    required String baseUrl,
    required String token,
  }) async {
    final origin = serverOrigin(baseUrl);
    if (!_tokenPattern.hasMatch(token)) {
      return const GoalVdLineUploadResult(
        'Credenziale dispositivo non valida.',
      );
    }
    final drafts = await _outbox.eligibleLocalDrafts();
    if (!_outbox.consentGranted) {
      return const GoalVdLineUploadResult(
        'Prima autorizza la raccolta delle nuove previsioni.',
      );
    }
    if (drafts.isEmpty) {
      return const GoalVdLineUploadResult(
        'Non ci sono nuove previsioni in coda.',
      );
    }
    if (!await mobileAvailable(baseUrl)) {
      return const GoalVdLineUploadResult(
        'Server non disponibile o invio mobile disattivato.',
      );
    }

    final selected = <GoalVdLineLearningDraft>[];
    final fixtures = <int>{};
    var unsupported = 0;
    for (final draft in drafts) {
      if (!isSupportedMarket(draft.market)) {
        unsupported++;
        continue;
      }
      if (selected.length >= 20) break;
      if (!fixtures.contains(draft.fixtureId) && fixtures.length >= 5) continue;
      fixtures.add(draft.fixtureId);
      selected.add(draft);
    }
    if (selected.isEmpty) {
      return GoalVdLineUploadResult(
        'Nessun mercato compatibile con il server. ${drafts.length} previsioni restano in coda.',
        unsupported: unsupported,
      );
    }

    final body = jsonEncode({
      'predictions': selected
          .map(
            (draft) => {
              'fixtureId': draft.fixtureId,
              'engine': draft.engine,
              'market': draft.market,
              'probability': draft.probability,
            },
          )
          .toList(),
    });

    try {
      // No redirect: il token non deve mai essere inoltrato a un altro host.
      final request = http.Request(
        'POST',
        _endpoint(origin, '/learning/v1/mobile/predictions'),
      )..followRedirects = false;
      request.body = body;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      });
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(_timeout);
      if (response.statusCode == 401) {
        return const GoalVdLineUploadResult('Credenziale scaduta o revocata.');
      }
      if (response.statusCode != 200) {
        return GoalVdLineUploadResult(
          'Server: invio non confermato (HTTP ${response.statusCode}). Coda conservata.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['success'] != true ||
          decoded['accepted'] is! int ||
          decoded['duplicates'] is! int) {
        return const GoalVdLineUploadResult(
          'Risposta non verificabile. Coda conservata.',
        );
      }
      final accepted = decoded['accepted'] as int;
      final duplicates = decoded['duplicates'] as int;
      if (accepted < 0 ||
          duplicates < 0 ||
          accepted + duplicates != selected.length) {
        return const GoalVdLineUploadResult(
          'Conferma incompleta. Coda conservata.',
        );
      }
      try {
        await _outbox.confirmDelivered(selected);
      } catch (_) {
        return GoalVdLineUploadResult(
          'Server: $accepted nuove e $duplicates gia presenti, ma la coda '
          'locale non si e aggiornata. Riprova: il server riconosce i duplicati.',
          accepted: accepted,
          duplicates: duplicates,
        );
      }
      return GoalVdLineUploadResult(
        'Server: $accepted nuove e $duplicates già presenti. '
        'Restano ${_outbox.pendingCount} previsioni nella coda.',
        confirmed: selected.length,
        accepted: accepted,
        duplicates: duplicates,
        unsupported: unsupported,
      );
    } catch (_) {
      return const GoalVdLineUploadResult(
        'Invio non confermato (rete o risposta). Coda conservata per ritentare.',
      );
    }
  }

  /// B45 P2: copie retrospettive (NON previsioni originali certificate).
  /// Richiede consenso locale già attivo e conferma esplicita nella UI.
  /// Non svuota mai lo storico o le fotografie originali dell'iPhone.
  /// Un invio fallito può essere ripetuto: il server deduplica per dispositivo.
  Future<GoalVdLineHistoricalUploadResult> uploadHistorical({
    required String baseUrl,
    required String token,
    required GoalVdLineHistoricalLearningReview history,
    void Function(int completed, int total)? onProgress,
  }) async {
    final origin = serverOrigin(baseUrl);
    if (!_tokenPattern.hasMatch(token)) {
      return const GoalVdLineHistoricalUploadResult('Token mobile non valido.');
    }
    await history.initialize();
    if (!history.consentGranted) {
      return const GoalVdLineHistoricalUploadResult(
        'Prepara e autorizza prima la copia storica sul telefono.',
      );
    }
    final drafts = history.preparedDrafts;
    if (drafts.isEmpty) {
      return const GoalVdLineHistoricalUploadResult(
        'Nessuna copia retrospettiva preparata.',
      );
    }
    try {
      final statusRequest = http.Request(
        'GET',
        _endpoint(origin, '/learning/v1/status'),
      )..followRedirects = false;
      statusRequest.headers['Accept'] = 'application/json';
      final statusStream = await _client.send(statusRequest).timeout(_timeout);
      final status = await http.Response.fromStream(
        statusStream,
      ).timeout(_timeout);
      if (status.statusCode != 200) {
        return const GoalVdLineHistoricalUploadResult(
          'Server storico non raggiungibile. Copie locali intatte.',
        );
      }
      final statusBody = jsonDecode(status.body);
      if (statusBody is! Map ||
          statusBody['retrospectiveIngestEnabled'] != true ||
          statusBody['liveCalibration'] != false) {
        return const GoalVdLineHistoricalUploadResult(
          'Ricezione dello storico non ancora abilitata sul server.',
        );
      }
    } catch (_) {
      return const GoalVdLineHistoricalUploadResult(
        'Verifica server non riuscita. Copie locali intatte.',
      );
    }

    var confirmed = 0;
    var accepted = 0;
    var duplicates = 0;
    const batchSize = 100;
    while (confirmed < drafts.length) {
      final end = confirmed + batchSize < drafts.length
          ? confirmed + batchSize
          : drafts.length;
      final batch = drafts.sublist(confirmed, end);
      try {
        final request = http.Request(
          'POST',
          _endpoint(origin, '/learning/v1/mobile/retrospective'),
        )..followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        });
        request.body = jsonEncode({
          'snapshots': batch.map((row) => row.toJson()).toList(),
        });
        final stream = await _client.send(request).timeout(_timeout);
        final response = await http.Response.fromStream(
          stream,
        ).timeout(_timeout);
        if (response.statusCode != 200) {
          return GoalVdLineHistoricalUploadResult(
            'Storico: $confirmed/${drafts.length} confermate. '
            'HTTP ${response.statusCode}. Puoi riprovare; nessun dato locale eliminato.',
            confirmed: confirmed,
            accepted: accepted,
            duplicates: duplicates,
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map ||
            decoded['success'] != true ||
            decoded['kind'] != 'retrospective_unverified_v1' ||
            decoded['appliesToLivePredictions'] != false ||
            decoded['accepted'] is! int ||
            decoded['duplicates'] is! int ||
            decoded['accepted'] < 0 ||
            decoded['duplicates'] < 0 ||
            decoded['accepted'] + decoded['duplicates'] != batch.length) {
          return GoalVdLineHistoricalUploadResult(
            'Conferma server incompleta: $confirmed/${drafts.length}. '
            'Copie locali intatte, riprova.',
            confirmed: confirmed,
            accepted: accepted,
            duplicates: duplicates,
          );
        }
        accepted += decoded['accepted'] as int;
        duplicates += decoded['duplicates'] as int;
        confirmed = end;
        onProgress?.call(confirmed, drafts.length);
      } catch (_) {
        return GoalVdLineHistoricalUploadResult(
          'Rete interrotta: $confirmed/${drafts.length} confermate. '
          'Copie locali intatte, riprova.',
          confirmed: confirmed,
          accepted: accepted,
          duplicates: duplicates,
        );
      }
    }
    return GoalVdLineHistoricalUploadResult(
      'Storico sul server: $confirmed/${drafts.length}. '
      '$accepted nuove, $duplicates già presenti. '
      'Le copie sul telefono sono rimaste intatte.',
      confirmed: confirmed,
      accepted: accepted,
      duplicates: duplicates,
      completed: true,
    );
  }

  /// La cancellazione sul server richiede la stessa credenziale mobile.
  /// Non tocca lo storico P23B3, né lo storico analisi dell'utente.
  Future<GoalVdLineEraseResult> eraseRemote({
    required String baseUrl,
    required String token,
  }) async {
    final origin = serverOrigin(baseUrl);
    if (!_tokenPattern.hasMatch(token)) {
      return const GoalVdLineEraseResult(
        false,
        'Credenziale dispositivo non valida.',
      );
    }
    try {
      final request = http.Request(
        'POST',
        _endpoint(origin, '/learning/v1/mobile/erase'),
      )..followRedirects = false;
      request.body = '{}';
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(_timeout);
      if (response.statusCode != 200) {
        return GoalVdLineEraseResult(
          false,
          'Cancellazione remota non confermata (HTTP ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['success'] != true ||
          decoded['deleted'] is! int) {
        return const GoalVdLineEraseResult(
          false,
          'Risposta di cancellazione non valida.',
        );
      }
      return GoalVdLineEraseResult(
        true,
        'Cancellazione remota confermata: ${decoded['deleted']} record eliminati.',
      );
    } catch (_) {
      return const GoalVdLineEraseResult(
        false,
        'Cancellazione remota non confermata. Ritenta o contatta l\'amministratore.',
      );
    }
  }

  // Stesse famiglie accettate dal backend P23A. Mercati non riconosciuti
  // restano sul telefono: un lotto invalido non deve bloccare gli altri.
  static bool isSupportedMarket(String value) {
    final market = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (market.isEmpty || market.length > 64) return false;
    if ({
      '1',
      'X',
      '2',
      '1X',
      'X2',
      '12',
      'GOAL',
      'NO GOAL',
      'CASA SEGNA',
      'OSPITE SEGNA',
      'CASA 2+ GOL',
      'OSPITE 2+ GOL',
      'CASA 3+ GOL',
      'OSPITE 3+ GOL',
      'CASA ALMENO 2 GOL',
      'OSPITE ALMENO 2 GOL',
      'CASA ALMENO 3 GOL',
      'OSPITE ALMENO 3 GOL',
    }.contains(market))
      return true;

    final parts = market.split(RegExp(r'\s+\+\s+'));
    if (parts.length > 1) {
      return parts.length <= 3 &&
          parts.every((part) {
            final normalized = part
                .replaceFirstMapped(
                  RegExp(r'^O(\d+(?:\.\d+)?)$'),
                  (m) => 'OVER ${m[1]}',
                )
                .replaceFirstMapped(
                  RegExp(r'^U(\d+(?:\.\d+)?)$'),
                  (m) => 'UNDER ${m[1]}',
                );
            return isSupportedMarket(normalized);
          });
    }
    final overUnder = RegExp(
      r'^(OVER|UNDER) (\d+(?:\.\d+)?)$',
    ).firstMatch(market);
    if (overUnder != null) {
      final line = double.tryParse(overUnder[2]!);
      return line != null &&
          line >= 0.5 &&
          line <= 6.5 &&
          (line * 2) == (line * 2).roundToDouble() &&
          line != line.roundToDouble();
    }
    final multi = RegExp(r'^MULTIGOL (\d+)-(\d+)$').firstMatch(market);
    if (multi != null) {
      final lower = int.parse(multi[1]!);
      final upper = int.parse(multi[2]!);
      return lower >= 0 && upper <= 12 && lower <= upper;
    }
    final euro = RegExp(
      r'^HCP EURO CASA ([+-]?\d+) ([1X2])$',
    ).firstMatch(market);
    if (euro != null) {
      return int.parse(euro[1]!).abs() <= 5;
    }
    return false;
  }
}

class GoalVdLineUploadResult {
  final String message;
  final int confirmed;
  final int accepted;
  final int duplicates;
  final int unsupported;

  const GoalVdLineUploadResult(
    this.message, {
    this.confirmed = 0,
    this.accepted = 0,
    this.duplicates = 0,
    this.unsupported = 0,
  });
}

class GoalVdLineEraseResult {
  final bool success;
  final String message;
  const GoalVdLineEraseResult(this.success, this.message);
}

/// Risultato del caricamento retrospettivo; non è una metrica di successo AI.
class GoalVdLineHistoricalUploadResult {
  final String message;
  final int confirmed;
  final int accepted;
  final int duplicates;
  final bool completed;
  const GoalVdLineHistoricalUploadResult(
    this.message, {
    this.confirmed = 0,
    this.accepted = 0,
    this.duplicates = 0,
    this.completed = false,
  });
}
