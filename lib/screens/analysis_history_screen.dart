import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';

enum _HistoryEngineFilter { all, smartBet, diego }

enum _HistoryStatusFilter { all, pending, correct, wrong, unsupported }

class AnalysisHistoryScreen extends StatefulWidget {
  const AnalysisHistoryScreen({super.key});

  @override
  State<AnalysisHistoryScreen> createState() => _AnalysisHistoryScreenState();
}

class _AnalysisHistoryScreenState extends State<AnalysisHistoryScreen> {
  final SmartBetAnalysisHistoryStore _store =
      SmartBetAnalysisHistoryStore.instance;

  _HistoryEngineFilter _engineFilter = _HistoryEngineFilter.all;

  _HistoryStatusFilter _statusFilter = _HistoryStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _store.initialize();
  }

  List<SmartBetAnalysisRecord> _filteredRecords() {
    return _store.records
        .where((record) {
          if (_engineFilter == _HistoryEngineFilter.smartBet &&
              record.engine != SmartBetAnalysisEngine.smartBet) {
            return false;
          }

          if (_engineFilter == _HistoryEngineFilter.diego &&
              record.engine != SmartBetAnalysisEngine.diego) {
            return false;
          }

          switch (_statusFilter) {
            case _HistoryStatusFilter.all:
              return true;

            case _HistoryStatusFilter.pending:
              return record.status == SmartBetAnalysisStatus.pending;

            case _HistoryStatusFilter.correct:
              return record.status == SmartBetAnalysisStatus.correct;

            case _HistoryStatusFilter.wrong:
              return record.status == SmartBetAnalysisStatus.wrong;

            case _HistoryStatusFilter.unsupported:
              return record.status == SmartBetAnalysisStatus.unsupported;
          }
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Storico Analisi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _store,
          builder: (context, child) {
            final records = _filteredRecords();

            return Column(
              children: [
                _filters(
                  visibleCount: records.length,
                  totalCount: _store.records.length,
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: records.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          itemCount: records.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _recordCard(records[index]);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filters({required int visibleCount, required int totalCount}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Analisi registrate',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$visibleCount / $totalCount',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Motore',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              _engineChip(label: 'Tutte', value: _HistoryEngineFilter.all),
              _engineChip(
                label: 'SmartBet',
                value: _HistoryEngineFilter.smartBet,
              ),
              _engineChip(label: 'Diego', value: _HistoryEngineFilter.diego),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'Esito',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statusChip(label: 'Tutte', value: _HistoryStatusFilter.all),
                const SizedBox(width: 8),
                _statusChip(
                  label: 'Corrette',
                  value: _HistoryStatusFilter.correct,
                ),
                const SizedBox(width: 8),
                _statusChip(label: 'Errate', value: _HistoryStatusFilter.wrong),
                const SizedBox(width: 8),
                _statusChip(
                  label: 'In attesa',
                  value: _HistoryStatusFilter.pending,
                ),
                const SizedBox(width: 8),
                _statusChip(
                  label: 'Non verificabili',
                  value: _HistoryStatusFilter.unsupported,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _engineChip({
    required String label,
    required _HistoryEngineFilter value,
  }) {
    final selected = _engineFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _engineFilter = value;
        });
      },
      selectedColor: Colors.blueAccent.withValues(alpha: 0.28),
      backgroundColor: const Color(0xFF1F2937),
      side: BorderSide(color: selected ? Colors.blueAccent : Colors.white10),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white60,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      showCheckmark: false,
    );
  }

  Widget _statusChip({
    required String label,
    required _HistoryStatusFilter value,
  }) {
    final selected = _statusFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _statusFilter = value;
        });
      },
      selectedColor: Colors.purpleAccent.withValues(alpha: 0.22),
      backgroundColor: const Color(0xFF1F2937),
      side: BorderSide(color: selected ? Colors.purpleAccent : Colors.white10),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white60,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      showCheckmark: false,
    );
  }

  Widget _recordCard(SmartBetAnalysisRecord record) {
    final engineColor = record.engine == SmartBetAnalysisEngine.smartBet
        ? const Color(0xFF00C853)
        : Colors.lightBlueAccent;

    final engineLabel = record.engine == SmartBetAnalysisEngine.smartBet
        ? 'SMARTBET'
        : 'DIEGO';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: engineColor.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: engineColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                engineLabel,
                style: TextStyle(
                  color: engineColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _statusBadge(record.status),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            record.matchLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            [
              if (record.league.trim().isNotEmpty) record.league.trim(),
              if (record.country.trim().isNotEmpty) record.country.trim(),
            ].join(' • '),
            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _dataBlock(label: 'Mercato', value: record.market),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dataBlock(
                  label: 'Probabilità',
                  value: _probabilityLabel(record),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _dataBlock(
                  label: 'Partita',
                  value: _dateTimeLabel(record.matchDate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dataBlock(
                  label: 'Risultato',
                  value: _resultLabel(record),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _engineDetails(record),
          const SizedBox(height: 13),
          _dataBlock(
            label: 'Fonte',
            value: record.sources.map(_sourceLabel).join(' • '),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                record.prospectiveEligible
                    ? Icons.verified_outlined
                    : Icons.info_outline,
                size: 16,
                color: record.prospectiveEligible
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  record.prospectiveEligible
                      ? 'Analisi pre-match valida per le statistiche ufficiali'
                      : 'Analisi registrata dopo l’inizio: esclusa dalle statistiche ufficiali',
                  style: TextStyle(
                    color: record.prospectiveEligible
                        ? Colors.greenAccent.withValues(alpha: 0.75)
                        : Colors.orangeAccent.withValues(alpha: 0.8),
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Registrata ${_dateTimeLabel(record.firstSeenAt)}',
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _engineDetails(SmartBetAnalysisRecord record) {
    if (record.engine == SmartBetAnalysisEngine.smartBet) {
      return _dataBlock(
        label: 'SmartScore',
        value: record.smartScore != null ? '${record.smartScore}' : 'N/D',
      );
    }

    final values = <String>[];

    if (record.confidence != null) {
      values.add('Confidence ${record.confidence}');
    }

    final classification = record.classification?.trim();

    if (classification != null && classification.isNotEmpty) {
      values.add(classification);
    }

    if (record.qualified == false) {
      values.add('Non qualificata');
    } else if (record.qualified == true) {
      values.add('Qualificata');
    }

    return _dataBlock(
      label: 'Dettaglio Diego',
      value: values.isEmpty ? 'N/D' : values.join(' • '),
    );
  }

  Widget _dataBlock({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(SmartBetAnalysisStatus status) {
    late final String label;
    late final Color color;

    switch (status) {
      case SmartBetAnalysisStatus.correct:
        label = 'CORRETTA';
        color = Colors.greenAccent;

      case SmartBetAnalysisStatus.wrong:
        label = 'ERRATA';
        color = Colors.redAccent;

      case SmartBetAnalysisStatus.pending:
        label = 'IN ATTESA';
        color = Colors.orangeAccent;

      case SmartBetAnalysisStatus.unsupported:
        label = 'NON VERIFICABILE';
        color = Colors.white54;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _probabilityLabel(SmartBetAnalysisRecord record) {
    final probability = record.probability;

    if (probability == null) {
      return 'N/D';
    }

    return '${(probability * 100).toStringAsFixed(1)}%';
  }

  String _resultLabel(SmartBetAnalysisRecord record) {
    if (record.actualHomeGoals == null || record.actualAwayGoals == null) {
      return 'In attesa';
    }

    return '${record.actualHomeGoals} - '
        '${record.actualAwayGoals}';
  }

  String _sourceLabel(SmartBetAnalysisSource source) {
    switch (source) {
      case SmartBetAnalysisSource.analysis:
        return 'Analisi partita';

      case SmartBetAnalysisSource.aiCoupon:
        return 'Schedina AI';

      case SmartBetAnalysisSource.combinations:
        return 'Combinazioni AI';

      case SmartBetAnalysisSource.dailyResults:
        return 'Risultati del giorno';
    }
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} '
        '$hour:$minute';
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.history_toggle_off,
              color: Colors.white24,
              size: 54,
            ),
            const SizedBox(height: 14),
            const Text(
              'Nessuna analisi trovata',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _store.records.isEmpty
                  ? 'Lo storico si popolerà automaticamente '
                        'con le prossime analisi.'
                  : 'Prova a modificare i filtri selezionati.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
