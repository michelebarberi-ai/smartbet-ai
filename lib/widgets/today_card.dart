import 'package:flutter/material.dart';

class TodayCard extends StatelessWidget {
  final int? matches;
  final int? valueBets;
  final int? premium;
  final bool online;

  const TodayCard({
    super.key,
    this.matches,
    this.valueBets,
    this.premium,
    this.online = true,
  });

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
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // TITOLO
          // ======================================================
          const Row(
            children: [
              Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text(
                'OGGI',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ======================================================
          // RIGA 1
          // ======================================================
          Row(
            children: [
              Expanded(
                child: _TodayItem(
                  icon: Icons.sports_soccer,
                  color: Colors.green,
                  value: matches?.toString() ?? '—',
                  label: 'Partite',
                ),
              ),

              Expanded(
                child: _TodayItem(
                  icon: Icons.show_chart,
                  color: Colors.orange,
                  value: valueBets?.toString() ?? '—',
                  label: 'Value Bet',
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ======================================================
          // RIGA 2
          // ======================================================
          Row(
            children: [
              Expanded(
                child: _TodayItem(
                  icon: Icons.workspace_premium,
                  color: Colors.amber,
                  value: premium?.toString() ?? '—',
                  label: 'Premium',
                ),
              ),

              Expanded(
                child: _TodayItem(
                  icon: online ? Icons.check_circle : Icons.error_outline,
                  color: online ? const Color(0xFF00C853) : Colors.redAccent,
                  value: online ? 'Online' : 'Offline',
                  label: 'AI',
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
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),

              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}
