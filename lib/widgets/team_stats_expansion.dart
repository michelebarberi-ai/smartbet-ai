import 'package:flutter/material.dart';

import '../models/match_model.dart';
import '../services/team_form_service.dart';

class TeamStatsExpansion extends StatefulWidget {
  final MatchModel match;

  const TeamStatsExpansion({super.key, required this.match});

  @override
  State<TeamStatsExpansion> createState() => _TeamStatsExpansionState();
}

class _TeamStatsExpansionState extends State<TeamStatsExpansion> {
  // TeamFormService usa una cache statica.
  // Manteniamo un solo client per tutti i riquadri.
  static final TeamFormService _service = TeamFormService();

  bool _expanded = false;
  bool _loading = false;
  bool _loaded = false;

  TeamFormData? _home;
  TeamFormData? _away;

  String? _error;

  Future<void> _toggle() async {
    final opening = !_expanded;

    setState(() {
      _expanded = opening;
    });

    if (opening && !_loaded && !_loading) {
      await _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<TeamFormData?>([
        _service.getTeamForm(teamId: widget.match.homeTeamId, last: 10),
        _service.getTeamForm(teamId: widget.match.awayTeamId, last: 10),
      ]);

      if (!mounted) return;

      setState(() {
        _home = results[0];
        _away = results[1];
        _loaded = true;

        if (_home == null && _away == null) {
          _error =
              'Statistiche recenti non disponibili '
              'per entrambe le squadre.';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'Non è stato possibile caricare '
            'le statistiche delle squadre.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  int? _homeVenueScore(TeamFormData? data) {
    if (data == null) return null;

    final matches = data.homeWins + data.homeDraws + data.homeLosses;

    if (matches <= 0) return null;

    return data.homePerformance;
  }

  int? _awayVenueScore(TeamFormData? data) {
    if (data == null) return null;

    final matches = data.awayWins + data.awayDraws + data.awayLosses;

    if (matches <= 0) return null;

    return data.awayPerformance;
  }

  String _record(TeamFormData? data) {
    if (data == null) return 'N/D';

    return '${data.wins}V '
        '${data.draws}X '
        '${data.losses}P';
  }

  String _matches(TeamFormData? data) {
    if (data == null) return 'N/D';

    return '${data.matchesPlayed}';
  }

  String _form(TeamFormData? data) {
    if (data == null) return 'N/D';

    return '${data.formScore}/100';
  }

  String _goalsFor(TeamFormData? data) {
    if (data == null) return 'N/D';

    return data.goalsPerMatch.toStringAsFixed(2);
  }

  String _goalsAgainst(TeamFormData? data) {
    if (data == null) return 'N/D';

    return data.concededPerMatch.toStringAsFixed(2);
  }

  String _venue(TeamFormData? data, {required bool home}) {
    final value = home ? _homeVenueScore(data) : _awayVenueScore(data);

    if (value == null) return 'N/D';

    return '$value/100';
  }

  String _summary() {
    final home = _home;
    final away = _away;

    if (home == null && away == null) {
      return 'Dati insufficienti per creare '
          'una sintesi statistica.';
    }

    if (home == null || away == null) {
      return 'Il confronto è parziale perché '
          'i dati recenti di una delle due '
          'squadre non sono disponibili.';
    }

    final notes = <String>[];

    final formDifference = home.formScore - away.formScore;

    if (formDifference.abs() >= 12) {
      notes.add(
        formDifference > 0
            ? '${widget.match.homeTeam} presenta '
                  'una forma recente migliore.'
            : '${widget.match.awayTeam} presenta '
                  'una forma recente migliore.',
      );
    }

    final homeVenue = _homeVenueScore(home);
    final awayVenue = _awayVenueScore(away);

    if (homeVenue != null &&
        awayVenue != null &&
        (homeVenue - awayVenue).abs() >= 12) {
      notes.add(
        homeVenue > awayVenue
            ? '${widget.match.homeTeam} mostra '
                  'un rendimento interno superiore '
                  'al rendimento esterno avversario.'
            : '${widget.match.awayTeam} mostra '
                  'un buon rendimento in trasferta '
                  'rispetto al rendimento interno '
                  'della squadra di casa.',
      );
    }

    final attackDifference = home.goalsPerMatch - away.goalsPerMatch;

    if (attackDifference.abs() >= 0.35) {
      notes.add(
        attackDifference > 0
            ? '${widget.match.homeTeam} segna '
                  'mediamente più gol nel campione recente.'
            : '${widget.match.awayTeam} segna '
                  'mediamente più gol nel campione recente.',
      );
    }

    final concededDifference = home.concededPerMatch - away.concededPerMatch;

    if (concededDifference.abs() >= 0.35) {
      notes.add(
        concededDifference < 0
            ? '${widget.match.homeTeam} concede '
                  'mediamente meno gol.'
            : '${widget.match.awayTeam} concede '
                  'mediamente meno gol.',
      );
    }

    if (notes.isEmpty) {
      return 'Le statistiche recenti delle due '
          'squadre risultano abbastanza equilibrate.';
    }

    return notes.take(3).join(' ');
  }

  Widget _columnTitle(String name, String venue) {
    return Expanded(
      child: Column(
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            venue,
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String home, String away) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          Expanded(
            child: Text(
              home,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              away,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 4, 14, 16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00C853),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Caricamento statistiche recenti…',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null && _home == null && _away == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 15),
        child: Text(
          _error!,
          style: const TextStyle(
            color: Colors.orangeAccent,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      );
    }

    if (!_loaded) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 104),
              _columnTitle(widget.match.homeTeam, 'CASA'),
              _columnTitle(widget.match.awayTeam, 'OSPITE'),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          _statRow('Partite analizzate', _matches(_home), _matches(_away)),
          _statRow('V / X / P', _record(_home), _record(_away)),
          _statRow('Forma recente', _form(_home), _form(_away)),
          _statRow('Gol fatti medi', _goalsFor(_home), _goalsFor(_away)),
          _statRow(
            'Gol subiti medi',
            _goalsAgainst(_home),
            _goalsAgainst(_away),
          ),
          _statRow(
            'Casa / Trasferta',
            _venue(_home, home: true),
            _venue(_away, home: false),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      color: Color(0xFF00C853),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'SINTESI STATISTICA',
                      style: TextStyle(
                        color: Color(0xFF00C853),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _summary(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dati delle ultime partite disponibili. '
            'Questa sezione è informativa e non modifica '
            'il verdetto della verifica.',
            style: TextStyle(color: Colors.white30, fontSize: 9, height: 1.35),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161F2E),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.query_stats,
                    color: Color(0xFF00C853),
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STATISTICHE SQUADRE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Forma recente • gol • '
                          'casa/trasferta',
                          style: TextStyle(color: Colors.white38, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _content(),
        ],
      ),
    );
  }
}
