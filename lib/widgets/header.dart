import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return "Buongiorno 👋";
    } else if (hour < 18) {
      return "Buon pomeriggio 👋";
    } else {
      return "Buonasera 🌙";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C853).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/smartbet_app_icon.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),

                const SizedBox(height: 6),

                const Text(
                  "SMARTBET AI",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 3),

                const Text(
                  "La tua assistente intelligente",
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
