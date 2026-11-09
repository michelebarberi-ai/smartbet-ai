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
      final events = _parseEvents(coupon['events']);
      if (events == null) {
        return const GoalVdLineTodayCouponResult(
          'Schedina ricevuta non verificabile.',
        );
      }
      final variants = <GoalVdLineTodayCouponVariant>[];
      if (coupon.containsKey('coupons')) {
        final source = coupon['coupons'];
        if (source is! List || source.length != 3) {
          return const GoalVdLineTodayCouponResult('Varianti non valide.');
        }
        const expectedNames = ['PRINCIPALE', 'ALTERNATIVA_1', 'ALTERNATIVA_2'];
        final signatures = <String>{};
        for (var i = 0; i < source.length; i++) {
          final raw = source[i];
          if (raw is! Map<String, dynamic> || raw['name'] != expectedNames[i]) {
            return const GoalVdLineTodayCouponResult('Variante non valida.');
          }
          final selection = _parseEvents(raw['events']);
          if (selection == null || selection.length != events.length) {
            return const GoalVdLineTodayCouponResult(
              'Eventi alternativi non validi.',
            );
          }
          for (var j = 0; j < events.length; j++) {
            if (selection[j].fixtureId != events[j].fixtureId ||
                !selection[j].kickoffAt.isAtSameMomentAs(events[j].kickoffAt)) {
              return const GoalVdLineTodayCouponResult(
                'Le schedine non hanno le stesse partite.',
              );
            }
            if (i == 0 &&
                (selection[j].market != events[j].market ||
                    selection[j].probability != events[j].probability ||
                    selection[j].odds != events[j].odds)) {
              return const GoalVdLineTodayCouponResult(
                'Prima schedina non coerente.',
              );
            }
          }
          signatures.add(
            selection.map((e) => '${e.fixtureId}:${e.market}').join('|'),
          );
          variants.add(
            GoalVdLineTodayCouponVariant(
              name: expectedNames[i],
              events: selection,
            ),
          );
        }
        if (signatures.length != 3) {
          return const GoalVdLineTodayCouponResult('Schedine identiche.');
        }
      }
      return GoalVdLineTodayCouponResult(
        variants.isEmpty
            ? 'Schedina del giorno ${data['dayKey']}: ${events.length} eventi.'
            : '3 schedine del giorno ${data['dayKey']}: ${events.length} partite ciascuna.',
        events: events,
        coupons: variants,
      );
    } catch (_) {
      return const GoalVdLineTodayCouponResult(
        'Impossibile leggere la schedina dal server.',
      );
    }
  }

  static List<GoalVdLineTodayCouponEvent>? _parseEvents(Object? input) {
    if (input is! List || input.length < 3 || input.length > 15) return null;
    final events = <GoalVdLineTodayCouponEvent>[];
    final ids = <int>{};
    for (final raw in input) {
      if (raw is! Map<String, dynamic>) return null;
      final id = raw['fixtureId'];
      final market = raw['market'];
      final probability = raw['marketProbability'];
      final kickoff = raw['kickoffAt'];
      final odds = raw['odds'];
      final date = kickoff is String ? DateTime.tryParse(kickoff) : null;
      if (id is! int ||
          id <= 0 ||
          !ids.add(id) ||
          market is! String ||
          market.trim().isEmpty ||
          market.length > 100 ||
          probability is! num ||
          !probability.isFinite ||
          probability < 0 ||
          probability > 100 ||
          date == null ||
          (odds != null && (odds is! num || !odds.isFinite || odds <= 1))) {
        return null;
      }
      events.add(
        GoalVdLineTodayCouponEvent(
          fixtureId: id,
          market: market.trim(),
          probability: probability.toDouble(),
          kickoffAt: date,
          odds: odds is num ? odds.toDouble() : null,
        ),
      );
    }
    return events;
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

class GoalVdLineTodayCouponVariant {
  const GoalVdLineTodayCouponVariant({
    required this.name,
    required this.events,
  });
  final String name;
  final List<GoalVdLineTodayCouponEvent> events;
}

class GoalVdLineTodayCouponResult {
  const GoalVdLineTodayCouponResult(
    this.message, {
    this.events = const [],
    this.coupons = const [],
  });
  final String message;
  final List<GoalVdLineTodayCouponEvent> events;
  final List<GoalVdLineTodayCouponVariant> coupons;
  bool get isReady => events.isNotEmpty;
}
