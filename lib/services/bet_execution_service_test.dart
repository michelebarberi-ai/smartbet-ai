import '../models/analysis_result.dart';

import 'bankroll_manager.dart';
import 'bet_execution_service.dart';

Future<void> main() async {
  print('');
  print('========================================');
  print('SMARTBET - BET EXECUTION TEST');
  print('========================================');

  final bankroll =
      BankrollManager(
    initialBankroll: 1000.0,
  );

  final execution =
      BetExecutionService(
    bankrollManager:
        bankroll,
  );

  // ============================================================
  // SIMULIAMO UNA VALUE BET SMARTBET
  // ============================================================

  const analysis =
      AnalysisResult(
    smartScore: 70,

    homeProbability: 68,
    drawProbability: 20,
    awayProbability: 12,

    prediction: '1',

    valueBet:
        'WEAK VALUE 1 @ 1.62',

    risk:
        'Medio',

    shouldBet:
        true,

    recommendedStakePercent:
        0.50,

    recommendedStakeUnits:
        0.50,

    stakeOutcome:
        '1',

    stakeOdd:
        1.62,

    stakeBookmaker:
        'Betano',

    stakeRecommendation:
        'Stake consigliato 0.50% bankroll.',

    explanation:
        'Test SmartBet.',
  );

  // ============================================================
  // PREVIEW
  // ============================================================

  final preview =
      execution.preview(
    analysis:
        analysis,
  );

  print('');
  print('========================================');
  print('PREVIEW BET');
  print('========================================');

  print(
    'Giocabile: '
    '${preview.canPlaceBet}',
  );

  print(
    'Esito: '
    '${preview.outcome}',
  );

  print(
    'Quota: '
    '${preview.odd.toStringAsFixed(2)}',
  );

  print(
    'Bookmaker: '
    '${preview.bookmaker}',
  );

  print(
    'Stake %: '
    '${preview.stakePercent.toStringAsFixed(2)}%',
  );

  print(
    'Stake €: '
    '€${preview.stakeAmount.toStringAsFixed(2)}',
  );

  print(
    'Current bankroll: '
    '€${preview.currentBankroll.toStringAsFixed(2)}',
  );

  print(
    'Locked bankroll: '
    '€${preview.lockedBankroll.toStringAsFixed(2)}',
  );

  print(
    'Available bankroll: '
    '€${preview.availableBankroll.toStringAsFixed(2)}',
  );

  // ============================================================
  // CONFERMA
  // ============================================================

  final bet =
      execution.confirmBet(
    analysis:
        analysis,

    matchLabel:
        'Cagliari - Arezzo',
  );

  if (bet == null) {
    print('');
    print(
      'ERRORE: bet non registrata.',
    );

    return;
  }

  // ============================================================
  // STATO DOPO REGISTRAZIONE
  // ============================================================

  print('');
  print('========================================');
  print('DOPO REGISTRAZIONE');
  print('========================================');

  print(
    'Current bankroll: '
    '€${bankroll.currentBankroll.toStringAsFixed(2)}',
  );

  print(
    'Locked bankroll: '
    '€${bankroll.lockedBankroll.toStringAsFixed(2)}',
  );

  print(
    'Available bankroll: '
    '€${bankroll.availableBankroll.toStringAsFixed(2)}',
  );

  print(
    'Pending: '
    '${bankroll.snapshot.pending}',
  );

  print('');
  print('========================================');
  print('BET EXECUTION TEST COMPLETATO');
  print('========================================');
}

