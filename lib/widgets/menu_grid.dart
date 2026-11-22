import 'package:flutter/material.dart';

import '../screens/analysis_screen.dart';
import '../screens/personal_coupons_screen.dart';
import '../screens/combinations_ai_screen.dart';
import '../screens/create_ai_coupon_screen.dart';
import '../screens/live_analysis_screen.dart';
import '../screens/prediction_screen.dart';
import '../screens/review_coupon_screen.dart';
import '../screens/saved_screen.dart';
import '../screens/scorers_screen.dart';

class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem(
        icon: Icons.confirmation_number_outlined,
        title: 'Le mie\\nSchedine',
        color: const Color(0xFF27E887),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PersonalCouponsScreen())),
      ),
      _MenuItem(
        icon: Icons.live_tv,
        title: 'Analisi Live\nAI',
        color: Colors.redAccent,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveAnalysisScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.sports_soccer,
        title: 'Analisi\nPartite',
        color: const Color(0xFF00C853),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnalysisScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.auto_awesome_motion,
        title: 'Crea Schedina\nGoalVdLine',
        color: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateAiCouponScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.auto_awesome,
        title: 'Combinazioni\nGoalVdLine',
        color: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CombinationsAiScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.sports_soccer_outlined,
        title: 'Possibili\nMarcatori',
        color: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScorersScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.psychology,
        title: 'Risultati del\nGiorno',
        color: const Color(0xFF00C853),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PredictionScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.fact_check_outlined,
        title: 'Revisione\nSchedina GoalVdLine',
        color: const Color(0xFF00C853),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReviewCouponScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.star,
        title: 'Pronostici\nSalvati',
        color: const Color(0xFF00C853),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SavedScreen()),
          );
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.36,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return _MenuTile(
          icon: item.icon,
          title: item.title,
          color: item.color,
          onTap: item.onTap,
        );
      },
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF142B40),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF29455C)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 10),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
