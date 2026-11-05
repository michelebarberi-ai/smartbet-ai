/// P21U: preselezione economica e deterministica di fixture, senza quote.
/// Nessuna richiesta API: il servizio ordina soltanto stime gia disponibili.
class SmartBetAutomaticFixtureEstimate {
  final int fixtureId;
  final double? probability;
  final double? dataQuality;
  const SmartBetAutomaticFixtureEstimate({
    required this.fixtureId,
    required this.probability,
    required this.dataQuality,
  });
}

class SmartBetAutoFixtureSelectionService {
  const SmartBetAutoFixtureSelectionService();

  /// Ritorna un massimo di 30 fixture per l'analisi avanzata,
  /// ma non meno del numero richiesto se disponibili. Non elimina
  /// fixture per un'affidabilita' insufficiente: le mette in fondo.
  List<int> shortlist({
    required List<SmartBetAutomaticFixtureEstimate> candidates,
    required int requestedCount,
    int maxDeepAnalyses = 30,
  }) {
    if (requestedCount < 3 || requestedCount > 15) {
      throw ArgumentError.value(
        requestedCount,
        'requestedCount',
        'Range 3..15',
      );
    }
    if (maxDeepAnalyses < requestedCount || maxDeepAnalyses > 30) {
      throw ArgumentError.value(maxDeepAnalyses, 'maxDeepAnalyses');
    }
    final ids = <int>{};
    for (final item in candidates) {
      if (item.fixtureId <= 0 || !ids.add(item.fixtureId)) {
        throw ArgumentError('ID fixture non validi o duplicati');
      }
    }
    final sorted = candidates.toList()
      ..sort((a, b) {
        double score(SmartBetAutomaticFixtureEstimate e) {
          final p = e.probability;
          if (p == null || !p.isFinite || p <= 0 || p > 1) return -1;
          final rawQuality = e.dataQuality;
          final quality =
              rawQuality != null &&
                  rawQuality.isFinite &&
                  rawQuality >= 0 &&
                  rawQuality <= 1
              ? rawQuality
              : 0;
          return p * (0.55 + 0.45 * quality);
        }

        final scoreDiff = score(b).compareTo(score(a));
        return scoreDiff != 0 ? scoreDiff : a.fixtureId.compareTo(b.fixtureId);
      });
    final doubled = requestedCount * 2;
    final minimum = maxDeepAnalyses < 12 ? maxDeepAnalyses : 12;
    final count = doubled < minimum
        ? minimum
        : (doubled > maxDeepAnalyses ? maxDeepAnalyses : doubled);
    return List<int>.unmodifiable(
      sorted.take(count).map((item) => item.fixtureId),
    );
  }
}
