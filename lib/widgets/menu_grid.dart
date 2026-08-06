import '../screens/analysis_screen.dart';
import 'package:flutter/material.dart';

class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 2.1,
      children: const [
        _MenuTile(
          icon: Icons.sports_soccer,
          title: "Analisi\nPartite",
          color: Color(0xFF00C853),
        ),
        _MenuTile(
          icon: Icons.show_chart,
          title: "Quote\nConsigliate",
          color: Colors.orange,
        ),
        _MenuTile(
          icon: Icons.psychology,
          title: "Pronostico\nAI",
          color: Color(0xFF00C853),
        ),
        _MenuTile(
          icon: Icons.account_balance_wallet,
          title: "Budget",
          color: Colors.orange,
        ),
        _MenuTile(
          icon: Icons.star,
          title: "Pronostici\nSalvati",
          color: Color(0xFF00C853),
        ),
        _MenuTile(
          icon: Icons.settings,
          title: "Impostazioni",
          color: Colors.grey,
        ),
      ],
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
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
