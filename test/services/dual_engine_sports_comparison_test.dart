import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/diego_ai_market_probability_service.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/smartbet_ai_service.dart';
import 'package:smartbet_ai_new/services/dual_engine_analysis_service.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

AnalysisResult smart({
  String audit = 'CONFIRM',
  List<String> blocked = const <String>[],
}) {
  return AnalysisResult(
    smartScore: 82,
    predictionConfidence: 82,
    dataConfidence: 80,
    sportsAuditStatus: audit,
    sportsAuditBlockedMarkets: blocked,
    homeProbability: 65,
    drawProbability: 20,
    awayProbability: 15,
    goalProbability: 80,
    noGoalProbability: 20,
    over25Probability: 72,
    prediction: '1',
    valueBet: '',
    risk: 'BASSO',
    explanation: 'Test statistico',
  );
}

DiegoAiMarketProbability probability(String name, double value) {
  return DiegoAiMarketProbability(market: name, probability: value);
}

FixtureMarketOdds quotes(Map<String, double> values) {
  return FixtureMarketOdds(
    fixtureId: 1001,
    matchWinner: null,
    bookmakerCount: 1,
    bestByOutcome: {
      for (final entry in values.entries)
        entry.key: BestOdd(
          outcome: entry.key,
          odd: entry.value,
          bookmakerId: 1,
          bookmakerName: 'Bookmaker Test',
        ),
    },
  );
}

/// Finto risultato Diego: nessuna simulazione e nessuna API.
class FakeDiego extends Fake implements DiegoAiAnalysis {
  @override
  final List<DiegoAiMarketProbability> markets;

  @override
  final FixtureMarketOdds? marketOdds;

  FakeDiego({required this.markets, required this.marketOdds});
}

// Nessuna inizializzazione dei servizi reali.
// Il confronto utilizza soltanto risultati preparati.
class FakeSmartBetService extends Fake implements SmartBetAiService {}

class FakeDiegoService extends Fake implements DiegoAiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DualEngineAnalysisService service;

  setUp(() {
    service = DualEngineAnalysisService(
      smartBetService: FakeSmartBetService(),
      diegoService: FakeDiegoService(),
    );
  });

  final baseMarkets = [
    probability('GOAL', 0.80),
    probability('OVER 2.5', 0.72),
  ];

  final baseQuotes = {'GOAL': 1.40, 'OVER 2.5': 1.60};

  FakeDiego diego({
    List<DiegoAiMarketProbability>? markets,
    FixtureMarketOdds? odds,
  }) {
    return FakeDiego(markets: markets ?? baseMarkets, marketOdds: odds);
  }

  test('Accordo: entrambi scelgono Goal', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes(baseQuotes)),
    );

    expect(result.comparison.status, DualEngineAgreement.agree);
    expect(result.comparison.smartBetMarket, 'GOAL');
    expect(result.comparison.diegoMarket, 'GOAL');
  });

  test('Divergenza: Goal contro No Goal', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(
        markets: [probability('NO GOAL', 0.85), probability('GOAL', 0.15)],
        odds: quotes({'GOAL': 1.40, 'NO GOAL': 1.60}),
      ),
    );

    expect(result.comparison.status, DualEngineAgreement.diverge);
    expect(result.comparison.smartBetMarket, 'GOAL');
    expect(result.comparison.diegoMarket, 'NO GOAL');
  });

  test('Auditor blocca Goal: SmartBet sceglie Over 2.5', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'DOUBT', blocked: ['BTTS YES']),
      diego: diego(odds: quotes(baseQuotes)),
    );

    expect(result.comparison.smartBetMarket, 'OVER 2.5');
    expect(result.comparison.diegoMarket, 'GOAL');
    expect(result.comparison.status, DualEngineAgreement.partial);
  });

  test('Quota GOAL sotto 1.20: entrambi mantengono GOAL come pronostico AI', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes({'GOAL': 1.19, 'OVER 2.5': 1.60})),
    );

    expect(result.comparison.smartBetMarket, 'GOAL');
    expect(result.comparison.diegoMarket, 'GOAL');
    expect(result.comparison.diegoOdd, isNull);
    expect(result.comparison.status, DualEngineAgreement.agree);
  });

  test('P19B2A: NOT_RUN mostra solo lettura statistica', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'NOT_RUN'),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: 'GOAL',
      smartBetProbability: 80,
      smartBetOdd: 1.40,
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
    expect(result.comparison.statisticalSmartBetMarket, 'GOAL');
    expect(result.comparison.statisticalSmartBetProbability, 0.80);
  });

  test('P19B2A: quota sotto 1.20 non produce preview', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'NOT_RUN'),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: 'GOAL',
      smartBetProbability: 80,
      smartBetOdd: 1.19,
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.statisticalSmartBetMarket, isNull);
  });

  test('P19B2A: veto sportivo non produce preview', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'STRONG_CONTRADICTION'),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: 'GOAL',
      smartBetProbability: 80,
      smartBetOdd: 1.40,
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.statisticalSmartBetMarket, isNull);
  });

  test('P19B2A: verifica completa usa il confronto normale', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'CONFIRM'),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: 'GOAL',
      smartBetProbability: 80,
      smartBetOdd: 1.40,
    );

    expect(result.comparison.status, DualEngineAgreement.agree);
    expect(result.comparison.smartBetMarket, 'GOAL');
    expect(result.comparison.statisticalSmartBetMarket, isNull);
  });

  test('Auditor NOT_RUN: confronto indisponibile', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'NOT_RUN'),
      diego: diego(odds: quotes(baseQuotes)),
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
  });

  test('Contraddizione globale: confronto indisponibile', () {
    final result = service.comparePrepared(
      smartBet: smart(audit: 'STRONG_CONTRADICTION'),
      diego: diego(odds: quotes(baseQuotes)),
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
  });

  test('Override esplicito: conserva il mercato della schermata', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: '1',
      smartBetProbability: 65,
      smartBetOdd: 1.70,
    );

    expect(result.comparison.smartBetMarket, '1');
    expect(result.comparison.smartBetProbability, 0.65);
    expect(result.comparison.diegoMarket, 'GOAL');
  });

  test('Override senza quota verificabile: indisponibile', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: '1',
      smartBetProbability: 65,
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
  });

  test('Quota esplicita sotto 1.20: rifiutata', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes({'GOAL': 1.40, 'OVER 2.5': 1.60, '1': 2.00})),
      smartBetMarket: '1',
      smartBetOdd: 1.19,
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
  });

  test('Quota esattamente 1.20: consentita', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: '1',
      smartBetProbability: 65,
      smartBetOdd: 1.20,
    );

    expect(result.comparison.smartBetMarket, '1');
    expect(result.comparison.smartBetProbability, 0.65);
    expect(result.comparison.status, DualEngineAgreement.partial);
  });

  test('Quote assenti: solo lettura statistica', () {
    final result = service.comparePrepared(
      smartBet: smart(),
      diego: diego(odds: null),
    );

    expect(result.comparison.status, DualEngineAgreement.noSelection);
    expect(result.comparison.diegoMarket, 'GOAL');
    expect(result.comparison.diegoOdd, isNull);
  });

  test('Override bloccato: nessun confronto approvato', () {
    final result = service.comparePrepared(
      smartBet: smart(blocked: ['GOAL']),
      diego: diego(odds: quotes(baseQuotes)),
      smartBetMarket: 'GOAL',
    );

    expect(result.comparison.status, DualEngineAgreement.unavailable);
    expect(result.comparison.smartBetMarket, 'N/D');
  });
}
