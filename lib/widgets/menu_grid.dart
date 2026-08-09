import 'package:flutter/material.dart';

import '../screens/analysis_screen.dart';

class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),

      padding: EdgeInsets.zero,

      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,

        // Altezza maggiore delle card
        childAspectRatio: 1.15,
      ),

      itemCount: 6,

      itemBuilder: (context, index) {
        const items = [
          (
            icon: Icons.sports_soccer,
            title: "Analisi\nPartite",
            color: Color(0xFF00C853),
          ),
          (
            icon: Icons.show_chart,
            title: "Quote\nConsigliate",
            color: Colors.orange,
          ),
          (
            icon: Icons.psychology,
            title: "Pronostico\nAI",
            color: Color(0xFF00C853),
          ),
          (
            icon: Icons.account_balance_wallet,
            title: "Budget",
            color: Colors.orange,
          ),
          (
            icon: Icons.star,
            title: "Pronostici\nSalvati",
            color: Color(0xFF00C853),
          ),
          (icon: Icons.settings, title: "Impostazioni", color: Colors.grey),
        ];

        final item = items[index];

        return _MenuTile(icon: item.icon, title: item.title, color: item.color);
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),

      onTap: () {
        if (title.contains("Analisi")) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnalysisScreen()),
          );
        }
      },

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
