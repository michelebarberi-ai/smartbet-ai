import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_rate_limiter.dart';
import 'team_data_resolver.dart';

class EuropeanLeagueStrength {
  final int leagueId;
  final String leagueName;

  final double rating;

  /// Incertezza model-based del rating penalizzato.
  ///
  /// Non è ancora una confidence calibrata e non viene
  /// utilizzata per modificare Diego o gli xG.
  final double? standardError;

  final int previousMainMatches;
  final int currentQualifyingMatches;
  final int currentMainMatches;

  final int uniqueOpposingLeagues;
  final double weightedEvidence;

  /// D2B.2:
  /// volutamente N/D finché non viene calibrata separatamente.
  final double? confidence;

  const EuropeanLeagueStrength({
    required this.leagueId,
    required this.leagueName,
    required this.rating,
    required this.standardError,
    required this.previousMainMatches,
    required this.currentQualifyingMatches,
    required this.currentMainMatches,
    required this.uniqueOpposingLeagues,
    required this.weightedEvidence,
    required this.confidence,
  });

  double get ratingDelta => rating - 1500.0;

  bool get hasCalibratedConfidence => confidence != null;
}

class EuropeanLeagueComparison {
  final int firstLeagueId;
  final int secondLeagueId;

  final double ratingDifference;
  final double standardError;
  final double signalToNoise;

  /// Gate empirico D2B.2.
  ///
  /// Non rappresenta una confidence percentuale.
  final bool passesEvidenceGate;

  const EuropeanLeagueComparison({
    required this.firstLeagueId,
    required this.secondLeagueId,
    required this.ratingDifference,
    required this.standardError,
    required this.signalToNoise,
    required this.passesEvidenceGate,
  });
}

class EuropeanLeagueStrengthSnapshot {
  /// Prima soglia supportata dal walk-forward OOS
  /// e dal cluster bootstrap D2B.2.
  ///
  /// Non è una percentuale di confidence.
  static const double minimumInformativeSignalToNoise = 1.0;

  final int currentSeason;
  final DateTime referenceDate;
  final DateTime firstMainStageDate;

  final int previousMainFixtures;
  final int currentQualifyingFixtures;
  final int currentMainFixtures;

  final int ambiguousScoreFixtures;
  final int unfinishedPastFixtures;
  final int unresolvedLeagueFixtures;
  final int sameLeagueFixtures;
  final int fallbackTeamResolutions;

  /// Covarianza dei rating espressa direttamente in punti rating.
  ///
  /// Serve esclusivamente alla diagnostica dell'incertezza D2B.2.
  final Map<int, Map<int, double>> ratingCovariance;

  final List<EuropeanLeagueStrength> leagues;

  const EuropeanLeagueStrengthSnapshot({
    required this.currentSeason,
    required this.referenceDate,
    required this.firstMainStageDate,
    required this.previousMainFixtures,
    required this.currentQualifyingFixtures,
    required this.currentMainFixtures,
    required this.ambiguousScoreFixtures,
    required this.unfinishedPastFixtures,
    required this.unresolvedLeagueFixtures,
    required this.sameLeagueFixtures,
    required this.fallbackTeamResolutions,
    required this.ratingCovariance,
    required this.leagues,
  });

  EuropeanLeagueStrength? forLeague(int leagueId) {
    for (final league in leagues) {
      if (league.leagueId == leagueId) {
        return league;
      }
    }

    return null;
  }

  /// Standard error della DIFFERENZA tra due rating.
  ///
  /// Usa:
  /// Var(A - B) = Var(A) + Var(B) - 2 Cov(A, B)
  ///
  /// Questo è preferibile a trattare i due rating come indipendenti.
  double? ratingDifferenceStandardError(int firstLeagueId, int secondLeagueId) {
    final firstRow = ratingCovariance[firstLeagueId];
    final secondRow = ratingCovariance[secondLeagueId];

    if (firstRow == null || secondRow == null) {
      return null;
    }

    final firstVariance = firstRow[firstLeagueId];
    final secondVariance = secondRow[secondLeagueId];
    final covariance = firstRow[secondLeagueId];

    if (firstVariance == null || secondVariance == null || covariance == null) {
      return null;
    }

    final variance = firstVariance + secondVariance - (2.0 * covariance);

    if (!variance.isFinite || variance < -1e-9) {
      return null;
    }

    return math.sqrt(math.max(0.0, variance));
  }

  /// Confronto diagnostico D2B.2 fra due campionati.
  ///
  /// Restituisce rating difference, standard error,
  /// signal-to-noise e superamento del gate OOS.
  ///
  /// Non modifica Diego, non modifica gli xG
  /// e non produce una confidence percentuale.
  EuropeanLeagueComparison? compareLeagues(
    int firstLeagueId,
    int secondLeagueId,
  ) {
    final first = forLeague(firstLeagueId);
    final second = forLeague(secondLeagueId);

    if (first == null || second == null) {
      return null;
    }

    final standardError = ratingDifferenceStandardError(
      firstLeagueId,
      secondLeagueId,
    );

    if (standardError == null ||
        !standardError.isFinite ||
        standardError <= 0.0) {
      return null;
    }

    final difference = first.rating - second.rating;

    final signalToNoise = difference.abs() / standardError;

    return EuropeanLeagueComparison(
      firstLeagueId: firstLeagueId,
      secondLeagueId: secondLeagueId,
      ratingDifference: difference,
      standardError: standardError,
      signalToNoise: signalToNoise,
      passesEvidenceGate: signalToNoise >= minimumInformativeSignalToNoise,
    );
  }
}

abstract class EuropeanLeagueStrengthSnapshotStore {
  Future<EuropeanLeagueStrengthSnapshot?> read({
    required int currentSeason,
    required DateTime referenceDate,
  });

  Future<void> write(EuropeanLeagueStrengthSnapshot snapshot);
}

class EuropeanLeagueStrengthService {
  // ============================================================
  // MODELLO VALIDATO D2B.2
  // ============================================================

  static const double previousMainWeight = 1.00;
  static const double currentQualifyingWeight = 0.50;
  static const double currentMainWeight = 1.00;

  static const double lambda = 3.00;

  static const int _iterations = 5000;
  static const double _learningRate = 0.01;

  static const Set<int> _europeanCompetitionIds = {
    2, // Champions League
    3, // Europa League
    848, // Conference League
  };

  static const Set<String> _finishedStatuses = {'FT', 'AET', 'PEN'};

  late final http.Client _client;
  late final TeamDataResolver _teamDataResolver;

  final EuropeanLeagueStrengthSnapshotStore? snapshotStore;

  final bool _ownsClient;

  final Map<String, List<Map<String, dynamic>>> _bulkFixtureCache = {};
  final Map<String, ResolvedTeamLeague> _resolvedLeagueCache = {};
  final Map<String, EuropeanLeagueStrengthSnapshot> _snapshotCache = {};

  EuropeanLeagueStrengthService({
    http.Client? client,
    TeamDataResolver? teamDataResolver,
    TeamLeagueCacheStore? teamLeagueCacheStore,
    this.snapshotStore,
  }) : _ownsClient = client == null {
    _client = client ?? http.Client();

    _teamDataResolver =
        teamDataResolver ??
        TeamDataResolver(
          client: _client,
          leagueCacheStore: teamLeagueCacheStore,
        );
  }

  // ============================================================
  // BUILD
  // ============================================================

  Future<EuropeanLeagueStrengthSnapshot?> build({
    required int currentSeason,
    required DateTime referenceDate,
  }) async {
    if (currentSeason <= 0) {
      return null;
    }

    // Stessa convenzione del walk-forward validato:
    // nessun risultato dello stesso giorno viene utilizzato.
    final utc = referenceDate.toUtc();

    final cutoff = DateTime.utc(utc.year, utc.month, utc.day);

    final snapshotKey = '$currentSeason|${_dayKey(cutoff)}';

    final cachedSnapshot = _snapshotCache[snapshotKey];

    if (cachedSnapshot != null) {
      return cachedSnapshot;
    }

    final persistentStore = snapshotStore;

    if (persistentStore != null) {
      try {
        final persisted = await persistentStore.read(
          currentSeason: currentSeason,
          referenceDate: cutoff,
        );

        if (persisted != null) {
          _snapshotCache[snapshotKey] = persisted;
          return persisted;
        }
      } catch (_) {
        // La persistenza è un'ottimizzazione:
        // un errore di storage non deve bloccare il modello.
      }
    }

    final previousSeason = currentSeason - 1;

    final previousRaw = await _fetchSeason(
      season: previousSeason,
      cacheDate: cutoff,
    );

    if (previousRaw == null) {
      return null;
    }

    final currentRaw = await _fetchSeason(
      season: currentSeason,
      cacheDate: cutoff,
    );

    if (currentRaw == null) {
      return null;
    }

    final previousFixtures = _parseBaseFixtures(previousRaw);
    final currentFixtures = _parseBaseFixtures(currentRaw);

    final currentMainAll = currentFixtures
        .where((fixture) => _isMainStage(fixture.round))
        .toList();

    if (currentMainAll.isEmpty) {
      return null;
    }

    currentMainAll.sort((a, b) => a.date.compareTo(b.date));

    final firstMainStageDate = currentMainAll.first.date;

    // ------------------------------------------------------------
    // STAGIONE PRECEDENTE
    // SOLO LEAGUE/GROUP STAGE
    // ------------------------------------------------------------

    final previousMainCandidates = previousFixtures
        .where(
          (fixture) =>
              _isMainStage(fixture.round) && fixture.date.isBefore(cutoff),
        )
        .toList();

    // ------------------------------------------------------------
    // STAGIONE CORRENTE - QUALIFICAZIONI
    //
    // Non usiamo la parola "play-off":
    // qualsiasi gara NON main-stage disputata prima
    // dell'inizio della League Stage è pre-main.
    //
    // In questo modo "Knockout Round Play-offs"
    // post-main non può contaminare il modello.
    // ------------------------------------------------------------

    final currentQualifyingCandidates = currentFixtures
        .where(
          (fixture) =>
              !_isMainStage(fixture.round) &&
              fixture.date.isBefore(firstMainStageDate) &&
              fixture.date.isBefore(cutoff),
        )
        .toList();

    // ------------------------------------------------------------
    // STAGIONE CORRENTE - MAIN STAGE
    // SOLO risultati precedenti al giorno target.
    // ------------------------------------------------------------

    final currentMainCandidates = currentFixtures
        .where(
          (fixture) =>
              _isMainStage(fixture.round) && fixture.date.isBefore(cutoff),
        )
        .toList();

    final diagnostics = _BuildDiagnostics();

    final previousMain = _canonicalize(previousMainCandidates, diagnostics);

    final currentQualifying = _canonicalize(
      currentQualifyingCandidates,
      diagnostics,
    );

    final currentMain = _canonicalize(currentMainCandidates, diagnostics);

    // ============================================================
    // TEAM -> DOMESTIC LEAGUE
    // ============================================================

    final previousTeams = _collectTeams(previousMain);
    final currentTeams = _collectTeams([...currentQualifying, ...currentMain]);

    final previousLeagueMap = await _resolveDomesticLeagues(
      teams: previousTeams,
      season: previousSeason,
      diagnostics: diagnostics,
    );

    final currentLeagueMap = await _resolveDomesticLeagues(
      teams: currentTeams,
      season: currentSeason,
      diagnostics: diagnostics,
    );

    // ============================================================
    // CROSS-LEAGUE EVIDENCE
    // ============================================================

    final evidence = <_LeagueMatchEvidence>[];

    final leagueNames = <int, String>{};
    final counters = <int, _LeagueEvidenceCounter>{};

    void addSource({
      required List<_CanonicalEuropeanFixture> fixtures,
      required Map<int, ResolvedTeamLeague> leagueMap,
      required _EvidenceSource source,
      required double weight,
    }) {
      for (final fixture in fixtures) {
        final homeLeague = leagueMap[fixture.homeTeamId];
        final awayLeague = leagueMap[fixture.awayTeamId];

        if (homeLeague == null || awayLeague == null) {
          diagnostics.unresolvedLeagueFixtures++;
          continue;
        }

        if (homeLeague.leagueId == awayLeague.leagueId) {
          diagnostics.sameLeagueFixtures++;
          continue;
        }

        leagueNames[homeLeague.leagueId] = homeLeague.leagueName;
        leagueNames[awayLeague.leagueId] = awayLeague.leagueName;

        final homeCounter = counters.putIfAbsent(
          homeLeague.leagueId,
          _LeagueEvidenceCounter.new,
        );

        final awayCounter = counters.putIfAbsent(
          awayLeague.leagueId,
          _LeagueEvidenceCounter.new,
        );

        homeCounter.add(
          source: source,
          weight: weight,
          opposingLeagueId: awayLeague.leagueId,
        );

        awayCounter.add(
          source: source,
          weight: weight,
          opposingLeagueId: homeLeague.leagueId,
        );

        evidence.add(
          _LeagueMatchEvidence(
            homeLeagueId: homeLeague.leagueId,
            awayLeagueId: awayLeague.leagueId,
            result: fixture.result,
            weight: weight,
          ),
        );
      }
    }

    addSource(
      fixtures: previousMain,
      leagueMap: previousLeagueMap,
      source: _EvidenceSource.previousMain,
      weight: previousMainWeight,
    );

    addSource(
      fixtures: currentQualifying,
      leagueMap: currentLeagueMap,
      source: _EvidenceSource.currentQualifying,
      weight: currentQualifyingWeight,
    );

    addSource(
      fixtures: currentMain,
      leagueMap: currentLeagueMap,
      source: _EvidenceSource.currentMain,
      weight: currentMainWeight,
    );

    if (evidence.isEmpty || leagueNames.isEmpty) {
      return null;
    }

    // ============================================================
    // REGULARIZED LEAGUE MODEL
    //
    // - nessuna quota
    // - nessun home advantage
    // - nessun goal margin
    // - pareggio = 0.5
    // - modello order-independent
    // ============================================================

    final fit = _fitRatings(
      evidence: evidence,
      leagueIds: leagueNames.keys.toList(),
    );

    final strengths = <EuropeanLeagueStrength>[];

    for (final entry in fit.ratings.entries) {
      final counter = counters[entry.key] ?? _LeagueEvidenceCounter();

      strengths.add(
        EuropeanLeagueStrength(
          leagueId: entry.key,
          leagueName: leagueNames[entry.key] ?? 'League ${entry.key}',
          rating: entry.value,
          standardError: fit.standardErrors[entry.key],
          previousMainMatches: counter.previousMainMatches,
          currentQualifyingMatches: counter.currentQualifyingMatches,
          currentMainMatches: counter.currentMainMatches,
          uniqueOpposingLeagues: counter.opposingLeagues.length,
          weightedEvidence: counter.weightedEvidence,

          // Non inventiamo una confidence.
          confidence: null,
        ),
      );
    }

    strengths.sort((a, b) => b.rating.compareTo(a.rating));

    final snapshot = EuropeanLeagueStrengthSnapshot(
      currentSeason: currentSeason,
      referenceDate: cutoff,
      firstMainStageDate: firstMainStageDate,
      previousMainFixtures: previousMain.length,
      currentQualifyingFixtures: currentQualifying.length,
      currentMainFixtures: currentMain.length,
      ambiguousScoreFixtures: diagnostics.ambiguousScoreFixtures,
      unfinishedPastFixtures: diagnostics.unfinishedPastFixtures,
      unresolvedLeagueFixtures: diagnostics.unresolvedLeagueFixtures,
      sameLeagueFixtures: diagnostics.sameLeagueFixtures,
      fallbackTeamResolutions: diagnostics.fallbackTeamResolutions,
      ratingCovariance: fit.ratingCovariance,
      leagues: List.unmodifiable(strengths),
    );

    _snapshotCache[snapshotKey] = snapshot;

    if (persistentStore != null) {
      try {
        await persistentStore.write(snapshot);
      } catch (_) {
        // Il risultato appena calcolato resta valido
        // anche se il salvataggio persistente fallisce.
      }
    }

    return snapshot;
  }

  // ============================================================
  // FIT
  // ============================================================

  _LeagueModelFit _fitRatings({
    required List<_LeagueMatchEvidence> evidence,
    required List<int> leagueIds,
  }) {
    final orderedLeagueIds = List<int>.from(leagueIds)..sort();

    final index = <int, int>{
      for (var i = 0; i < orderedLeagueIds.length; i++) orderedLeagueIds[i]: i,
    };

    final theta = List<double>.filled(orderedLeagueIds.length, 0.0);

    // ==========================================================
    // STIMA RATING
    // ==========================================================

    for (var iteration = 0; iteration < _iterations; iteration++) {
      final gradient = List<double>.filled(theta.length, 0.0);

      for (final match in evidence) {
        final homeIndex = index[match.homeLeagueId];
        final awayIndex = index[match.awayLeagueId];

        if (homeIndex == null || awayIndex == null) {
          continue;
        }

        final probability = _sigmoid(theta[homeIndex] - theta[awayIndex]);

        final error = (match.result - probability) * match.weight;

        gradient[homeIndex] += error;
        gradient[awayIndex] -= error;
      }

      for (var i = 0; i < theta.length; i++) {
        gradient[i] -= lambda * theta[i];
      }

      var maxChange = 0.0;

      for (var i = 0; i < theta.length; i++) {
        final change = _learningRate * gradient[i];

        theta[i] += change;

        maxChange = math.max(maxChange, change.abs());
      }

      final mean =
          theta.fold<double>(0.0, (sum, value) => sum + value) / theta.length;

      for (var i = 0; i < theta.length; i++) {
        theta[i] -= mean;
      }

      if (maxChange < 1e-9) {
        break;
      }
    }

    final eloScale = 400.0 / math.log(10.0);

    final ratings = <int, double>{
      for (var i = 0; i < orderedLeagueIds.length; i++)
        orderedLeagueIds[i]: 1500.0 + (theta[i] * eloScale),
    };

    // ==========================================================
    // INFORMATION MATRIX / PENALIZED HESSIAN
    // ==========================================================
    //
    // Per ogni incontro:
    //
    // information = weight * p * (1-p)
    //
    // La ridge regularization aggiunge lambda alla diagonale.
    //
    // L'inversa fornisce una misura model-based
    // dell'incertezza dei parametri penalizzati.
    //
    // IMPORTANTE:
    // questo NON è ancora una confidence calibrata.
    // ==========================================================

    final information = List.generate(
      theta.length,
      (_) => List<double>.filled(theta.length, 0.0),
    );

    for (final match in evidence) {
      final homeIndex = index[match.homeLeagueId];
      final awayIndex = index[match.awayLeagueId];

      if (homeIndex == null || awayIndex == null) {
        continue;
      }

      final probability = _sigmoid(theta[homeIndex] - theta[awayIndex]);

      final matchInformation = match.weight * probability * (1.0 - probability);

      information[homeIndex][homeIndex] += matchInformation;

      information[awayIndex][awayIndex] += matchInformation;

      information[homeIndex][awayIndex] -= matchInformation;

      information[awayIndex][homeIndex] -= matchInformation;
    }

    for (var i = 0; i < information.length; i++) {
      information[i][i] += lambda;
    }

    final thetaCovariance = _invertMatrix(information);

    final standardErrors = <int, double?>{};
    final ratingCovariance = <int, Map<int, double>>{};

    if (thetaCovariance == null) {
      for (final leagueId in orderedLeagueIds) {
        standardErrors[leagueId] = null;
      }
    } else {
      final scaleSquared = eloScale * eloScale;

      for (var i = 0; i < orderedLeagueIds.length; i++) {
        final leagueId = orderedLeagueIds[i];

        final row = <int, double>{};

        for (var j = 0; j < orderedLeagueIds.length; j++) {
          row[orderedLeagueIds[j]] = thetaCovariance[i][j] * scaleSquared;
        }

        ratingCovariance[leagueId] = Map.unmodifiable(row);

        final variance = row[leagueId];

        if (variance == null || !variance.isFinite || variance < -1e-9) {
          standardErrors[leagueId] = null;
        } else {
          standardErrors[leagueId] = math.sqrt(math.max(0.0, variance));
        }
      }
    }

    return _LeagueModelFit(
      ratings: Map.unmodifiable(ratings),
      standardErrors: Map.unmodifiable(standardErrors),
      ratingCovariance: Map.unmodifiable(ratingCovariance),
    );
  }

  List<List<double>>? _invertMatrix(List<List<double>> matrix) {
    final n = matrix.length;

    if (n == 0) {
      return <List<double>>[];
    }

    final augmented = List.generate(n, (row) {
      final result = List<double>.filled(n * 2, 0.0);

      for (var column = 0; column < n; column++) {
        result[column] = matrix[row][column];
      }

      result[n + row] = 1.0;

      return result;
    });

    for (var column = 0; column < n; column++) {
      var pivotRow = column;
      var pivotMagnitude = augmented[column][column].abs();

      for (var row = column + 1; row < n; row++) {
        final candidate = augmented[row][column].abs();

        if (candidate > pivotMagnitude) {
          pivotMagnitude = candidate;
          pivotRow = row;
        }
      }

      if (!pivotMagnitude.isFinite || pivotMagnitude < 1e-12) {
        return null;
      }

      if (pivotRow != column) {
        final temp = augmented[column];
        augmented[column] = augmented[pivotRow];
        augmented[pivotRow] = temp;
      }

      final pivot = augmented[column][column];

      for (var j = 0; j < n * 2; j++) {
        augmented[column][j] /= pivot;
      }

      for (var row = 0; row < n; row++) {
        if (row == column) {
          continue;
        }

        final factor = augmented[row][column];

        if (factor.abs() < 1e-15) {
          continue;
        }

        for (var j = 0; j < n * 2; j++) {
          augmented[row][j] -= factor * augmented[column][j];
        }
      }
    }

    return List.generate(
      n,
      (row) => List.generate(n, (column) => augmented[row][n + column]),
    );
  }

  double _sigmoid(double value) {
    if (value >= 0) {
      final z = math.exp(-value);
      return 1.0 / (1.0 + z);
    }

    final z = math.exp(value);
    return z / (1.0 + z);
  }

  // ============================================================
  // BULK EUROPEAN FIXTURES
  // ============================================================

  Future<List<Map<String, dynamic>>?> _fetchSeason({
    required int season,
    required DateTime cacheDate,
  }) async {
    final all = <Map<String, dynamic>>[];

    for (final leagueId in _europeanCompetitionIds) {
      final fixtures = await _fetchCompetitionFixtures(
        leagueId: leagueId,
        season: season,
        cacheDate: cacheDate,
      );

      if (fixtures == null) {
        return null;
      }

      all.addAll(fixtures);
    }

    return all;
  }

  Future<List<Map<String, dynamic>>?> _fetchCompetitionFixtures({
    required int leagueId,
    required int season,
    required DateTime cacheDate,
  }) async {
    final cacheKey = '$season|$leagueId|${_dayKey(cacheDate)}';

    final cached = _bulkFixtureCache[cacheKey];

    if (cached != null) {
      return cached;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {
        'league': leagueId.toString(),
        'season': season.toString(),
      },
    );

    try {
      await ApiRateLimiter.wait();

      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        return null;
      }

      final responseData = decoded['response'];

      if (responseData is! List) {
        return null;
      }

      final result = <Map<String, dynamic>>[];

      for (final item in responseData) {
        if (item is Map<String, dynamic>) {
          result.add(item);
        }
      }

      _bulkFixtureCache[cacheKey] = result;

      return result;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // RAW FIXTURE PARSER
  // ============================================================

  List<_RawEuropeanFixture> _parseBaseFixtures(
    List<Map<String, dynamic>> source,
  ) {
    final byFixtureId = <int, _RawEuropeanFixture>{};

    for (final item in source) {
      final fixture = item['fixture'];
      final league = item['league'];
      final teams = item['teams'];

      if (fixture is! Map<String, dynamic> ||
          league is! Map<String, dynamic> ||
          teams is! Map<String, dynamic>) {
        continue;
      }

      final fixtureId = _toInt(fixture['id']);

      if (fixtureId <= 0) {
        continue;
      }

      final date = DateTime.tryParse(fixture['date']?.toString() ?? '');

      if (date == null) {
        continue;
      }

      final home = teams['home'];
      final away = teams['away'];

      if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
        continue;
      }

      final homeId = _toInt(home['id']);
      final awayId = _toInt(away['id']);

      if (homeId <= 0 || awayId <= 0) {
        continue;
      }

      final statusData = fixture['status'];

      final statusShort = statusData is Map<String, dynamic>
          ? statusData['short']?.toString().toUpperCase().trim() ?? ''
          : '';

      byFixtureId.putIfAbsent(
        fixtureId,
        () => _RawEuropeanFixture(
          fixtureId: fixtureId,
          date: date.toUtc(),
          round: league['round']?.toString() ?? '',
          statusShort: statusShort,
          homeTeamId: homeId,
          homeTeamName: home['name']?.toString() ?? 'Team $homeId',
          awayTeamId: awayId,
          awayTeamName: away['name']?.toString() ?? 'Team $awayId',
          raw: item,
        ),
      );
    }

    return byFixtureId.values.toList();
  }

  // ============================================================
  // CANONICAL 90'
  // ============================================================

  List<_CanonicalEuropeanFixture> _canonicalize(
    List<_RawEuropeanFixture> fixtures,
    _BuildDiagnostics diagnostics,
  ) {
    final result = <_CanonicalEuropeanFixture>[];

    for (final fixture in fixtures) {
      if (!_finishedStatuses.contains(fixture.statusShort)) {
        diagnostics.unfinishedPastFixtures++;
        continue;
      }

      final score = _canonical90Score(fixture.raw, fixture.statusShort);

      if (score == null) {
        diagnostics.ambiguousScoreFixtures++;
        continue;
      }

      final homeGoals = score.$1;
      final awayGoals = score.$2;

      final matchResult = homeGoals > awayGoals
          ? 1.0
          : homeGoals < awayGoals
          ? 0.0
          : 0.5;

      result.add(
        _CanonicalEuropeanFixture(
          fixtureId: fixture.fixtureId,
          date: fixture.date,
          homeTeamId: fixture.homeTeamId,
          homeTeamName: fixture.homeTeamName,
          awayTeamId: fixture.awayTeamId,
          awayTeamName: fixture.awayTeamName,
          result: matchResult,
        ),
      );
    }

    return result;
  }

  (int, int)? _canonical90Score(Map<String, dynamic> item, String statusShort) {
    final goals = item['goals'];
    final score = item['score'];

    if (goals is! Map<String, dynamic> || score is! Map<String, dynamic>) {
      return null;
    }

    final total = _scorePair(goals);
    final fulltime = _scorePair(score['fulltime']);

    if (total == null || fulltime == null) {
      return null;
    }

    if (statusShort == 'FT' || statusShort == 'PEN') {
      if (total != fulltime) {
        return null;
      }

      return fulltime;
    }

    if (statusShort == 'AET') {
      final extraTime = _scorePair(score['extratime']);

      if (extraTime == null) {
        return null;
      }

      final expectedTotal = (
        fulltime.$1 + extraTime.$1,
        fulltime.$2 + extraTime.$2,
      );

      if (total != expectedTotal) {
        return null;
      }

      return fulltime;
    }

    return null;
  }

  (int, int)? _scorePair(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final home = _nullableInt(value['home']);
    final away = _nullableInt(value['away']);

    if (home == null || away == null) {
      return null;
    }

    return (home, away);
  }

  // ============================================================
  // DOMESTIC LEAGUE RESOLUTION
  // ============================================================

  Map<int, String> _collectTeams(List<_CanonicalEuropeanFixture> fixtures) {
    final teams = <int, String>{};

    for (final fixture in fixtures) {
      teams[fixture.homeTeamId] = fixture.homeTeamName;
      teams[fixture.awayTeamId] = fixture.awayTeamName;
    }

    return teams;
  }

  Future<Map<int, ResolvedTeamLeague>> _resolveDomesticLeagues({
    required Map<int, String> teams,
    required int season,
    required _BuildDiagnostics diagnostics,
  }) async {
    final result = <int, ResolvedTeamLeague>{};

    // Stessa fotografia usata nei backtest.
    final seasonReference = DateTime.utc(season, 10, 20, 23, 59);

    for (final entry in teams.entries) {
      final cacheKey = '${entry.key}|$season';

      var resolved = _resolvedLeagueCache[cacheKey];

      if (resolved == null) {
        resolved = await _teamDataResolver.resolveCurrentLeagueOnly(
          teamId: entry.key,
          teamName: entry.value,
          referenceDate: seasonReference,
        );

        if (resolved != null) {
          _resolvedLeagueCache[cacheKey] = resolved;
        }
      }

      if (resolved == null) {
        continue;
      }

      if (resolved.season != season) {
        diagnostics.fallbackTeamResolutions++;
      }

      result[entry.key] = resolved;
    }

    return result;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  bool _isMainStage(String round) {
    final normalized = round.toLowerCase().trim();

    return normalized.contains('league stage') ||
        normalized.contains('group stage');
  }

  String _dayKey(DateTime value) {
    final utc = value.toUtc();

    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  void clearCache() {
    _bulkFixtureCache.clear();
    _resolvedLeagueCache.clear();
    _snapshotCache.clear();
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _LeagueModelFit {
  final Map<int, double> ratings;
  final Map<int, double?> standardErrors;

  /// Covarianza espressa in punti rating².
  final Map<int, Map<int, double>> ratingCovariance;

  const _LeagueModelFit({
    required this.ratings,
    required this.standardErrors,
    required this.ratingCovariance,
  });
}

enum _EvidenceSource { previousMain, currentQualifying, currentMain }

class _LeagueEvidenceCounter {
  int previousMainMatches = 0;
  int currentQualifyingMatches = 0;
  int currentMainMatches = 0;

  double weightedEvidence = 0.0;

  final Set<int> opposingLeagues = {};

  void add({
    required _EvidenceSource source,
    required double weight,
    required int opposingLeagueId,
  }) {
    switch (source) {
      case _EvidenceSource.previousMain:
        previousMainMatches++;
      case _EvidenceSource.currentQualifying:
        currentQualifyingMatches++;
      case _EvidenceSource.currentMain:
        currentMainMatches++;
    }

    weightedEvidence += weight;
    opposingLeagues.add(opposingLeagueId);
  }
}

class _LeagueMatchEvidence {
  final int homeLeagueId;
  final int awayLeagueId;

  final double result;
  final double weight;

  const _LeagueMatchEvidence({
    required this.homeLeagueId,
    required this.awayLeagueId,
    required this.result,
    required this.weight,
  });
}

class _RawEuropeanFixture {
  final int fixtureId;
  final DateTime date;

  final String round;
  final String statusShort;

  final int homeTeamId;
  final String homeTeamName;

  final int awayTeamId;
  final String awayTeamName;

  final Map<String, dynamic> raw;

  const _RawEuropeanFixture({
    required this.fixtureId,
    required this.date,
    required this.round,
    required this.statusShort,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.raw,
  });
}

class _CanonicalEuropeanFixture {
  final int fixtureId;
  final DateTime date;

  final int homeTeamId;
  final String homeTeamName;

  final int awayTeamId;
  final String awayTeamName;

  final double result;

  const _CanonicalEuropeanFixture({
    required this.fixtureId,
    required this.date,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.result,
  });
}

class _BuildDiagnostics {
  int ambiguousScoreFixtures = 0;
  int unfinishedPastFixtures = 0;

  int unresolvedLeagueFixtures = 0;
  int sameLeagueFixtures = 0;

  int fallbackTeamResolutions = 0;
}
