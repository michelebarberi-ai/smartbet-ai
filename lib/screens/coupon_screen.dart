import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/smartbet_coupon_service.dart';

enum _CouponView { premium, balanced, value }

class CouponScreen extends StatefulWidget {
  final SmartBetCouponSet coupons;

  const CouponScreen({super.key, required this.coupons});

  @override
  State<CouponScreen> createState() => _CouponScreenState();
}

class _CouponScreenState extends State<CouponScreen> {
  late _CouponView _selectedView;

  @override
  void initState() {
    super.initState();

    if (widget.coupons.premium.hasCoupon) {
      _selectedView = _CouponView.premium;
    } else if (widget.coupons.balanced.hasCoupon) {
      _selectedView = _CouponView.balanced;
    } else {
      _selectedView = _CouponView.value;
    }
  }

  SmartBetCouponResult get result {
    switch (_selectedView) {
      case _CouponView.premium:
        return widget.coupons.premium;
      case _CouponView.balanced:
        return widget.coupons.balanced;
      case _CouponView.value:
        return widget.coupons.value;
    }
  }

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
    return result.profileName;
  }

  Color _couponProfileColor() {
    switch (result.profileName.toUpperCase()) {
      case 'PREMIUM':
        return const Color(0xFF69F0AE);
      case 'BILANCIATA':
        return Colors.amberAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  IconData _couponProfileIcon() {
    switch (result.profileName.toUpperCase()) {
      case 'PREMIUM':
        return Icons.workspace_premium;
      case 'BILANCIATA':
        return Icons.balance;
      default:
        return Icons.trending_up;
    }
  }

  // ============================================================
  // SELETTORE STRATEGIA
  // ============================================================

  Widget _profileSelector() {
    return Row(
      children: [
        Expanded(
          child: _profileButton(
            view: _CouponView.premium,
            label: 'PREMIUM',
            icon: Icons.workspace_premium,
            available: widget.coupons.premium.hasCoupon,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _profileButton(
            view: _CouponView.balanced,
            label: 'BILANCIATA',
            icon: Icons.balance,
            available: widget.coupons.balanced.hasCoupon,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _profileButton(
            view: _CouponView.value,
            label: 'VALUE',
            icon: Icons.trending_up,
            available: widget.coupons.value.hasCoupon,
          ),
        ),
      ],
    );
  }

  Widget _profileButton({
    required _CouponView view,
    required String label,
    required IconData icon,
    required bool available,
  }) {
    final selected = _selectedView == view;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedView = view;
        });
      },
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00C853).withValues(alpha: 0.16)
              : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? const Color(0xFF00C853) : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: available
                  ? (selected ? const Color(0xFF69F0AE) : Colors.white70)
                  : Colors.white24,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: available
                    ? (selected ? Colors.white : Colors.white70)
                    : Colors.white30,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              available ? 'DISPONIBILE' : 'N/D',
              style: TextStyle(
                color: available ? Colors.white38 : Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
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
  // CONDIVIDI SCHEDINA
  // ============================================================

  Future<void> _shareCoupon() async {
    if (!result.hasCoupon) {
      return;
    }

    final probability = result.estimatedCombinedProbability * 100;

    final text = StringBuffer()
      ..writeln('SMARTBET AI — SCHEDINA ${result.profileName.toUpperCase()}')
      ..writeln()
      ..writeln('${result.selectionCount} selezioni')
      ..writeln('Quota totale: ${result.totalOdd.toStringAsFixed(2)}')
      ..writeln(
        'Qualità media: ${result.averageSmartScore.toStringAsFixed(0)}%',
      )
      ..writeln('Probabilità stimata: ${probability.toStringAsFixed(1)}%')
      ..writeln('Rischio: ${result.riskLevel}')
      ..writeln(
        'Stake consigliato: '
        '${result.recommendedStakePercent.toStringAsFixed(2)}%',
      )
      ..writeln();

    for (var i = 0; i < result.selections.length; i++) {
      final selection = result.selections[i];

      text.writeln(
        '${i + 1}. ${selection.matchLabel} → '
        '${selection.outcome} @ ${selection.odd.toStringAsFixed(2)}',
      );

      if (selection.bookmaker.trim().isNotEmpty) {
        text.writeln('   Quota rilevata: ${selection.bookmaker}');
      }
    }

    text
      ..writeln()
      ..writeln(
        'Analisi statistica a scopo informativo. '
        'Gioca responsabilmente.',
      );

    await SharePlus.instance.share(
      ShareParams(
        text: text.toString(),
        subject: 'SmartBet AI — Schedina ${result.profileName.toUpperCase()}',
      ),
    );
  }

  Widget _shareCouponButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: result.hasCoupon ? _shareCoupon : null,
        icon: const Icon(Icons.ios_share_outlined),
        label: Text('CONDIVIDI SCHEDINA ${result.profileName.toUpperCase()}'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: const Color(0xFF00C853),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
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
            _profileSelector(),

            const SizedBox(height: 16),

            if (!result.hasCoupon) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: _emptyCoupon(context),
              ),
            ] else ...[
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

              const SizedBox(height: 14),

              _shareCouponButton(),

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
                        'Premium privilegia qualità e prudenza. '
                        'Bilanciata cerca un compromesso tra affidabilità '
                        'e quota. Value accetta opportunità più aggressive '
                        'solo dopo i controlli SmartBet. '
                        'La probabilità stimata considera che tutti gli '
                        'eventi debbano risultare corretti.',
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
          ],
        ),
      ),
    );
  }
}
