import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_market_probability_filter.dart';

void main() {
  test(
    'Build 45: SmartScore alto non sostituisce la probabilità di mercato',
    () {
      // Una selezione al 13% deve essere esclusa con filtro al 65%,
      // indipendentemente dallo SmartScore della partita.
      expect(
        GoalVdLineMarketProbabilityFilter.accepts(
          probability: 13,
          minimumPercent: 65,
        ),
        isFalse,
      );
    },
  );

  test('Build 45: soglia del mercato inclusiva al 65%', () {
    for (final probability in [1, 55, 64]) {
      expect(
        GoalVdLineMarketProbabilityFilter.accepts(
          probability: probability,
          minimumPercent: 65,
        ),
        isFalse,
      );
    }
    for (final probability in [65, 75, 100]) {
      expect(
        GoalVdLineMarketProbabilityFilter.accepts(
          probability: probability,
          minimumPercent: 65,
        ),
        isTrue,
      );
    }
  });

  test('Build 45: senza soglia conserva i mercati con stima valida', () {
    expect(
      GoalVdLineMarketProbabilityFilter.accepts(
        probability: 13,
        minimumPercent: 0,
      ),
      isTrue,
    );
    for (final probability in [0, -1, 101]) {
      expect(
        GoalVdLineMarketProbabilityFilter.accepts(
          probability: probability,
          minimumPercent: 0,
        ),
        isFalse,
      );
    }
  });

  test('Build 45: una soglia non valida viene rifiutata', () {
    expect(
      () => GoalVdLineMarketProbabilityFilter.accepts(
        probability: 70,
        minimumPercent: 101,
      ),
      throwsRangeError,
    );
  });
}
