import 'package:flutter/material.dart';

class AiCard extends StatelessWidget {
  final double? reliability;
  final int? matches;
  final int? valueBets;
  final int? premium;
  final bool online;

  const AiCard({
    super.key,
    this.reliability,
    this.matches,
    this.valueBets,
    this.premium,
    this.online = true,
  });

  // ============================================================
  // ORARIO AGGIORNAMENTO
  // ============================================================

  String _currentTime() {
    final now = DateTime.now();

    final hour = now.hour.toString().padLeft(2, '0');

    final minute = now.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  // ============================================================
  // AFFIDABILITÀ
  // ============================================================

  double get _progressValue {
    if (reliability == null) {
      return 0.0;
    }

    return (reliability! / 100.0).clamp(0.0, 1.0);
  }

  String get _reliabilityLabel {
    if (reliability == null) {
      return 'In calcolo';
    }

    return '${reliability!.toStringAsFixed(0)}%';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF00C853), Color(0xFF009688)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // HEADER
          // ======================================================
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white24,
                child: Icon(Icons.psychology, color: Colors.white, size: 24),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? 'AI PRONTA' : 'AI NON DISPONIBILE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Aggiornato alle ${_currentTime()}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  online ? 'ONLINE' : 'OFFLINE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ======================================================
          // AFFIDABILITÀ
          // ======================================================
          const Text(
            'Indice di affidabilità',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _progressValue,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                reliability == null ? Colors.white38 : const Color(0xFFFF9800),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _reliabilityLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),

          const SizedBox(height: 22),

          const Divider(color: Colors.white24, height: 1),

          const SizedBox(height: 18),

          // ======================================================
          // DATI
          // ======================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Info(
                icon: Icons.sports_soccer,
                value: matches?.toString() ?? '—',
                label: 'Partite',
              ),

              _Info(
                icon: Icons.trending_up,
                value: valueBets?.toString() ?? '—',
                label: 'Value Bet',
              ),

              _Info(
                icon: Icons.workspace_premium,
                value: premium?.toString() ?? '—',
                label: 'Premium',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INFO
// ============================================================

class _Info extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Info({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white24,
          child: Icon(icon, color: Colors.white, size: 20),
        ),

        const SizedBox(height: 8),

        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),

        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
