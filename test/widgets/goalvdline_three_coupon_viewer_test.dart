import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_three_coupon_system.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_three_coupon_viewer.dart';

MatchModel match(int id, String home, String away, String league) {
  return MatchModel(
    fixtureId: id,
    homeTeamId: id * 2,
    awayTeamId: id * 2 + 1,
    homeTeam: home,
    awayTeam: away,
    league: league,
    leagueId: 101,
    country: 'Italy',
    countryCode: 'IT',
    date: '2026-11-14T15:00:00Z',
    leagueType: 'League',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.7,
    smartScore: 70,
    homeWin: 30,
    draw: 30,
    awayWin: 40,
    valueBet: '',
    odd: 1.30,
  );
}

GoalVdLineSystemSelection selection(
  int id,
  String market,
  int probability, {
  double odd = 1.30,
  String bookmaker = 'Bookmaker Test',
}) {
  return GoalVdLineSystemSelection(
    fixtureId: id,
    market: market,
    probability: probability,
    odd: odd,
    bookmaker: bookmaker,
  );
}

void main() {
  final originals = [
    selection(1, '1X', 77),
    selection(2, 'OVER 1.5', 85),
    selection(3, 'UNDER 3.5', 88),
  ];
  final alternatives1 = [
    selection(1, 'GOAL', 72, odd: 1.40, bookmaker: 'Alt Bookmaker'),
    originals[1],
    originals[2],
  ];
  final alternatives2 = [
    selection(1, 'OVER 2.5', 70, odd: 1.45),
    originals[1],
    originals[2],
  ];

  Future<void> mount(WidgetTester tester, VoidCallback share) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF111827),
          body: SizedBox(
            height: 700,
            child: GoalVdLineThreeCouponViewer(
              coupons: [originals, alternatives1, alternatives2],
              matchesById: {
                1: match(1, 'Team Alpha', 'Team Beta', 'Serie C'),
                2: match(2, 'Team Gamma', 'Team Delta', 'Serie B'),
                3: match(3, 'Team Epsilon', 'Team Zeta', 'Serie A'),
              },
              onShareAll: share,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('B50: original coupon shows full readable details',
      (tester) async {
    await mount(tester, () {});
    expect(find.text('3 SCHEDINE — STESSE PARTITE'), findsOneWidget);
    expect(find.text('ORIGINALE'), findsWidgets);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2.20'), findsOneWidget);
    expect(find.text('1. Team Alpha - Team Beta'), findsOneWidget);
    expect(find.text('ITALIA · Serie C'), findsOneWidget);
    expect(find.text('1X'), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    expect(find.text('@ 1.30'), findsWidgets);
    expect(find.text('Bookmaker Test'), findsWidgets);
    expect(find.textContaining('MERCATO ALTERNATIVO'), findsNothing);
  });

  testWidgets('B50: switching tabs changes visual details, not match order',
      (tester) async {
    await mount(tester, () {});
    await tester.tap(find.byKey(const ValueKey('b50-three-coupon-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('ALTERNATIVA 1'), findsWidgets);
    expect(find.text('GOAL'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('@ 1.40'), findsOneWidget);
    expect(find.text('Alt Bookmaker'), findsOneWidget);
    expect(find.textContaining('MERCATO ALTERNATIVO'), findsOneWidget);
    expect(find.text('1. Team Alpha - Team Beta'), findsOneWidget);
    expect(find.text('1X'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('b50-three-coupon-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('OVER 2.5'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('1. Team Alpha - Team Beta'), findsOneWidget);
  });

  testWidgets('B50: share remains explicit across all three variants',
      (tester) async {
    var shared = 0;
    await mount(tester, () => shared++);
    await tester.tap(find.text('CONDIVIDI LE 3 SCHEDINE'));
    expect(shared, 1);
  });
}
