import '../models/analysis_result.dart';
import 'bankroll_manager.dart';

// ============================================================
// BET EXECUTION PREVIEW
// ============================================================

class BetExecutionPreview {
  final bool canPlaceBet;

  final String outcome;

  final double odd;

  final String bookmaker;

  final double stakePercent;

  final double stakeAmount;

  final double currentBankroll;

  final double lockedBankroll;

  final double availableBankroll;

  final String message;

  const BetExecutionPreview({
    required this.canPlaceBet,
    required this.outcome,
    required this.odd,
    required this.bookmaker,
    required this.stakePercent,
    required this.stakeAmount,
    required this.currentBankroll,
    required this.lockedBankroll,
    required this.availableBankroll,
    required this.message,
  });

  factory BetExecutionPreview.noBet({
    required BankrollManager bankroll,
    required String message,
  }) {
    return BetExecutionPreview(
      canPlaceBet: false,
      outcome: '',
      odd: 0.0,
      bookmaker: '',
      stakePercent: 0.0,
      stakeAmount: 0.0,
      currentBankroll: bankroll.currentBankroll,
      lockedBankroll: bankroll.lockedBankroll,
      availableBankroll: bankroll.availableBankroll,
      message: message,
    );
  }
}

// ============================================================
// BET EXECUTION SERVICE
// ============================================================

class BetExecutionService {
  final BankrollManager bankrollManager;

  const BetExecutionService({
    required this.bankrollManager,
  });

  // ============================================================
  // PREVIEW
  // ============================================================
  //
  // Non modifica il bankroll.
  //
  // Controlla solamente se la raccomandazione SmartBet
  // può essere realmente eseguita.
  // ============================================================

  BetExecutionPreview preview({
    required AnalysisResult analysis,
  }) {
    // ----------------------------------------------------------
    // SMARTBET NON CONSIGLIA UNA BET
    // ----------------------------------------------------------

    if (!analysis.shouldBet) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'SmartBet non consiglia alcuna puntata.',
      );
    }

    // ----------------------------------------------------------
    // STAKE NON VALIDO
    // ----------------------------------------------------------

    if (analysis.recommendedStakePercent <= 0.0) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'Stake percentuale non valido.',
      );
    }

    // ----------------------------------------------------------
    // QUOTA NON VALIDA
    // ----------------------------------------------------------

    if (analysis.stakeOdd <= 1.0) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'Quota non valida.',
      );
    }

    // ----------------------------------------------------------
    // BANKROLL
    // ----------------------------------------------------------

    if (bankrollManager.currentBankroll <= 0.0) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'Bankroll non disponibile.',
      );
    }

    if (bankrollManager.availableBankroll <= 0.0) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'Capitale disponibile esaurito.',
      );
    }

    // ----------------------------------------------------------
    // IMPORTO CONSIGLIATO
    // ----------------------------------------------------------
    //
    // Lo Stake Engine ragiona sul bankroll corrente.
    // Manteniamo quindi la stessa base matematica.
    // ----------------------------------------------------------

    final stakeAmount =
        bankrollManager.currentBankroll *
        (analysis.recommendedStakePercent / 100.0);

    // ----------------------------------------------------------
    // CONTROLLO ESPOSIZIONE
    // ----------------------------------------------------------

    if (stakeAmount > bankrollManager.availableBankroll) {
      return BetExecutionPreview.noBet(
        bankroll: bankrollManager,
        message:
            'Capitale disponibile insufficiente per '
            'lo stake consigliato.',
      );
    }

    final message =
        'Puntata disponibile: '
        '${analysis.stakeOutcome} '
        '@ ${analysis.stakeOdd.toStringAsFixed(2)} '
        '(${analysis.stakeBookmaker}) | '
        'Stake '
        '${analysis.recommendedStakePercent.toStringAsFixed(2)}% | '
        '€${stakeAmount.toStringAsFixed(2)}';

    return BetExecutionPreview(
      canPlaceBet: true,
      outcome: analysis.stakeOutcome,
      odd: analysis.stakeOdd,
      bookmaker: analysis.stakeBookmaker,
      stakePercent:
          analysis.recommendedStakePercent,
      stakeAmount:
          stakeAmount,
      currentBankroll:
          bankrollManager.currentBankroll,
      lockedBankroll:
          bankrollManager.lockedBankroll,
      availableBankroll:
          bankrollManager.availableBankroll,
      message:
          message,
    );
  }

  // ============================================================
  // CONFERMA BET
  // ============================================================
  //
  // Questa è l'operazione che registra davvero
  // la scommessa come PENDING.
  // ============================================================

  BankrollBet? confirmBet({
    required AnalysisResult analysis,
    required String matchLabel,
  }) {
    final previewResult =
        preview(
      analysis: analysis,
    );

    if (!previewResult.canPlaceBet) {
      print('');
      print('SMARTBET BET EXECUTION');
      print(
        'BET NON REGISTRATA: '
        '${previewResult.message}',
      );

      return null;
    }

    final bet =
        bankrollManager.placeBet(
      matchLabel:
          matchLabel,
      outcome:
          previewResult.outcome,
      odd:
          previewResult.odd,
      bookmaker:
          previewResult.bookmaker,
      stakePercent:
          previewResult.stakePercent,
    );

    if (bet == null) {
      print('');
      print(
        'SMARTBET BET EXECUTION: '
        'registrazione fallita.',
      );

      return null;
    }

    print('');
    print('========================================');
    print('SMARTBET - BET REGISTRATA');
    print('========================================');

    print(
      'Partita: ${bet.matchLabel}',
    );

    print(
      'Esito: ${bet.outcome}',
    );

    print(
      'Quota: ${bet.odd.toStringAsFixed(2)}',
    );

    print(
      'Bookmaker: ${bet.bookmaker}',
    );

    print(
      'Stake: '
      '${bet.stakePercent.toStringAsFixed(2)}%',
    );

    print(
      'Importo: '
      '€${bet.stakeAmount.toStringAsFixed(2)}',
    );

    print(
      'Locked bankroll: '
      '€${bankrollManager.lockedBankroll.toStringAsFixed(2)}',
    );

    print(
      'Available bankroll: '
      '€${bankrollManager.availableBankroll.toStringAsFixed(2)}',
    );

    print('========================================');

    return bet;
  }
}

