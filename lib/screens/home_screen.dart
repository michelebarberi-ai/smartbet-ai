import '../widgets/menu_grid.dart';
import 'package:flutter/material.dart';
import '../widgets/today_card.dart';
import '../widgets/header.dart';
import '../widgets/ai_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget statCard(IconData icon, String value, String title, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget menuCard(IconData icon, String text, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 5,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded),
        onTap: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const HomeHeader(),

            const AiCard(),
            const TodayCard(),

            const SizedBox(height: 25),

            const Text(
              "Le tue statistiche",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                statCard(
                  Icons.psychology,
                  "84%",
                  "Affidabilità",
                  const Color(0xFF00C853),
                ),

                statCard(
                  Icons.account_balance_wallet,
                  "+183€",
                  "Profitto",
                  Colors.orange,
                ),
                statCard(Icons.star, "82%", "Precisione", Colors.amber),
              ],
            ),

            const SizedBox(height: 30),

            const Text(
              "Funzioni",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 15),
            const Text(
              "I tuoi strumenti",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 18),

            const MenuGrid(),
          ],
        ),
      ),
    );
  }
}
