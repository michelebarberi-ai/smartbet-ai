import 'dart:convert';

import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_mobile_sync.dart';
import 'goalvdline_mobile_token_vault.dart';

/// B45 P9: sola LETTURA delle schedine gia' salvate su Neon.
/// Non genera pronostici, non abilita job e non invia notifiche.
class GoalVdLineAutoCouponToday {
  GoalVdLineAutoCouponToday({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<GoalVdLineTodayCouponResult> fetch({
    required String token,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!GoalVdLineMobileTokenVault.validToken(token)) {
      return const GoalVdLineTodayCouponResult(
        'Token mobile mancante o non valido.',
      );
    }
    final Uri origin;
    try {
      origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
    } on FormatException {
      return const GoalVdLineTodayCouponResult(
        'Indirizzo del server non valido.',
      );
    }
    final endpoint = origin.replace(
      path: '/learning/v1/mobile/auto-coupon/today',
    );
    try {
      final request = http.Request('GET', endpoint)..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
      });
      final stream = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(
        stream,
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 401) {
        return const GoalVdLineTodayCouponResult(
          'Token mobile scaduto o non riconosciuto.',
        );
      }
      if (response.statusCode == 503) {
        return const GoalVdLineTodayCouponResult(
          'AutoSchedina non ancora abilitata sul server.',
        );
      }
      if (response.statusCode != 200) {
        return GoalVdLineTodayCouponResult(
          'Server: errore HTTP ${response.statusCode}.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> ||
          data['success'] != true ||
          data['dayKey'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data['dayKey'] as String)) {
        return const GoalVdLineTodayCouponResult(
          'Risposta del server non valida.',
        );
      }
      final status = data['status'];
      if (status == 'not_ready' ||
          status == 'processing' ||
          status == 'retry') {
        return const GoalVdLineTodayCouponResult(
          'La schedina di oggi non e\' ancora pronta.',
        );
      }
      if (status == 'unavailable') {
        return const GoalVdLineTodayCouponResult(
          'Oggi non ci sono abbastanza eventi idonei.',
        );
      }
      if (status != 'ready') {
        return const GoalVdLineTodayCouponResult(
          'Stato della schedina non riconosciuto.',
        );
      }
      final coupon = data['coupon'];
      if (coupon is! Map<String, dynamic> || coupon['events'] is! List) {
        return const GoalVdLineTodayCouponResult(
          'Schedina ricevuta non valida.',
        );
      }
      final rawEvents = coupon['events'] as List;
      if (rawEvents.length < 3 || rawEvents.length > 6) {
        return const GoalVdLineTodayCouponResult(
          'Numero di eventi non valido.',
        );
      }
      final events = <GoalVdLineTodayCouponEvent>[];
      final fixtureIds = <int>{};
      for (final raw in rawEvents) {
        if (raw is! Map<String, dynamic>) {
          return const GoalVdLineTodayCouponResult('Evento non valido.');
        }
        final fixtureId = raw['fixtureId'];
        final market = raw['market'];
        final probability = raw['marketProbability'];
        final kickoff = raw['kickoffAt'];
        final odds = raw['odds'];
        final parsedKickoff = kickoff is String
            ? DateTime.tryParse(kickoff)
            : null;
        if (fixtureId is! int ||
            fixtureId <= 0 ||
            !fixtureIds.add(fixtureId) ||
            market is! String ||
            market.trim().isEmpty ||
            market.length > 100 ||
            probability is! num ||
            !probability.isFinite ||
            probability < 0 ||
            probability > 100 ||
            parsedKickoff == null ||
            (odds != null && (odds is! num || !odds.isFinite || odds <= 1))) {
          return const GoalVdLineTodayCouponResult(
            'Schedina ricevuta non verificabile.',
          );
        }
        events.add(
          GoalVdLineTodayCouponEvent(
            fixtureId: fixtureId,
            market: market.trim(),
            probability: probability.toDouble(),
            kickoffAt: parsedKickoff,
            odds: odds is num ? odds.toDouble() : null,
          ),
        );
      }
      return GoalVdLineTodayCouponResult(
        'Schedina del giorno ${data['dayKey']}: ${events.length} eventi.',
        events: events,
      );
    } catch (_) {
      return const GoalVdLineTodayCouponResult(
        'Impossibile leggere la schedina dal server.',
      );
    }
  }
}

class GoalVdLineTodayCouponEvent {
  const GoalVdLineTodayCouponEvent({
    required this.fixtureId,
    required this.market,
    required this.probability,
    required this.kickoffAt,
    this.odds,
  });
  final int fixtureId;
  final String market;
  final double probability;
  final DateTime kickoffAt;
  final double? odds;
}

class GoalVdLineTodayCouponResult {
  const GoalVdLineTodayCouponResult(this.message, {this.events = const []});
  final String message;
  final List<GoalVdLineTodayCouponEvent> events;
  bool get isReady => events.isNotEmpty;
}
