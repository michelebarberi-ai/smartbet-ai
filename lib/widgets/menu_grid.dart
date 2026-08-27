import 'package:flutter/material.dart';

import '../screens/analysis_screen.dart';
import '../screens/combinations_ai_screen.dart';
import '../screens/create_ai_coupon_screen.dart';
import '../screens/prediction_screen.dart';
import '../screens/review_coupon_screen.dart';
import '../screens/saved_screen.dart';
import '../screens/settings_screen.dart';

class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
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
        icon: Icons.auto_awesome,
        title: 'Combinazioni\nAI',
        color: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CombinationsAiScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.psychology,
        title: 'Risultati del\nGiorno AI',
        color: const Color(0xFF00C853),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PredictionScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.auto_awesome_motion,
        title: 'Crea Schedina\nAI',
        color: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateAiCouponScreen()),
          );
        },
      ),
      _MenuItem(
        icon: Icons.fact_check_outlined,
        title: 'Revisione\nSchedina AI',
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
      _MenuItem(
        icon: Icons.settings,
        title: 'Impostazioni',
        color: Colors.grey,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.15,
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
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
