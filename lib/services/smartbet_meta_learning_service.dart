import 'smartbet_adaptive_learning_service.dart';
import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';

enum SmartBetMetaLearningDimension {
  overall,
  league,
  marketPair,
  leagueMarketPair,
  probabilityPair,
}

enum SmartBetMetaLearningPreference {
  smartBet,
  diego,
  balanced,
  insufficientData,
}

class SmartBetMetaLearningSegment {
  final SmartBetMetaLearningDimension dimension;

  final String? league;

  final String? smartBetMarket;
  final String? diegoMarket;

  final String? probabilityPair;

  final int sampleSize;

  final int bothCorrect;
  final int smartBetOnlyCorrect;
  final int diegoOnlyCorrect;
  final int bothWrong;

  final double smartBetAccuracy;
  final double diegoAccuracy;

  /// SmartBet accuracy - Diego accuracy.
  ///
  /// Positivo = vantaggio SmartBet.
  /// Negativo = vantaggio Diego.
  final double advantagePercentagePoints;

  final SmartBetAdaptiveLearningSignal signal;

  final SmartBetMetaLearningPreference preference;

  const SmartBetMetaLearningSegment({
    required this.dimension,
    required this.league,
    required this.smartBetMarket,
    required this.diegoMarket,
    required this.probabilityPair,
    required this.sampleSize,
    required this.bothCorrect,
    required this.smartBetOnlyCorrect,
    required this.diegoOnlyCorrect,
    required this.bothWrong,
    required this.smartBetAccuracy,
    required this.diegoAccuracy,
    required this.advantagePercentagePoints,
    required this.signal,
    required this.preference,
  });

  int get smartBetCorrect => bothCorrect + smartBetOnlyCorrect;

  int get diegoCorrect => bothCorrect + diegoOnlyCorrect;

  int get disagreements => smartBetOnlyCorrect + diegoOnlyCorrect;

  String get key {
    return [
      dimension.name,
      league ?? '-',
      smartBetMarket ?? '-',
      diegoMarket ?? '-',
      probabilityPair ?? '-',
    ].join('|');
  }
}

class SmartBetMetaLearningReport {
  final DateTime generatedAt;

  final int linkedPairs;
  final int eligiblePairs;

  final int excludedMissingRecords;
  final int excludedNonProspective;
  final int excludedPendingOrUnsupported;
  final int excludedUnqualifiedDiego;

  final List<SmartBetMetaLearningSegment> segments;

  const SmartBetMetaLearningReport({
    required this.generatedAt,
    required this.linkedPairs,
    required this.eligiblePairs,
    required this.excludedMissingRecords,
    required this.excludedNonProspective,
    required this.excludedPendingOrUnsupported,
    required this.excludedUnqualifiedDiego,
    required this.segments,
  });

  SmartBetMetaLearningSegment? get overall {
    for (final segment in segments) {
      if (segment.dimension == SmartBetMetaLearningDimension.overall) {
        return segment;
      }
    }

    return null;
  }

  List<SmartBetMetaLearningSegment> preferredSmartBet({
    int minimumSample = 50,
  }) {
    final values = segments.where((segment) {
      return segment.sampleSize >= minimumSample &&
          segment.preference == SmartBetMetaLearningPreference.smartBet;
    }).toList();

    values.sort(
      (a, b) =>
          b.advantagePercentagePoints.compareTo(a.advantagePercentagePoints),
    );

    return List.unmodifiable(values);
  }

  List<SmartBetMetaLearningSegment> preferredDiego({int minimumSample = 50}) {
    final values = segments.where((segment) {
      return segment.sampleSize >= minimumSample &&
          segment.preference == SmartBetMetaLearningPreference.diego;
    }).toList();

    values.sort(
      (a, b) =>
          a.advantagePercentagePoints.compareTo(b.advantagePercentagePoints),
    );

    return List.unmodifiable(values);
  }

  List<SmartBetMetaLearningSegment> strongSignals() {
    final values = segments.where((segment) {
      return segment.signal == SmartBetAdaptiveLearningSignal.strongCandidate;
    }).toList();

    values.sort((a, b) => b.sampleSize.compareTo(a.sampleSize));

    return List.unmodifiable(values);
  }
}

class SmartBetMetaLearningService {
  const SmartBetMetaLearningService({
    this.minimumPreferenceSample = 50,
    this.minimumAdvantagePoints = 3.0,
  });

  /// Sotto questa soglia non dichiariamo un motore preferito.
  final int minimumPreferenceSample;

  /// Differenza minima, in punti percentuali, per considerare
  /// un motore realmente davanti all'altro.
  final double minimumAdvantagePoints;

  SmartBetMetaLearningReport analyze({
    required List<SmartBetAnalysisRecord> records,
    required List<SmartBetAnalysisComparisonLink> links,
    DateTime? generatedAt,
    bool includeUnqualifiedDiego = false,
  }) {
    final recordsByKey = <String, SmartBetAnalysisRecord>{
      for (final record in records) record.key: record,
    };

    final buckets = <String, _MetaBucket>{};

    var eligiblePairs = 0;

    var excludedMissingRecords = 0;
    var excludedNonProspective = 0;
    var excludedPendingOrUnsupported = 0;
    var excludedUnqualifiedDiego = 0;

    for (final link in links) {
      final smartBet = recordsByKey[link.smartBetRecordKey];

      final diego = recordsByKey[link.diegoRecordKey];

      if (smartBet == null || diego == null) {
        excludedMissingRecords++;
        continue;
      }

      if (!smartBet.prospectiveEligible || !diego.prospectiveEligible) {
        excludedNonProspective++;
        continue;
      }

      if (!_isSettledSupported(smartBet) || !_isSettledSupported(diego)) {
        excludedPendingOrUnsupported++;
        continue;
      }

      if (!includeUnqualifiedDiego && diego.qualified == false) {
        excludedUnqualifiedDiego++;
        continue;
      }

      eligiblePairs++;

      _addPair(
        buckets: buckets,
        dimension: SmartBetMetaLearningDimension.overall,
        smartBet: smartBet,
        diego: diego,
      );

      final league = _normalizeLabel(smartBet.league);

      if (league.isNotEmpty) {
        _addPair(
          buckets: buckets,
          dimension: SmartBetMetaLearningDimension.league,
          smartBet: smartBet,
          diego: diego,
          league: league,
        );
      }

      final smartMarket = normalizeAnalysisMarket(smartBet.market);

      final diegoMarket = normalizeAnalysisMarket(diego.market);

      _addPair(
        buckets: buckets,
        dimension: SmartBetMetaLearningDimension.marketPair,
        smartBet: smartBet,
        diego: diego,
        smartBetMarket: smartMarket,
        diegoMarket: diegoMarket,
      );

      if (league.isNotEmpty) {
        _addPair(
          buckets: buckets,
          dimension: SmartBetMetaLearningDimension.leagueMarketPair,
          smartBet: smartBet,
          diego: diego,
          league: league,
          smartBetMarket: smartMarket,
          diegoMarket: diegoMarket,
        );
      }

      final smartProbability = smartBet.probability;
      final diegoProbability = diego.probability;

      if (smartProbability != null && diegoProbability != null) {
        _addPair(
          buckets: buckets,
          dimension: SmartBetMetaLearningDimension.probabilityPair,
          smartBet: smartBet,
          diego: diego,
          probabilityPair:
              '${_probabilityBand(smartProbability)} | '
              '${_probabilityBand(diegoProbability)}',
        );
      }
    }

    final segments = buckets.values
        .map(
          (bucket) => bucket.toSegment(
            minimumPreferenceSample: minimumPreferenceSample,
            minimumAdvantagePoints: minimumAdvantagePoints,
          ),
        )
        .toList();

    segments.sort(_segmentCompare);

    return SmartBetMetaLearningReport(
      generatedAt: (generatedAt ?? DateTime.now()).toUtc(),
      linkedPairs: links.length,
      eligiblePairs: eligiblePairs,
      excludedMissingRecords: excludedMissingRecords,
      excludedNonProspective: excludedNonProspective,
      excludedPendingOrUnsupported: excludedPendingOrUnsupported,
      excludedUnqualifiedDiego: excludedUnqualifiedDiego,
      segments: List.unmodifiable(segments),
    );
  }

  bool _isSettledSupported(SmartBetAnalysisRecord record) {
    return record.status == SmartBetAnalysisStatus.correct ||
        record.status == SmartBetAnalysisStatus.wrong;
  }

  void _addPair({
    required Map<String, _MetaBucket> buckets,
    required SmartBetMetaLearningDimension dimension,
    required SmartBetAnalysisRecord smartBet,
    required SmartBetAnalysisRecord diego,
    String? league,
    String? smartBetMarket,
    String? diegoMarket,
    String? probabilityPair,
  }) {
    final key = [
      dimension.name,
      league ?? '-',
      smartBetMarket ?? '-',
      diegoMarket ?? '-',
      probabilityPair ?? '-',
    ].join('|');

    final bucket = buckets.putIfAbsent(
      key,
      () => _MetaBucket(
        dimension: dimension,
        league: league,
        smartBetMarket: smartBetMarket,
        diegoMarket: diegoMarket,
        probabilityPair: probabilityPair,
      ),
    );

    bucket.add(smartBet: smartBet, diego: diego);
  }

  static String _probabilityBand(double raw) {
    final probability = raw.clamp(0.0, 1.0);

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
    SmartBetMetaLearningSegment a,
    SmartBetMetaLearningSegment b,
  ) {
    final dimensionCompare = a.dimension.index.compareTo(b.dimension.index);

    if (dimensionCompare != 0) {
      return dimensionCompare;
    }

    return a.key.compareTo(b.key);
  }
}

class _MetaBucket {
  final SmartBetMetaLearningDimension dimension;

  final String? league;
  final String? smartBetMarket;
  final String? diegoMarket;
  final String? probabilityPair;

  int sampleSize = 0;

  int bothCorrect = 0;
  int smartBetOnlyCorrect = 0;
  int diegoOnlyCorrect = 0;
  int bothWrong = 0;

  _MetaBucket({
    required this.dimension,
    required this.league,
    required this.smartBetMarket,
    required this.diegoMarket,
    required this.probabilityPair,
  });

  void add({
    required SmartBetAnalysisRecord smartBet,
    required SmartBetAnalysisRecord diego,
  }) {
    final smartCorrect = smartBet.status == SmartBetAnalysisStatus.correct;

    final diegoCorrect = diego.status == SmartBetAnalysisStatus.correct;

    sampleSize++;

    if (smartCorrect && diegoCorrect) {
      bothCorrect++;
    } else if (smartCorrect) {
      smartBetOnlyCorrect++;
    } else if (diegoCorrect) {
      diegoOnlyCorrect++;
    } else {
      bothWrong++;
    }
  }

  SmartBetMetaLearningSegment toSegment({
    required int minimumPreferenceSample,
    required double minimumAdvantagePoints,
  }) {
    final smartCorrect = bothCorrect + smartBetOnlyCorrect;

    final diegoCorrect = bothCorrect + diegoOnlyCorrect;

    final smartAccuracy = sampleSize > 0
        ? smartCorrect / sampleSize * 100.0
        : 0.0;

    final diegoAccuracy = sampleSize > 0
        ? diegoCorrect / sampleSize * 100.0
        : 0.0;

    final advantage = smartAccuracy - diegoAccuracy;

    SmartBetMetaLearningPreference preference;

    if (sampleSize < minimumPreferenceSample) {
      preference = SmartBetMetaLearningPreference.insufficientData;
    } else if (advantage.abs() < minimumAdvantagePoints) {
      preference = SmartBetMetaLearningPreference.balanced;
    } else if (advantage > 0) {
      preference = SmartBetMetaLearningPreference.smartBet;
    } else {
      preference = SmartBetMetaLearningPreference.diego;
    }

    return SmartBetMetaLearningSegment(
      dimension: dimension,
      league: league,
      smartBetMarket: smartBetMarket,
      diegoMarket: diegoMarket,
      probabilityPair: probabilityPair,
      sampleSize: sampleSize,
      bothCorrect: bothCorrect,
      smartBetOnlyCorrect: smartBetOnlyCorrect,
      diegoOnlyCorrect: diegoOnlyCorrect,
      bothWrong: bothWrong,
      smartBetAccuracy: smartAccuracy,
      diegoAccuracy: diegoAccuracy,
      advantagePercentagePoints: advantage,
      signal: SmartBetAdaptiveLearningService.signalForSample(sampleSize),
      preference: preference,
    );
  }
}
