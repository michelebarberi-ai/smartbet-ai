import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../models/team_analysis.dart';

import 'decision_engine.dart';
import 'match_analyzer.dart';
import 'team_analyzer.dart';

class SmartCore {
  static AnalysisResult analyze(MatchModel match) {
    final TeamAnalysis home = TeamAnalyzer.analyze(
      teamName: match.homeTeam,
      form: 85,
      attack: 88,
      defense: 84,
      homeAway: 92,
      motivation: 87,
    );

    final TeamAnalysis away = TeamAnalyzer.analyze(
      teamName: match.awayTeam,
      form: 80,
      attack: 82,
      defense: 79,
      homeAway: 74,
      motivation: 84,
    );

    final comparison = MatchAnalyzer.analyze(homeTeam: home, awayTeam: away);

    return DecisionEngine.analyze(comparison);
  }
}
