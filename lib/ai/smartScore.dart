import '../models/analysis_result.dart';
import '../models/match_model.dart';

class AiEngine {
  static AnalysisResult analyze(MatchModel match) {
    String risk;

    if (match.smartScore >= 90) {
      risk = "Basso";
    } else if (match.smartScore >= 75) {
      risk = "Medio";
    } else {
      risk = "Alto";
    }

    return AnalysisResult(
      smartScore: match.smartScore,

      homeProbability: match.homeWin,
      drawProbability: match.draw,
      awayProbability: match.awayWin,

      valueBet: match.valueBet,
      odd: match.odd,

      risk: risk,

      explanation: _buildExplanation(match),
    );
  }

  static String _buildExplanation(MatchModel match) {
    return "${match.homeTeam} presenta una probabilità stimata del "
        "${match.homeWin}% secondo il modello. "
        "La giocata suggerita è '${match.valueBet}' "
        "con quota ${match.odd.toStringAsFixed(2)}. "
        "Questa è una prima analisi dimostrativa: nelle prossime versioni verranno considerate forma recente, infortuni, scontri diretti, andamento delle quote e altri indicatori.";
  }
}
