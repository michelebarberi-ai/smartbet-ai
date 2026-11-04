import '../models/analysis_result.dart';
import 'smartbet_match_simulation_service.dart';

/// P21K: graduatoria multimercato su fixture SCELTE dall'utente.
/// Quote estranee al modello sportivo; eventuali quote intervengono SOLO dopo
/// la stima delle probabilita'. Non genera fixture, non chiama API, non salva.
class SmartBetMultiMarketFixture {
  final int fixtureId;
  final AnalysisResult? analysis;
  final Map<String, double> decimalOdds;

  const SmartBetMultiMarketFixture({
    required this.fixtureId,
    required this.analysis,
    this.decimalOdds = const {},
  });
}

class SmartBetMultiMarketOption {
  final String market;
  final double probability;
  final double? decimalOdd;

  const SmartBetMultiMarketOption({
    required this.market,
    required this.probability,
    required this.decimalOdd,
  });

  double? get impliedProbability => decimalOdd == null ? null : 1 / decimalOdd!;
  double? get expectedValueMargin =>
      decimalOdd == null ? null : (probability * decimalOdd!) - 1;
}

enum SmartBetFixtureBand { priority, secondary, insufficientData }

class SmartBetRankedMultiMarketFixture {
  final int fixtureId;
  final SmartBetFixtureBand band;
  final double? dataQuality;
  final SmartBetMultiMarketOption? selection;
  final List<SmartBetMultiMarketOption> alternatives;
  final String reason;

  const SmartBetRankedMultiMarketFixture({
    required this.fixtureId,
    required this.band,
    required this.dataQuality,
    required this.selection,
    required this.alternatives,
    required this.reason,
  });
}

class SmartBetMultiMarketRankingService {
  final SmartBetMatchSimulationService simulator;
  const SmartBetMultiMarketRankingService({
    this.simulator = const SmartBetMatchSimulationService(),
  });

  static const Map<String, List<String>> allowedGroups = {
    '1X2': ['1', 'X', '2'],
    'DOPPIA CHANCE': ['1X', 'X2', '12'],
    'OVER': ['OVER 1.5', 'OVER 2.5', 'OVER 3.5'],
    'UNDER': ['UNDER 1.5', 'UNDER 2.5', 'UNDER 3.5', 'UNDER 4.5'],
    'GOAL': ['GOAL', 'NO GOAL'],
    'GOL': ['GOAL', 'NO GOAL'],
    'MULTIGOL': [
      'MULTIGOL 1-3',
      'MULTIGOL 1-4',
      'MULTIGOL 2-4',
      'MULTIGOL 2-5',
      'MULTIGOL 3-5',
    ],
    'SEGNA': ['HOME SCORES', 'AWAY SCORES'],
  };

  /// Valuta tutte le fixture richieste (max 15). `families` puo' contenere
  /// massimo tre famiglie; per analisi automatica usare `families: []`,
  /// che abilita tutti i mercati supportati da questa versione.
  ///
  /// `preferValue`: se true ordina per EV solo quando sono disponibili quote
  /// valide; in mancanza usa probabilita' pura senza inventare quote.
  List<SmartBetRankedMultiMarketFixture> rank({
    required List<SmartBetMultiMarketFixture> selectedMatches,
    required List<String> families,
    bool preferValue = false,
  }) {
    if (selectedMatches.length > 15 ||
        selectedMatches.any((x) => x.fixtureId <= 0) ||
        selectedMatches.map((x) => x.fixtureId).toSet().length !=
            selectedMatches.length) {
      throw ArgumentError('Selezionare al massimo 15 fixture con ID univoci.');
    }
    final groups = families.map((e) => e.trim().toUpperCase()).toSet();
    if (groups.length > 3 || groups.any((f) => !allowedGroups.containsKey(f))) {
      throw ArgumentError('Sono consentite al massimo 3 famiglie note.');
    }
    final markets = groups.isEmpty
        ? allowedGroups.values.expand((v) => v).toSet()
        : groups.expand((f) => allowedGroups[f]!).toSet();
    final results = <SmartBetRankedMultiMarketFixture>[];

    for (final fixture in selectedMatches) {
      final analysis = fixture.analysis;
      final h = analysis?.expectedHomeGoals;
      final a = analysis?.expectedAwayGoals;
      final quality =
          analysis == null ||
              analysis.dataConfidence <= 0 ||
              analysis.dataConfidence > 100
          ? null
          : analysis.dataConfidence / 100.0;
      if (h == null ||
          a == null ||
          !h.isFinite ||
          !a.isFinite ||
          h <= 0 ||
          a <= 0 ||
          h > 6 ||
          a > 6) {
        results.add(
          SmartBetRankedMultiMarketFixture(
            fixtureId: fixture.fixtureId,
            band: SmartBetFixtureBand.insufficientData,
            dataQuality: quality,
            selection: null,
            alternatives: const [],
            reason: 'xG prepartita non disponibili: analisi non simulabile.',
          ),
        );
        continue;
      }
      final sim = simulator.simulate(
        SmartBetMatchSimulationInput(
          expectedHomeGoals: h,
          expectedAwayGoals: a,
          dataQuality: quality ?? 0,
        ),
      );
      final options = <SmartBetMultiMarketOption>[];
      for (final market in markets) {
        final probability = sim.marketProbabilities[market];
        if (probability == null) continue;
        final rawOdd = fixture.decimalOdds[market];
        final odd = rawOdd != null && rawOdd.isFinite && rawOdd > 1
            ? rawOdd
            : null;
        options.add(
          SmartBetMultiMarketOption(
            market: market,
            probability: probability,
            decimalOdd: odd,
          ),
        );
      }
      options.sort((x, y) {
        if (preferValue &&
            x.expectedValueMargin != null &&
            y.expectedValueMargin != null) {
          final value = y.expectedValueMargin!.compareTo(
            x.expectedValueMargin!,
          );
          if (value != 0) return value;
        }
        final p = y.probability.compareTo(x.probability);
        return p != 0 ? p : x.market.compareTo(y.market);
      });
      final choice = options.isEmpty ? null : options.first;
      final band = choice == null || quality == null
          ? SmartBetFixtureBand.insufficientData
          : quality >= 0.65 && choice.probability >= 0.70
          ? SmartBetFixtureBand.priority
          : SmartBetFixtureBand.secondary;
      final reason = choice == null
          ? 'Nessun mercato compatibile con i dati disponibili.'
          : quality == null
          ? 'Probabilita calcolata, ma qualita dati non misurata.'
          : band == SmartBetFixtureBand.priority
          ? 'Soglie operative di probabilita e qualita dati superate.'
          : 'Selezione secondaria: probabilita o qualita dati limitate.';
      results.add(
        SmartBetRankedMultiMarketFixture(
          fixtureId: fixture.fixtureId,
          band: band,
          dataQuality: quality,
          selection: choice,
          alternatives: List.unmodifiable(options.skip(1).take(3)),
          reason: reason,
        ),
      );
    }
    const bandRank = {
      SmartBetFixtureBand.priority: 0,
      SmartBetFixtureBand.secondary: 1,
      SmartBetFixtureBand.insufficientData: 2,
    };
    results.sort((x, y) {
      final first = bandRank[x.band]!.compareTo(bandRank[y.band]!);
      if (first != 0) return first;
      final p = (y.selection?.probability ?? -1).compareTo(
        x.selection?.probability ?? -1,
      );
      if (p != 0) return p;
      final q = (y.dataQuality ?? -1).compareTo(x.dataQuality ?? -1);
      return q != 0 ? q : x.fixtureId.compareTo(y.fixtureId);
    });
    return List.unmodifiable(results);
  }
}
