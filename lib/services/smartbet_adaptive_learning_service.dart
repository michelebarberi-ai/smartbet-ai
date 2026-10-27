import 'smartbet_analysis_history_store.dart';

enum SmartBetAdaptiveLearningDimension {
  overall,
  market,
  league,
  marketLeague,
  probabilityBand,
}

enum SmartBetAdaptiveLearningSignal {
  insufficient,
  exploratory,
  signal,
  strongCandidate,
}

class SmartBetAdaptiveLearningSegment {
  final SmartBetAnalysisEngine engine;

  final SmartBetAdaptiveLearningDimension dimension;

  final String? market;
  final String? league;
  final String? probabilityBand;

  final int sampleSize;
  final int correct;
  final int wrong;

  final int probabilitySampleSize;

  /// Percentuale 0..100.
  final double accuracy;

  /// Probabilità media dichiarata dal motore, 0..100.
  final double? averagePredictedProbability;

  /// accuracy - probabilità media dichiarata.
  ///
  /// Positivo:
  /// il motore è stato storicamente più preciso
  /// di quanto dichiarato.
  ///
  /// Negativo:
  /// il motore è stato storicamente troppo
  /// ottimista.
  final double? calibrationGap;

  /// Brier Score medio 0..1.
  ///
  /// Più basso = migliore calibrazione.
  final double? brierScore;

  final SmartBetAdaptiveLearningSignal signal;

  const SmartBetAdaptiveLearningSegment({
    required this.engine,
    required this.dimension,
    required this.market,
    required this.league,
    required this.probabilityBand,
    required this.sampleSize,
    required this.correct,
    required this.wrong,
    required this.probabilitySampleSize,
    required this.accuracy,
    required this.averagePredictedProbability,
    required this.calibrationGap,
    required this.brierScore,
    required this.signal,
  });

  String get key {
    return [
      engine.name,
      dimension.name,
      market ?? '-',
      league ?? '-',
      probabilityBand ?? '-',
    ].join('|');
  }

  bool get hasReliableCalibration => probabilitySampleSize >= 50;

  bool get isHistoricallyOverconfident =>
      calibrationGap != null && calibrationGap! < 0;

  bool get isHistoricallyUnderconfident =>
      calibrationGap != null && calibrationGap! > 0;
}

class SmartBetAdaptiveLearningReport {
  final DateTime generatedAt;

  final int eligibleRecords;

  final List<SmartBetAdaptiveLearningSegment> segments;

  const SmartBetAdaptiveLearningReport({
    required this.generatedAt,
    required this.eligibleRecords,
    required this.segments,
  });

  List<SmartBetAdaptiveLearningSegment> forEngine(
    SmartBetAnalysisEngine engine,
  ) {
    return List.unmodifiable(
      segments.where((segment) => segment.engine == engine),
    );
  }

  List<SmartBetAdaptiveLearningSegment> strongCandidates({
    SmartBetAnalysisEngine? engine,
  }) {
    final values = segments.where((segment) {
      if (engine != null && segment.engine != engine) {
        return false;
      }

      return segment.signal == SmartBetAdaptiveLearningSignal.strongCandidate;
    }).toList();

    values.sort((a, b) => b.sampleSize.compareTo(a.sampleSize));

    return List.unmodifiable(values);
  }

  List<SmartBetAdaptiveLearningSegment> strongest({
    required SmartBetAnalysisEngine engine,
    int minimumSample = 50,
    int limit = 10,
  }) {
    final values = segments.where((segment) {
      return segment.engine == engine &&
          segment.dimension != SmartBetAdaptiveLearningDimension.overall &&
          segment.sampleSize >= minimumSample;
    }).toList();

    values.sort((a, b) {
      final accuracyCompare = b.accuracy.compareTo(a.accuracy);

      if (accuracyCompare != 0) {
        return accuracyCompare;
      }

      return b.sampleSize.compareTo(a.sampleSize);
    });

    return List.unmodifiable(values.take(limit));
  }

  List<SmartBetAdaptiveLearningSegment> weakest({
    required SmartBetAnalysisEngine engine,
    int minimumSample = 50,
    int limit = 10,
  }) {
    final values = segments.where((segment) {
      return segment.engine == engine &&
          segment.dimension != SmartBetAdaptiveLearningDimension.overall &&
          segment.sampleSize >= minimumSample;
    }).toList();

    values.sort((a, b) {
      final accuracyCompare = a.accuracy.compareTo(b.accuracy);

      if (accuracyCompare != 0) {
        return accuracyCompare;
      }

      return b.sampleSize.compareTo(a.sampleSize);
    });

    return List.unmodifiable(values.take(limit));
  }
}

class SmartBetAdaptiveLearningService {
  const SmartBetAdaptiveLearningService();

  SmartBetAdaptiveLearningReport analyze(
    List<SmartBetAnalysisRecord> records, {
    DateTime? generatedAt,
  }) {
    final eligible = records.where(_isEligible).toList();

    final buckets = <String, _LearningBucket>{};

    for (final record in eligible) {
      _addRecord(
        buckets: buckets,
        dimension: SmartBetAdaptiveLearningDimension.overall,
        record: record,
      );

      _addRecord(
        buckets: buckets,
        dimension: SmartBetAdaptiveLearningDimension.market,
        record: record,
        market: normalizeAnalysisMarket(record.market),
      );

      final league = _normalizeLabel(record.league);

      if (league.isNotEmpty) {
        _addRecord(
          buckets: buckets,
          dimension: SmartBetAdaptiveLearningDimension.league,
          record: record,
          league: league,
        );

        _addRecord(
          buckets: buckets,
          dimension: SmartBetAdaptiveLearningDimension.marketLeague,
          record: record,
          market: normalizeAnalysisMarket(record.market),
          league: league,
        );
      }

      final probability = record.probability;

      if (probability != null) {
        _addRecord(
          buckets: buckets,
          dimension: SmartBetAdaptiveLearningDimension.probabilityBand,
          record: record,
          probabilityBand: _probabilityBand(probability),
        );
      }
    }

    final segments = buckets.values
        .map((bucket) => bucket.toSegment())
        .toList();

    segments.sort(_segmentCompare);

    return SmartBetAdaptiveLearningReport(
      generatedAt: (generatedAt ?? DateTime.now()).toUtc(),
      eligibleRecords: eligible.length,
      segments: List.unmodifiable(segments),
    );
  }

  bool _isEligible(SmartBetAnalysisRecord record) {
    if (!record.prospectiveEligible) {
      return false;
    }

    return record.status == SmartBetAnalysisStatus.correct ||
        record.status == SmartBetAnalysisStatus.wrong;
  }

  void _addRecord({
    required Map<String, _LearningBucket> buckets,
    required SmartBetAdaptiveLearningDimension dimension,
    required SmartBetAnalysisRecord record,
    String? market,
    String? league,
    String? probabilityBand,
  }) {
    final key = [
      record.engine.name,
      dimension.name,
      market ?? '-',
      league ?? '-',
      probabilityBand ?? '-',
    ].join('|');

    final bucket = buckets.putIfAbsent(
      key,
      () => _LearningBucket(
        engine: record.engine,
        dimension: dimension,
        market: market,
        league: league,
        probabilityBand: probabilityBand,
      ),
    );

    bucket.add(record);
  }

  static SmartBetAdaptiveLearningSignal signalForSample(int sampleSize) {
    if (sampleSize >= 200) {
      return SmartBetAdaptiveLearningSignal.strongCandidate;
    }

    if (sampleSize >= 100) {
      return SmartBetAdaptiveLearningSignal.signal;
    }

    if (sampleSize >= 50) {
      return SmartBetAdaptiveLearningSignal.exploratory;
    }

    return SmartBetAdaptiveLearningSignal.insufficient;
  }

  static String _probabilityBand(double rawProbability) {
    final probability = rawProbability.clamp(0.0, 1.0);

    final percent = probability * 100.0;

    if (percent >= 90.0) {
      return '90-100%';
    }

    final lower = (percent ~/ 10) * 10;

    final upper = lower + 9;

    return '$lower-$upper%';
  }

  static String _normalizeLabel(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _segmentCompare(
    SmartBetAdaptiveLearningSegment a,
    SmartBetAdaptiveLearningSegment b,
  ) {
    final engineCompare = a.engine.index.compareTo(b.engine.index);

    if (engineCompare != 0) {
      return engineCompare;
    }

    final dimensionCompare = a.dimension.index.compareTo(b.dimension.index);

    if (dimensionCompare != 0) {
      return dimensionCompare;
    }

    return a.key.compareTo(b.key);
  }
}

class _LearningBucket {
  final SmartBetAnalysisEngine engine;

  final SmartBetAdaptiveLearningDimension dimension;

  final String? market;
  final String? league;
  final String? probabilityBand;

  int sampleSize = 0;
  int correct = 0;
  int wrong = 0;

  int probabilitySampleSize = 0;
  int probabilityCorrect = 0;

  double probabilitySum = 0.0;
  double brierSum = 0.0;

  _LearningBucket({
    required this.engine,
    required this.dimension,
    required this.market,
    required this.league,
    required this.probabilityBand,
  });

  void add(SmartBetAnalysisRecord record) {
    final isCorrect = record.status == SmartBetAnalysisStatus.correct;

    sampleSize++;

    if (isCorrect) {
      correct++;
    } else {
      wrong++;
    }

    final probability = record.probability;

    if (probability == null) {
      return;
    }

    final normalized = probability.clamp(0.0, 1.0);

    probabilitySampleSize++;
    if (isCorrect) probabilityCorrect++;
    probabilitySum += normalized;

    final actual = isCorrect ? 1.0 : 0.0;

    final difference = normalized - actual;

    brierSum += difference * difference;
  }

  SmartBetAdaptiveLearningSegment toSegment() {
    final accuracy = sampleSize > 0 ? correct / sampleSize * 100.0 : 0.0;

    final averageProbability = probabilitySampleSize > 0
        ? probabilitySum / probabilitySampleSize * 100.0
        : null;

    final calibrationGap = averageProbability == null
        ? null
        : (probabilityCorrect / probabilitySampleSize * 100.0) -
              averageProbability;

    final brierScore = probabilitySampleSize > 0
        ? brierSum / probabilitySampleSize
        : null;

    return SmartBetAdaptiveLearningSegment(
      engine: engine,
      dimension: dimension,
      market: market,
      league: league,
      probabilityBand: probabilityBand,
      sampleSize: sampleSize,
      correct: correct,
      wrong: wrong,
      probabilitySampleSize: probabilitySampleSize,
      accuracy: accuracy,
      averagePredictedProbability: averageProbability,
      calibrationGap: calibrationGap,
      brierScore: brierScore,
      signal: SmartBetAdaptiveLearningService.signalForSample(sampleSize),
    );
  }
}
