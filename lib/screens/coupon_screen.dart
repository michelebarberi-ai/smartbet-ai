import 'package:flutter/material.dart';

import '../services/smartbet_coupon_service.dart';

class CouponScreen extends StatelessWidget {
  final SmartBetCouponResult result;

  const CouponScreen({super.key, required this.result});

  // ============================================================
  // COLORI
  // ============================================================

  Color _scoreColor(int score) {
    if (score >= 80) {
      return const Color(0xFF00C853);
    }

    if (score >= 70) {
      return Colors.orange;
    }

    return Colors.redAccent;
  }

  Color _riskColor(String risk) {
    final value = risk.toLowerCase();

    if (value.contains('contenuto') || value.contains('basso')) {
      return const Color(0xFF00C853);
    }

    if (value.contains('medio-alto') || value.contains('alto')) {
      return Colors.redAccent;
    }

    return Colors.orange;
  }

  // ============================================================
  // PROFILO SCHEDINA
  // ============================================================

  String _couponProfile() {
    final score = result.averageSmartScore;

    if (score >= 78) {
      return 'PREMIUM';
    }

    if (score >= 68) {
      return 'BILANCIATA';
    }

    return 'VALUE CONTROLLATO';
  }

  Color _couponProfileColor() {
    final score = result.averageSmartScore;

    if (score >= 78) {
      return const Color(0xFF69F0AE);
    }

    if (score >= 68) {
      return Colors.amberAccent;
    }

    return Colors.orangeAccent;
  }

  IconData _couponProfileIcon() {
    final score = result.averageSmartScore;

    if (score >= 78) {
      return Icons.workspace_premium;
    }

    if (score >= 68) {
      return Icons.balance;
    }

    return Icons.trending_up;
  }

  // ============================================================
  // CARD RIASSUNTO
  // ============================================================

  Widget _summaryCard() {
    final probability = result.estimatedCombinedProbability * 100;

    final profileColor = _couponProfileColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C853), Color(0xFF009688)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white24,
                child: Icon(Icons.auto_awesome, color: Colors.white),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SCHEDINA SMARTBET',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '${result.selectionCount} selezioni consigliate',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: profileColor.withValues(alpha: 0.70),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _couponProfileIcon(),
                            size: 15,
                            color: profileColor,
                          ),

                          const SizedBox(width: 6),

                          Text(
                            _couponProfile(),
                            style: TextStyle(
                              color: profileColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: _summaryValue(
                  'QUOTA',
                  result.totalOdd.toStringAsFixed(2),
                ),
              ),

              Expanded(
                child: _summaryValue(
                  'QUALITÀ',
                  '${result.averageSmartScore.toStringAsFixed(0)}%',
                ),
              ),

              Expanded(
                child: _summaryValue(
                  'PROB. STIMATA',
                  '${probability.toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          const Divider(color: Colors.white24),

          const SizedBox(height: 12),

          Row(
            children: [
              const Text(
                'Rischio schedina',
                style: TextStyle(color: Colors.white70),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  result.riskLevel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SELEZIONE
  // ============================================================

  Widget _selectionCard(SmartBetCouponSelection selection, int index) {
    final scoreColor = _scoreColor(selection.smartScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Text(
                  selection.matchLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _detailBox(
                  'PRONOSTICO',
                  selection.outcome,
                  const Color(0xFF00C853),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _detailBox(
                  'QUOTA',
                  selection.odd.toStringAsFixed(2),
                  Colors.amber,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _detailBox(
                  'SMART SCORE',
                  '${selection.smartScore}',
                  scoreColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              const Icon(Icons.sports_score, color: Colors.white38, size: 17),

              const SizedBox(width: 6),

              Expanded(
                child: Text(
                  selection.match.league,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),

          if (selection.bookmaker.trim().isNotEmpty) ...[
            const SizedBox(height: 7),

            Row(
              children: [
                const Icon(
                  Icons.account_balance,
                  color: Colors.white38,
                  size: 17,
                ),

                const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    'Quota rilevata: ${selection.bookmaker}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 7),

          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: _riskColor(selection.risk),
                size: 17,
              ),

              const SizedBox(width: 6),

              Expanded(
                child: Text(
                  'Rischio: ${selection.risk}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STAKE
  // ============================================================

  Widget _stakeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF00C853).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0x2200C853),
            child: Icon(Icons.account_balance_wallet, color: Color(0xFF00C853)),
          ),

          const SizedBox(width: 13),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stake consigliato',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),

                SizedBox(height: 3),

                Text(
                  'Percentuale del bankroll',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),

          Text(
            '${result.recommendedStakePercent.toStringAsFixed(2)}%',
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NESSUNA SCHEDINA
  // ============================================================

  Widget _emptyCoupon(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, color: Colors.orange, size: 65),

            const SizedBox(height: 18),

            const Text(
              'Nessuna schedina consigliata',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              result.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.4),
            ),

            const SizedBox(height: 25),

            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('TORNA ALLE PARTITE'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (!result.hasCoupon) {
      return Scaffold(
        backgroundColor: const Color(0xFF111827),
        appBar: AppBar(
          title: const Text(
            'Schedina SmartBet',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF111827),
        ),
        body: _emptyCoupon(context),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        title: const Text(
          'Schedina SmartBet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF111827),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            _summaryCard(),

            const SizedBox(height: 24),

            const Text(
              'Selezioni SmartBet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              '${result.analyzedMatches} partite analizzate • '
              '${result.validCandidates} candidate valide • '
              '${result.rejectedMatches} escluse',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),

            const SizedBox(height: 15),

            ...List.generate(
              result.selections.length,
              (index) => _selectionCard(result.selections[index], index),
            ),

            const SizedBox(height: 8),

            _stakeCard(),

            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.20),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),

                  SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'La qualità media indica la qualità '
                      'delle singole selezioni. La probabilità '
                      'stimata della schedina considera invece '
                      'che tutti gli eventi debbano risultare '
                      'corretti.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
