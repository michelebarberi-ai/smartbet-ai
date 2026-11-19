import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smartbet_ai_new/services/api_rate_limiter.dart';
import 'package:smartbet_ai_new/services/team_form_service.dart';

void main() {
  test('B74: parallel analysis callers are paced without a simultaneous burst',
      () async {
    final started = <DateTime>[];
    await Future.wait(List.generate(4, (_) async {
      await ApiRateLimiter.wait();
      started.add(DateTime.now());
    }));
    expect(started, hasLength(4));
    for (var i = 1; i < started.length; i++) {
      // Permit ordinary CI timer jitter while rejecting the old behavior:
      // four futures all waking after the same 250 ms pause.
      expect(started[i].difference(started[i - 1]).inMilliseconds,
          greaterThanOrEqualTo(330));
    }
  });

  test('B74: duplicate team form requests share one HTTP lookup', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{"errors":{},"response":[]}', 200,
          headers: {'content-type': 'application/json'});
    });
    final service = TeamFormService(client: client);
    try {
      final answers = await Future.wait(List.generate(
        5,
        (_) => service.getTeamForm(teamId: 87654321, last: 10),
      ));
      expect(answers, everyElement(isNull));
      expect(requests, 1);
    } finally {
      client.close();
    }
  });
}
