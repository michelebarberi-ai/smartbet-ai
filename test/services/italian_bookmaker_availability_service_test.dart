import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/italian_bookmaker_availability_service.dart';

void main() {
  final when = DateTime.utc(2026, 11, 17, 0).toIso8601String();
  Map<String, dynamic> response({
    required List<Object> ids,
    int pagesRead = 1,
    int pagesTotal = 1,
    bool complete = true,
  }) => {
    'success': true,
    'fixtureIds': ids,
    'pagesRead': pagesRead,
    'pagesTotal': pagesTotal,
    'complete': complete,
    'verifiedAt': when,
  };

  test('B63: filter uses verified fixture IDs, never league names', () {
    final parsed = ItalianBookmakerAvailabilityService.parseResponse(
      response(ids: [101, 102, 102, -1, '103']),
    );
    expect(parsed.quotedFixtureIds, {101, 102});
    expect(parsed.complete, true);
    expect(parsed.verifiedAt, DateTime.utc(2026, 11, 17));
  });

  test('B63: incomplete bookmaker coverage is explicitly preserved', () {
    final parsed = ItalianBookmakerAvailabilityService.parseResponse(
      response(ids: [101], pagesRead: 12, pagesTotal: 35, complete: false),
    );
    expect(parsed.quotedFixtureIds, {101});
    expect(parsed.complete, false);
    expect(parsed.pagesTotal, 35);
  });

  test('B63: inconsistent or fake quote availability is rejected', () {
    expect(
      () => ItalianBookmakerAvailabilityService.parseResponse(
        response(ids: [1], pagesRead: 1, pagesTotal: 2, complete: true),
      ),
      throwsFormatException,
    );
    expect(
      () => ItalianBookmakerAvailabilityService.parseResponse({
        'success': false,
        'fixtureIds': [],
      }),
      throwsFormatException,
    );
  });
}
