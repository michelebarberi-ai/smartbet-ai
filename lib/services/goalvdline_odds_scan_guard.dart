import 'odds_service.dart';

/// B69: prevents repeated calls when a systemic quote feed outage is
/// already visible. NEVER infers that an unqueried fixture has no odds.
class GoalVdLineOddsScanGuard {
  const GoalVdLineOddsScanGuard._();

  static bool isSystemicFailure(OddsLookupDiagnostic diagnosis) =>
      switch (diagnosis.status) {
        OddsLookupStatus.quotaOrRateLimit ||
        OddsLookupStatus.proxyConfigurationError ||
        OddsLookupStatus.proxyAccessDenied ||
        OddsLookupStatus.proxyRouteUnavailable ||
        OddsLookupStatus.networkError ||
        OddsLookupStatus.invalidPayload => true,
        OddsLookupStatus.upstreamUnavailable =>
          (diagnosis.httpStatus ?? 0) >= 500,
        _ => false,
      };

  /// True only when *every* attempted fixture in a nontrivial batch
  /// had an actual systemic failure (not a valid empty bookmaker feed).
  static bool fullOutageBatch(List<OddsLookupDiagnostic> diagnostics) =>
      diagnostics.length >= 2 && diagnostics.every(isSystemicFailure);

  /// A confirmed quota/config/auth/route failure stops after one whole
  /// failed batch. Ordinary transport/5xx faults require two consecutive
  /// fully failing batches, reducing transient false positives.
  static bool stopAfterBatch({
    required List<OddsLookupDiagnostic> diagnostics,
    required int consecutiveFailedBatches,
  }) {
    if (!fullOutageBatch(diagnostics)) return false;
    final terminal = diagnostics.every((d) =>
        d.status == OddsLookupStatus.quotaOrRateLimit ||
        d.status == OddsLookupStatus.proxyConfigurationError ||
        d.status == OddsLookupStatus.proxyAccessDenied ||
        d.status == OddsLookupStatus.proxyRouteUnavailable);
    return terminal || consecutiveFailedBatches >= 2;
  }
}
