import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../models/team_analysis.dart';
import '../services/team_form_service.dart';
import 'statistics_engine.dart';
import 'team_analyzer.dart';

class SmartCore {
  const SmartCore._();

  static final TeamFormService _formService = TeamFormService();

  // ============================================================
  // ANALISI REALE DELLA PARTITA
  // ============================================================

  static Future<AnalysisResult> analyze(MatchModel match) async {
    // ----------------------------------------------------------
    // CONTROLLO ID
    // ----------------------------------------------------------

    if (!match.hasTeamIds) {
      return _insufficientDataResult("ID delle squadre non disponibili.");
    }

    // ----------------------------------------------------------
    // RECUPERO FORMA CASA + OSPITE IN PARALLELO
    // ----------------------------------------------------------
    //
    // Prima queste due richieste venivano eseguite una dopo l'altra.
    // Ora partono contemporaneamente per ridurre i tempi di attesa.
    // ----------------------------------------------------------

    final forms = await Future.wait([
      _formService.getTeamForm(teamId: match.homeTeamId, last: 10),
      _formService.getTeamForm(teamId: match.awayTeamId, last: 10),
    ]);

    final homeForm = forms[0];
    final awayForm = forms[1];

    // ----------------------------------------------------------
    // DATI NON DISPONIBILI
    // ----------------------------------------------------------

    if (homeForm == null || awayForm == null) {
      return _insufficientDataResult(
        "Non sono state trovate abbastanza partite recenti "
        "per una o entrambe le squadre.",
      );
    }

    // ----------------------------------------------------------
    // CONTROLLO NUMERO PARTITE
    // ----------------------------------------------------------

    if (homeForm.matchesPlayed < 3 || awayForm.matchesPlayed < 3) {
      return _insufficientDataResult(
        "Dati recenti insufficienti per una previsione affidabile.",
      );
    }

    // ----------------------------------------------------------
    // CONVERSIONE DATI -> TEAM ANALYSIS
    // ----------------------------------------------------------

    final TeamAnalysis homeAnalysis = TeamAnalyzer.analyzeFromForm(
      homeForm,
      isHome: true,
    );

    final TeamAnalysis awayAnalysis = TeamAnalyzer.analyzeFromForm(
      awayForm,
      isHome: false,
    );

    // ----------------------------------------------------------
    // CONTROLLO DATI
    // ----------------------------------------------------------

    if (!homeAnalysis.hasEnoughData || !awayAnalysis.hasEnoughData) {
      return _insufficientDataResult(
        "Dati statistici insufficienti per una previsione affidabile.",
      );
    }

    // ----------------------------------------------------------
    // SMART SCORE
    // ----------------------------------------------------------

    final smartScore = StatisticsEngine.calculateFromTeams(
      homeTeam: homeAnalysis,
      awayTeam: awayAnalysis,
      competitionWeight: match.aiWeight,
    );

    // ==========================================================
    // PROBABILITÀ 1X2
    // ==========================================================

    final probabilities = StatisticsEngine.calculateProbabilities(
      homeTeam: homeAnalysis,
      awayTeam: awayAnalysis,
    );

    final homeProbability = probabilities['home'] ?? 0;

    final drawProbability = probabilities['draw'] ?? 0;

    final awayProbability = probabilities['away'] ?? 0;

    // ==========================================================
    // PROBABILITÀ MERCATI GOL
    // ==========================================================

    final goalMarkets = StatisticsEngine.calculateGoalMarketProbabilities(
      homeForm: homeForm,
      awayForm: awayForm,
    );

    final over15Probability = goalMarkets['over15'] ?? 0;

    final under15Probability = goalMarkets['under15'] ?? 0;

    final over25Probability = goalMarkets['over25'] ?? 0;

    final under25Probability = goalMarkets['under25'] ?? 0;

    final goalProbability = goalMarkets['goal'] ?? 0;

    final noGoalProbability = goalMarkets['noGoal'] ?? 0;

    // ==========================================================
    // EXPECTED GOALS
    // ==========================================================

    final expectedGoals = StatisticsEngine.calculateExpectedGoals(
      homeForm: homeForm,
      awayForm: awayForm,
    );

    final expectedHomeGoals = expectedGoals['home'] ?? 0.0;

    final expectedAwayGoals = expectedGoals['away'] ?? 0.0;

    final expectedTotalGoals = expectedGoals['total'] ?? 0.0;

    // ----------------------------------------------------------
    // PRONOSTICO 1X2
    // ----------------------------------------------------------

    final prediction = _calculatePrediction(
      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,
    );

    // ----------------------------------------------------------
    // RISCHIO
    // ----------------------------------------------------------

    final risk = _calculateRisk(smartScore);

    // ----------------------------------------------------------
    // VALUE BET
    // ----------------------------------------------------------
    //
    // Per ora resta riferita all'1X2.
    //
    // Nel passaggio successivo collegheremo
    // quote reali anche a Over/Under e Goal/No Goal.
    // ----------------------------------------------------------

    final valueBet = _calculateValueBet(
      match: match,
      prediction: prediction,
      probability: _predictionProbability(
        prediction: prediction,
        homeProbability: homeProbability,
        drawProbability: drawProbability,
        awayProbability: awayProbability,
      ),
    );

    // ----------------------------------------------------------
    // SPIEGAZIONE
    // ----------------------------------------------------------

    final explanation = _buildExplanation(
      home: homeAnalysis,
      away: awayAnalysis,
      smartScore: smartScore,
      prediction: prediction,
      homeForm: homeForm,
      awayForm: awayForm,
      over15Probability: over15Probability,
      under15Probability: under15Probability,
      over25Probability: over25Probability,
      under25Probability: under25Probability,
      goalProbability: goalProbability,
      noGoalProbability: noGoalProbability,
      expectedHomeGoals: expectedHomeGoals,
      expectedAwayGoals: expectedAwayGoals,
      expectedTotalGoals: expectedTotalGoals,
    );

    // ----------------------------------------------------------
    // SALVIAMO I RISULTATI NEL MATCH
    // ----------------------------------------------------------

    match.smartScore = smartScore;

    match.homeWin = homeProbability;

    match.draw = drawProbability;

    match.awayWin = awayProbability;

    match.valueBet = valueBet;

    // ----------------------------------------------------------
    // RISULTATO
    // ----------------------------------------------------------

    return AnalysisResult(
      smartScore: smartScore,

      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,

      over15Probability: over15Probability,
      under15Probability: under15Probability,

      over25Probability: over25Probability,
      under25Probability: under25Probability,

      goalProbability: goalProbability,
      noGoalProbability: noGoalProbability,

      prediction: prediction,

      valueBet: valueBet,

      risk: risk,

      explanation: explanation,
    );
  }

  // ============================================================
  // PRONOSTICO
  // ============================================================

  static String _calculatePrediction({
    required int homeProbability,
    required int drawProbability,
    required int awayProbability,
  }) {
    if (homeProbability >= drawProbability &&
        homeProbability >= awayProbability) {
      return "1";
    }

    if (awayProbability >= homeProbability &&
        awayProbability >= drawProbability) {
      return "2";
    }

    return "X";
  }

  // ============================================================
  // PROBABILITÀ DEL PRONOSTICO
  // ============================================================

  static int _predictionProbability({
    required String prediction,
    required int homeProbability,
    required int drawProbability,
    required int awayProbability,
  }) {
    switch (prediction) {
      case "1":
        return homeProbability;

      case "2":
        return awayProbability;

      case "X":
        return drawProbability;

      default:
        return 0;
    }
  }

  // ============================================================
  // RISCHIO
  // ============================================================

  static String _calculateRisk(int smartScore) {
    if (smartScore >= 90) {
      return "Molto Basso";
    }

    if (smartScore >= 80) {
      return "Basso";
    }

    if (smartScore >= 70) {
      return "Medio";
    }

    if (smartScore >= 60) {
      return "Medio-Alto";
    }

    return "Alto";
  }

  // ============================================================
  // VALUE BET
  // ============================================================

  static String _calculateValueBet({
    required MatchModel match,
    required String prediction,
    required int probability,
  }) {
    if (match.odd <= 1.0) {
      return "Da verificare";
    }

    final impliedProbability = (1 / match.odd) * 100;

    final difference = probability - impliedProbability;

    if (difference >= 8) {
      return "SI";
    }

    if (difference >= 3) {
      return "Possibile";
    }

    return "NO";
  }

  // ============================================================
  // SPIEGAZIONE
  // ============================================================

  static String _buildExplanation({
    required TeamAnalysis home,
    required TeamAnalysis away,
    required int smartScore,
    required String prediction,
    required TeamFormData homeForm,
    required TeamFormData awayForm,

    required int over15Probability,
    required int under15Probability,

    required int over25Probability,
    required int under25Probability,

    required int goalProbability,
    required int noGoalProbability,

    required double expectedHomeGoals,
    required double expectedAwayGoals,
    required double expectedTotalGoals,
  }) {
    final homeResults = homeForm.recentResults.isEmpty
        ? "N/D"
        : homeForm.recentResults.join(" ");

    final awayResults = awayForm.recentResults.isEmpty
        ? "N/D"
        : awayForm.recentResults.join(" ");

    return """
FORMA CASA: ${home.form}
FORMA OSPITE: ${away.form}

ULTIME PARTITE CASA:
$homeResults

ULTIME PARTITE OSPITE:
$awayResults

ATTACCO CASA: ${home.attack}
ATTACCO OSPITE: ${away.attack}

DIFESA CASA: ${home.defense}
DIFESA OSPITE: ${away.defense}

RENDIMENTO CASA: ${home.homePerformance}
RENDIMENTO TRASFERTA: ${away.awayPerformance}

GOL FATTI CASA: ${homeForm.goalsFor}
GOL SUBITI CASA: ${homeForm.goalsAgainst}

GOL FATTI OSPITE: ${awayForm.goalsFor}
GOL SUBITI OSPITE: ${awayForm.goalsAgainst}

EXPECTED GOALS CASA: ${expectedHomeGoals.toStringAsFixed(2)}
EXPECTED GOALS OSPITE: ${expectedAwayGoals.toStringAsFixed(2)}
EXPECTED GOALS TOTALI: ${expectedTotalGoals.toStringAsFixed(2)}

MERCATI GOL:

OVER 1.5: $over15Probability%
UNDER 1.5: $under15Probability%

OVER 2.5: $over25Probability%
UNDER 2.5: $under25Probability%

GOAL: $goalProbability%
NO GOAL: $noGoalProbability%

SMART SCORE: $smartScore

PRONOSTICO 1X2 CONSIGLIATO: $prediction
""";
  }

  // ============================================================
  // DATI INSUFFICIENTI
  // ============================================================

  static AnalysisResult _insufficientDataResult(String reason) {
    return AnalysisResult(
      smartScore: 0,

      homeProbability: 0,
      drawProbability: 0,
      awayProbability: 0,

      over15Probability: 0,
      under15Probability: 0,

      over25Probability: 0,
      under25Probability: 0,

      goalProbability: 0,
      noGoalProbability: 0,

      prediction: "N/D",

      valueBet: "N/D",

      risk: "Dati insufficienti",

      explanation:
          """
ANALISI NON DISPONIBILE

$reason

SmartBet non genera un pronostico
quando i dati statistici non sono sufficienti.
""",
    );
  }
}
