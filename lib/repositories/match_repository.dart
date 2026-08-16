import '../models/match_model.dart';
import '../services/api_match_service.dart';

class MatchRepository {
  static final ApiMatchService _api = ApiMatchService();

  // ============================================================
  // PARTITE DI OGGI
  // ============================================================

  static Future<List<MatchModel>> getTodayMatches() async {
    return await _api.getTodayMatches();
  }

  // ============================================================
  // PARTITE PER DATA SPECIFICA
  // ============================================================

  static Future<List<MatchModel>> getMatchesByDate(DateTime date) async {
    return await _api.getMatchesByDate(date);
  }
}
