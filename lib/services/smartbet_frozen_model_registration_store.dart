import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';
import 'smartbet_frozen_model_snapshot_store.dart';

class SmartBetFrozenModelRegistration {
  final SmartBetFrozenModelSnapshot model;
  final DateTime registeredAt;

  const SmartBetFrozenModelRegistration({
    required this.model,
    required this.registeredAt,
  });

  String get modelId => model.id;

  Map<String, dynamic> toJson() => {
    'model': model.toJson(),
    'registeredAt': registeredAt.toUtc().toIso8601String(),
  };

  factory SmartBetFrozenModelRegistration.fromJson(Map<String, dynamic> json) {
    final rawModel = json['model'];

    if (rawModel is! Map || json['registeredAt'] is! String) {
      throw const FormatException('Registrazione modello incompleta');
    }

    final model = SmartBetFrozenModelSnapshot.fromJson(
      Map<String, dynamic>.from(rawModel),
    );

    final registeredAt = DateTime.parse(json['registeredAt'] as String).toUtc();

    if (!model.frozenAt.toUtc().isBefore(registeredAt)) {
      throw const FormatException(
        'Registrazione incompatibile con il congelamento',
      );
    }

    return SmartBetFrozenModelRegistration(
      model: model,
      registeredAt: registeredAt,
    );
  }
}

/// Registro separato di prima registrazione.
///
/// Una registrazione preesistente non viene modificata.
/// L'orario è quello del dispositivo: non costituisce
/// ancora un'attestazione temporale indipendente.
class SmartBetFrozenModelRegistrationStore {
  static const storageKey = 'smartbet_frozen_registrations_v1';

  final DateTime Function() _clock;

  SmartBetFrozenModelRegistrationStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  SharedPreferences? _prefs;
  bool _initialized = false;

  final Map<String, SmartBetFrozenModelRegistration> _registrations = {};

  List<SmartBetFrozenModelRegistration> get registrations =>
      List.unmodifiable(_registrations.values);

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    final loaded = <String, SmartBetFrozenModelRegistration>{};

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        throw const FormatException('Archivio registrazioni non valido');
      }

      for (final item in decoded) {
        if (item is! Map) {
          throw const FormatException('Registrazione non valida');
        }

        final registration = SmartBetFrozenModelRegistration.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (loaded.containsKey(registration.modelId)) {
          throw StateError('Registrazione duplicata');
        }

        loaded[registration.modelId] = registration;
      }
    }

    _registrations.addAll(loaded);
    _initialized = true;
  }

  Future<SmartBetFrozenModelRegistration> register(
    SmartBetFrozenModelSnapshot model,
  ) async {
    await initialize();

    final existing = _registrations[model.id];

    if (existing != null) {
      if (jsonEncode(existing.model.toJson()) != jsonEncode(model.toJson())) {
        throw StateError('Modello già registrato: modifica vietata');
      }

      // Una ripetizione non aggiorna la data originale.
      return existing;
    }

    final now = _clock().toUtc();

    if (!model.frozenAt.toUtc().isBefore(now)) {
      throw StateError('Il congelamento deve precedere la registrazione');
    }

    final registration = SmartBetFrozenModelRegistration(
      model: model,
      registeredAt: now,
    );

    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final next = [..._registrations.values, registration];

    final saved = await prefs.setString(
      storageKey,
      jsonEncode(next.map((entry) => entry.toJson()).toList()),
    );

    if (!saved) {
      throw StateError('Salvataggio registrazione fallito');
    }

    _registrations[model.id] = registration;
    return registration;
  }

  /// Una previsione è ammissibile alla futura verifica
  /// prospettica solo se successiva alla registrazione
  /// e riferita allo stesso motore e mercato.
  bool registeredBeforePrediction({
    required String modelId,
    required SmartBetAnalysisEngine engine,
    required String market,
    required DateTime predictedAt,
  }) {
    final entry = _registrations[modelId];

    if (entry == null) return false;

    final predictionTime = predictedAt.toUtc();

    return entry.model.engine == engine &&
        entry.model.market == normalizeAnalysisMarket(market) &&
        entry.model.frozenAt.toUtc().isBefore(predictionTime) &&
        entry.registeredAt.toUtc().isBefore(predictionTime);
  }
}
