import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_odds_scan_guard.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

const guard = GoalVdLineOddsScanGuard;

void main() {
  test('B69: a real empty feed is not a systemic failure', () {
    final missing = [
      const OddsLookupDiagnostic(status: OddsLookupStatus.noFeedRows),
      const OddsLookupDiagnostic(status: OddsLookupStatus.noBookmakers),
    ];
    expect(guard.fullOutageBatch(missing), isFalse);
    expect(guard.stopAfterBatch(diagnostics: missing,
        consecutiveFailedBatches: 999), isFalse);
  });

  test('B69: an occasional failed fixture cannot abort search', () {
    final mixed = [
      const OddsLookupDiagnostic(
          status: OddsLookupStatus.upstreamUnavailable, httpStatus: 502),
      const OddsLookupDiagnostic(status: OddsLookupStatus.available),
    ];
    expect(guard.fullOutageBatch(mixed), isFalse);
    expect(guard.stopAfterBatch(diagnostics: mixed,
        consecutiveFailedBatches: 2), isFalse);
    expect(guard.stopAfterBatch(diagnostics: [mixed.first],
        consecutiveFailedBatches: 2), isFalse);
  });

  test('B69: first ordinary 502 batch is not enough; second can stop', () {
    final unavailable = [
      const OddsLookupDiagnostic(
          status: OddsLookupStatus.upstreamUnavailable, httpStatus: 502),
      const OddsLookupDiagnostic(
          status: OddsLookupStatus.upstreamUnavailable, httpStatus: 503),
    ];
    expect(guard.stopAfterBatch(diagnostics: unavailable,
        consecutiveFailedBatches: 1), isFalse);
    expect(guard.stopAfterBatch(diagnostics: unavailable,
        consecutiveFailedBatches: 2), isTrue);
  });

  test('B69: global quota or known misconfiguration can stop first failed batch', () {
    for (final status in [
      OddsLookupStatus.quotaOrRateLimit,
      OddsLookupStatus.proxyConfigurationError,
      OddsLookupStatus.proxyAccessDenied,
      OddsLookupStatus.proxyRouteUnavailable,
    ]) {
      final diagnoses = [
        OddsLookupDiagnostic(status: status),
        OddsLookupDiagnostic(status: status),
      ];
      expect(guard.stopAfterBatch(diagnostics: diagnoses,
          consecutiveFailedBatches: 1), isTrue);
    }
  });

  test('B69: repeated network errors can stop without misclassifying empty odds', () {
    final network = [
      const OddsLookupDiagnostic(status: OddsLookupStatus.networkError),
      const OddsLookupDiagnostic(status: OddsLookupStatus.networkError),
    ];
    expect(guard.stopAfterBatch(diagnostics: network,
        consecutiveFailedBatches: 1), isFalse);
    expect(guard.stopAfterBatch(diagnostics: network,
        consecutiveFailedBatches: 2), isTrue);
  });

  test('B69: bad fixture 404 from provider remains a genuine unknown', () {
    final bad = [
      const OddsLookupDiagnostic(
          status: OddsLookupStatus.upstreamUnavailable, httpStatus: 404),
      const OddsLookupDiagnostic(
          status: OddsLookupStatus.upstreamUnavailable, httpStatus: 404),
    ];
    expect(guard.fullOutageBatch(bad), isFalse);
  });
}
