import 'goalvdline_market_probability_filter.dart';

/// Applica lo stesso limite di mercato sia alla selezione iniziale sia al
/// pool finale destinato a CORE e varianti del portfolio.
class GoalVdLineCouponProbabilityPolicy {
  const GoalVdLineCouponProbabilityPolicy._();

  static bool accepts({
    required int probability,
    required int minimumPercent,
  }) => GoalVdLineMarketProbabilityFilter.accepts(
    probability: probability,
    minimumPercent: minimumPercent,
  );

  static List<T> filter<T>(
    Iterable<T> selections, {
    required int Function(T) probabilityOf,
    required int minimumPercent,
  }) => selections
      .where(
        (item) => accepts(
          probability: probabilityOf(item),
          minimumPercent: minimumPercent,
        ),
      )
      .toList(growable: false);
}
