import 'package:flutter/material.dart';

class AiCard extends StatelessWidget {
  // Vecchi parametri mantenuti per compatibilità.
  final double? reliability;
  final int? matches;
  final int? valueBets;
  final int? premium;

  final int? liveMatches;
  final int? todayMatches;
  final int? analysesPerformed;

  final bool online;
  final bool loading;

  final DateTime? lastUpdate;

  const AiCard({
    super.key,
    this.reliability,
    this.matches,
    this.valueBets,
    this.premium,
    this.liveMatches,
    this.todayMatches,
    this.analysesPerformed,
    this.online = true,
    this.loading = false,
    this.lastUpdate,
  });

  String get _updateLabel {
    if (loading) {
      return 'Aggiornamento dati...';
    }

    final date = lastUpdate;

    if (date == null) {
      return 'Sincronizzazione SmartBet';
    }

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return 'Aggiornato alle $hour:$minute';
  }

  String _value(int? value) {
    if (value != null) {
      return value.toString();
    }

    return loading ? '...' : '—';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF00C853), Color(0xFF009688)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 21,
                backgroundColor: Colors.white24,
                child: Icon(Icons.psychology, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? 'SMARTBET AI' : 'SMARTBET NON DISPONIBILE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _updateLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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
                  loading
                      ? 'SYNC'
                      : online
                      ? 'ONLINE'
                      : 'OFFLINE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Info(
                  icon: Icons.live_tv,
                  value: _value(liveMatches),
                  label: 'Live',
                ),
              ),
              Expanded(
                child: _Info(
                  icon: Icons.calendar_today,
                  value: _value(todayMatches),
                  label: 'Analizzabili',
                ),
              ),
              Expanded(
                child: _Info(
                  icon: Icons.analytics_outlined,
                  value: '${analysesPerformed ?? 0}',
                  label: 'Analisi',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
          radius: 18,
          backgroundColor: Colors.white24,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
