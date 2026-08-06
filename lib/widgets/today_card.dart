import 'package:flutter/material.dart';

class TodayCard extends StatelessWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text(
                "OGGI",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: const [
              Expanded(
                child: _TodayItem(
                  icon: Icons.sports_soccer,
                  color: Colors.green,
                  value: "18",
                  label: "Partite",
                ),
              ),
              Expanded(
                child: _TodayItem(
                  icon: Icons.show_chart,
                  color: Colors.orange,
                  value: "6",
                  label: "Quote",
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: const [
              Expanded(
                child: _TodayItem(
                  icon: Icons.workspace_premium,
                  color: Colors.amber,
                  value: "3",
                  label: "Premium",
                ),
              ),
              Expanded(
                child: _TodayItem(
                  icon: Icons.check_circle,
                  color: Color(0xFF00C853),
                  value: "Online",
                  label: "AI",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _TodayItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ],
    );
  }
}
