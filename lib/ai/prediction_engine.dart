class PredictionEngine {
  const PredictionEngine._();

  static ({int home, int draw, int away}) calculate({required int smartScore}) {
    if (smartScore >= 90) {
      return (home: 65, draw: 20, away: 15);
    }

    if (smartScore >= 80) {
      return (home: 55, draw: 25, away: 20);
    }

    if (smartScore >= 70) {
      return (home: 48, draw: 28, away: 24);
    }

    if (smartScore >= 60) {
      return (home: 42, draw: 30, away: 28);
    }

    return (home: 34, draw: 33, away: 33);
  }
}
