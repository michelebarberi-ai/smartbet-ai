import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_market_settlement_service.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_settlement_service.dart';
import 'package:smartbet_ai_new/services/smartbet_multi_market_selection_service.dart';
import 'package:smartbet_ai_new/services/smartbet_refundable_market_candidate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_refundable_markets_odds_parser.dart';

AnalysisResult _analysis() => const AnalysisResult(
  smartScore: 71,
  homeProbability: 52,
  drawProbability: 24,
  awayProbability: 24,
  expectedHomeGoals: 1.7,
  expectedAwayGoals: 1.1,
  prediction: '1X',
  valueBet: '',
  risk: '',
  explanation: '',
);

BestOdd _odd(String market, double odd) => BestOdd(
  outcome: market,
  odd: odd,
  bookmakerId: 1,
  bookmakerName: 'Bookmaker di test',
);

void main() {
  test('DNB: parsifica soltanto il mercato full time esplicito', () {
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Draw No Bet',
        value: 'Home',
      ),
      'DNB CASA',
    );
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Draw No Bet',
        value: 'Away',
      ),
      'DNB OSPITE',
    );
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Draw No Bet - First Half',
        value: 'Home',
      ),
      isNull,
    );
  });

  test('Asia: solo mezzi gol quotati esplicitamente', () {
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Asian Handicap',
        value: 'Home -0.5',
      ),
      'HCP ASIA CASA -0.5',
    );
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Asian Handicap',
        value: 'Away +1.5',
      ),
      'HCP ASIA OSPITE 1.5',
    );
    for (final label in ['Home -0.75', 'Home -1', 'Home -2.75']) {
      expect(
        SmartBetRefundableMarketsOddsParser.outcomeFor(
          betName: 'Asian Handicap',
          value: label,
        ),
        isNull,
      );
    }
    expect(
      SmartBetRefundableMarketsOddsParser.outcomeFor(
        betName: 'Asian Handicap First Half',
        value: 'Home -0.5',
      ),
      isNull,
    );
  });

  test('selezione 1-3 famiglie: DNB e Asia disponibili', () {
    expect(
      SmartBetMultiMarketSelectionService.selectable,
      containsAll(['DRAW NO BET', 'HANDICAP ASIATICO']),
    );
    expect(
      () => SmartBetMultiMarketSelectionService.searchProbability(
        analysis: _analysis(),
        families: ['DRAW NO BET', 'HANDICAP ASIATICO', 'GOAL', 'OVER'],
      ),
      throwsArgumentError,
    );
  });

  test('DNB: probabilità vincita non comprende i pareggi rimborsati', () {
    expect(
      SmartBetRefundableMarketCandidateService.drawNoBetProbability(
        _analysis(),
        'DNB CASA',
      ),
      52,
    );
    expect(
      SmartBetRefundableMarketCandidateService.drawNoBetProbability(
        _analysis(),
        'DNB OSPITE',
      ),
      24,
    );
    expect(
      SmartBetAsianHandicapMarketSettlementService.evaluate(
        market: 'DNB CASA',
        homeGoals: 1,
        awayGoals: 1,
      ),
      SmartBetAsianSettlement.push,
    );
  });

  test('quote assenti: non crea candidati rimborsabili', () {
    final odds = FixtureMarketOdds(
      fixtureId: 54001,
      matchWinner: null,
      bestByOutcome: const {},
      bookmakerCount: 0,
    );
    expect(
      SmartBetMultiMarketSelectionService.bestQuoted(
        analysis: _analysis(),
        odds: odds,
        families: ['DRAW NO BET', 'HANDICAP ASIATICO'],
      ),
      isNull,
    );
  });

  test('DNB: quote vere e ranking sportivo non basato su quota alta', () {
    final odds = FixtureMarketOdds(
      fixtureId: 54002,
      matchWinner: null,
      bestByOutcome: {
        'DNB CASA': _odd('DNB CASA', 1.40),
        'DNB OSPITE': _odd('DNB OSPITE', 5.50),
      },
      bookmakerCount: 1,
    );
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: _analysis(),
      odds: odds,
      families: ['DRAW NO BET'],
    );
    expect(result?.market, 'DNB CASA');
    expect(result?.probability, 52);
  });

  test('handicap asiatico mezzo gol: corrisponde al settlement', () {
    final options = SmartBetRefundableMarketCandidateService.asianCandidates(
      analysis: _analysis(),
      quotedOutcomes: ['HCP ASIA CASA -0.5', 'HCP ASIA OSPITE 1.5'],
    );
    expect(options.length, 2);
    expect(
      options.every((e) => e.probability > 0 && e.probability < 100),
      isTrue,
    );
    expect(
      SmartBetAsianHandicapMarketSettlementService.evaluate(
        market: 'HCP ASIA CASA -0.5',
        homeGoals: 1,
        awayGoals: 0,
      ),
      SmartBetAsianSettlement.win,
    );
    expect(
      SmartBetAsianHandicapMarketSettlementService.evaluate(
        market: 'HCP ASIA CASA -0.5',
        homeGoals: 0,
        awayGoals: 0,
      ),
      SmartBetAsianSettlement.loss,
    );
  });

  test('linee asiatiche intere e quarti non vengono scelte come binarie', () {
    final options = SmartBetRefundableMarketCandidateService.asianCandidates(
      analysis: _analysis(),
      quotedOutcomes: [
        'HCP ASIA CASA -1',
        'HCP ASIA CASA -0.75',
        'HCP ASIA CASA -0.5',
      ],
    );
    expect(options.map((o) => o.market), ['HCP ASIA CASA -0.5']);
  });

  test('blocca xG assenti e non inventa una stima asiatica', () {
    final empty = AnalysisResult(
      smartScore: 30,
      homeProbability: 45,
      drawProbability: 30,
      awayProbability: 25,
      prediction: '',
      valueBet: '',
      risk: '',
      explanation: '',
    );
    expect(
      SmartBetRefundableMarketCandidateService.asianCandidates(
        analysis: empty,
        quotedOutcomes: ['HCP ASIA CASA -0.5'],
      ),
      isEmpty,
    );
  });

  test('servizio quote non confonde Full Time con First Half', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'errors': {},
          'response': [
            {
              'bookmakers': [
                {
                  'id': 77,
                  'name': 'Prova',
                  'bets': [
                    {
                      'id': 999,
                      'name': 'Draw No Bet',
                      'values': [
                        {'value': 'Home', 'odd': '1.65'},
                        {'value': 'Away', 'odd': '2.55'},
                      ],
                    },
                    {
                      'id': 998,
                      'name': 'Asian Handicap',
                      'values': [
                        {'value': 'Home -0.5', 'odd': '1.90'},
                        {'value': 'Home -0.75', 'odd': '2.10'},
                      ],
                    },
                    {
                      'id': 997,
                      'name': 'Asian Handicap First Half',
                      'values': [
                        {'value': 'Away +0.5', 'odd': '1.88'},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }),
        200,
      );
    });
    final service = OddsService(client: client);
    final odds = await service.getFixtureMarketOdds(fixtureId: 765432101);
    expect(odds?.oddFor('DNB CASA')?.odd, 1.65);
    expect(odds?.oddFor('DNB OSPITE')?.odd, 2.55);
    expect(odds?.oddFor('HCP ASIA CASA -0.5')?.odd, 1.90);
    expect(odds?.oddFor('HCP ASIA CASA -0.75'), isNull);
    expect(odds?.oddFor('HCP ASIA OSPITE 0.5'), isNull);
    service.dispose();
  });
}
