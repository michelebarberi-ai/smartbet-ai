import 'package:flutter/material.dart';

import '../widgets/ai_card.dart';
import '../widgets/header.dart';
import '../widgets/menu_grid.dart';
import '../widgets/today_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget statCard(IconData icon, String value, String title, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),

            const SizedBox(height: 10),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 5),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            // HEADER
            const HomeHeader(),

            // AI CARD
            const AiCard(),

            // OGGI
            const TodayCard(),

            const SizedBox(height: 18),

            // STATISTICHE
            const Text(
              "Le tue statistiche",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            // CARD STATISTICHE
            SizedBox(
              height: 155,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
            ),

            const SizedBox(height: 35),

            // STRUMENTI
            const Text(
              "I tuoi strumenti",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            const MenuGrid(),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}
