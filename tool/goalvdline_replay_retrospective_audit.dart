// ignore_for_file: avoid_print
//
// B54: verifica RETROSPETTIVA ESPLORATIVA di un archivio già tracciato.
// Gli xG del CSV NON sono dimostrati snapshot congelati prima del kickoff:
// questo strumento NON autorizza promozioni o cambi alle schedine.
import 'dart:io';

import '../lib/services/goalvdline_minute_replay_service.dart';

List<String> _csvColumns(String line) {
  final columns = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final c = line[index];
    if (c == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      columns.add(field.toString());
      field.clear();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV: virgolette non chiuse');
  columns.add(field.toString());
  return columns;
}

double _brier1x2(Map<String, double> prediction, String actual) {
  var total = 0.0;
  for (final outcome in ['1', 'X', '2']) {
    final error = prediction[outcome]! - (outcome == actual ? 1.0 : 0.0);
    total += error * error;
  }
  return total;
}

double _brier(double p, bool occurred) {
  final error = p - (occurred ? 1.0 : 0.0);
  return error * error;
}

void main(List<String> args) {
  final path = args.isEmpty
      ? 'tool/goalvdline_match_engine_validation_results.csv'
      : args.first;
  final lines = File(path).readAsLinesSync();
  if (lines.isEmpty) throw StateError('CSV vuoto');
  final columns = _csvColumns(lines.first);
  final index = <String, int>{
    for (var i = 0; i < columns.length; i++) columns[i]: i,
  };
  const required = <String>[
    'fixture_id', 'actual', 'expected_home_goals', 'expected_away_goals',
    'p1', 'px', 'p2', 'actual_over25', 'p_over25',
    'actual_goal', 'p_goal',
  ];
  if (required.any((key) => !index.containsKey(key))) {
    throw const FormatException('CSV: campi richiesti mancanti');
  }
  const engine = GoalVdLineMinuteReplayService();
  var valid = 0;
  var excluded = 0;
  var originalOneXTwo = 0.0;
  var replayOneXTwo = 0.0;
  var originalOver = 0.0;
  var replayOver = 0.0;
  var originalGoal = 0.0;
  var replayGoal = 0.0;

  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final values = _csvColumns(line);
    String read(String key) => values[index[key]!];
    final id = int.tryParse(read('fixture_id'));
    final h = double.tryParse(read('expected_home_goals'));
    final a = double.tryParse(read('expected_away_goals'));
    final original = <String, double>{
      '1': double.tryParse(read('p1')) ?? double.nan,
      'X': double.tryParse(read('px')) ?? double.nan,
      '2': double.tryParse(read('p2')) ?? double.nan,
    };
    final outcome = read('actual');
    final over = read('actual_over25');
    final goal = read('actual_goal');
    final pOver = double.tryParse(read('p_over25'));
    final pGoal = double.tryParse(read('p_goal'));
    if (id == null || id <= 0 || h == null || a == null ||
        !h.isFinite || !a.isFinite || h <= 0 || a <= 0 || h > 6 || a > 6 ||
        !['1', 'X', '2'].contains(outcome) ||
        !['true', 'false'].contains(over) ||
        !['true', 'false'].contains(goal) ||
        pOver == null || pGoal == null || !pOver.isFinite || !pGoal.isFinite ||
        pOver < 0 || pOver > 1 || pGoal < 0 || pGoal > 1 ||
        original.values.any((x) => !x.isFinite || x < 0 || x > 1)) {
      excluded++;
      continue;
    }

    final replay = engine.simulate(
      fixtureId: id,
      expectedHomeGoals: h,
      expectedAwayGoals: a,
      simulations: 5000,
    );
    final result = replay.probabilities;
    originalOneXTwo += _brier1x2(original, outcome);
    replayOneXTwo += _brier1x2(result, outcome);
    originalOver += _brier(pOver, over == 'true');
    replayOver += _brier(result['OVER 2.5']!, over == 'true');
    originalGoal += _brier(pGoal, goal == 'true');
    replayGoal += _brier(result['GOAL']!, goal == 'true');
    valid++;
  }
  if (valid == 0) throw StateError('Nessuna riga valutabile');
  String avg(double sum) => (sum / valid).toStringAsFixed(5);
  print('B54 RETROSPETTIVO — NON PROSPETTICO / NON PRODUZIONE');
  print('Partite archiviate valutabili: $valid; escluse: $excluded');
  print('Brier 1X2 originale: ${avg(originalOneXTwo)}');
  print('Brier 1X2 replay:    ${avg(replayOneXTwo)}');
  print('Brier Over2.5 originale: ${avg(originalOver)}');
  print('Brier Over2.5 replay:    ${avg(replayOver)}');
  print('Brier GOAL originale: ${avg(originalGoal)}');
  print('Brier GOAL replay:    ${avg(replayGoal)}');
  print('Il replay è Poisson temporale: una differenza sul campione può '
      'essere casuale. I dati di questo CSV non dimostrano congelamento '
      'prepartita e non autorizzano l’uso nelle schedine.');
}
