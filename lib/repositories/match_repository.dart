import '../models/match_model.dart';
import '../services/match_service.dart';

class MatchRepository {
  static List<MatchModel> getTodayMatches() {
    return MatchService.getTodayMatches();
  }
}
