/// Limiti espliciti per le liste giornaliere; non forzano eventi non validi.
class SmartBetPredictionQuantityPolicy {
  const SmartBetPredictionQuantityPolicy._();

  static const int dailyTarget = 5;
  static const int dailyReserves = 3;
  static const int dailyQuoteScanLimit = 24;

  static const int scorerMin = 5;
  static const int scorerMax = 10;
  static const List<int> scorerCounts = [5, 6, 7, 8, 9, 10];

  /// Limita a otto i candidati inviati all'analisi avanzata.
  static int dailyAiPoolSize(int quotedCandidates) {
    if (quotedCandidates <= 0) return 0;
    final maximum = dailyTarget + dailyReserves;
    return quotedCandidates > maximum ? maximum : quotedCandidates;
  }

  /// Cerca più incontri soltanto quando si richiedono più marcatori.
  static int scorerMatchesToScan(int requestedScorers) {
    final count = requestedScorers.clamp(scorerMin, scorerMax);
    return (count + 1).clamp(6, 10);
  }
}
