import '../models/match_model.dart';
import '../services/api_match_service.dart';

class MatchRepository {
  static final ApiMatchService _api = ApiMatchService();

  static Future<List<MatchModel>> getTodayMatches() async {
    return await _api.getTodayMatches();
  }
}
