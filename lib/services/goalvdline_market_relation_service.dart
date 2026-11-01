enum GoalVdLineMarketRelationKind {
  same,
  compatible,
  incompatible,
  unavailable,
}

class GoalVdLineMarketRelation {
  final GoalVdLineMarketRelationKind kind;
  final String title;
  final String explanation;

  const GoalVdLineMarketRelation(this.kind, this.title, this.explanation);
}

/// Confronto logico fra condizioni di vincita full-time.
/// Non modifica probabilità, quote, Auditor o selezioni AI.
class GoalVdLineMarketRelationService {
  const GoalVdLineMarketRelationService._();

  static String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('BTTS YES', 'GOAL')
        .replaceAll('BTTS NO', 'NO GOAL')
        .replaceAll('NOGOAL', 'NO GOAL');
  }

  /// Etichetta utente: la chiave originale resta invariata per quote e logica.
  static String displayMarket(String market) {
    final normalized = _normalize(market);
    final handicap = RegExp(
      r'^HCP EURO CASA ([+-]?[0-9]+) ([1X2])$',
    ).firstMatch(normalized);
    if (handicap == null) return market;
    return 'HANDICAP EUROPEO · CASA ${handicap.group(1)} '
        '· ESITO ${handicap.group(2)}';
  }

  static bool Function(int, int)? _condition(String market) {
    switch (market) {
      case '1':
        return (h, a) => h > a;
      case 'X':
        return (h, a) => h == a;
      case '2':
        return (h, a) => h < a;
      case '1X':
        return (h, a) => h >= a;
      case 'X2':
        return (h, a) => h <= a;
      case '12':
        return (h, a) => h != a;
      case 'GOAL':
        return (h, a) => h > 0 && a > 0;
      case 'NO GOAL':
        return (h, a) => h == 0 || a == 0;
      case 'CASA SEGNA':
        return (h, a) => h > 0;
      case 'OSPITE SEGNA':
        return (h, a) => a > 0;
      case 'CASA 2+ GOL':
        return (h, a) => h >= 2;
      case 'OSPITE 2+ GOL':
        return (h, a) => a >= 2;
      case 'CASA 3+ GOL':
        return (h, a) => h >= 3;
      case 'OSPITE 3+ GOL':
        return (h, a) => a >= 3;
      case 'GOAL + O2.5':
        return (h, a) => h > 0 && a > 0 && h + a >= 3;
      case 'NO GOAL + U2.5':
        return (h, a) => (h == 0 || a == 0) && h + a <= 2;
    }

    final totals = RegExp(r'^(OVER|UNDER) ([0-9]+)\.5$').firstMatch(market);

    if (totals != null) {
      final line = int.parse(totals.group(2)!);

      if (line >= 1 && line <= 4) {
        return totals.group(1) == 'OVER'
            ? (h, a) => h + a > line
            : (h, a) => h + a <= line;
      }
    }

    final handicap = RegExp(
      r'^HCP EURO CASA ([+-]?[0-9]+) ([1X2])$',
    ).firstMatch(market);

    if (handicap != null) {
      final line = int.parse(handicap.group(1)!);

      if (line < -5 || line > 5) return null;

      switch (handicap.group(2)!) {
        case '1':
          return (h, a) => h + line > a;
        case 'X':
          return (h, a) => h + line == a;
        case '2':
          return (h, a) => h + line < a;
      }
    }

    // Mercati che richiedono cronologia degli eventi
    // oppure regole non modellate: nessuna conclusione.
    return null;
  }

  static GoalVdLineMarketRelation compare({
    required String? goalVdLineMarket,
    required String? diegoMarket,
  }) {
    final first = _normalize(goalVdLineMarket);
    final second = _normalize(diegoMarket);

    if (first.isEmpty || second.isEmpty || first == 'N/D' || second == 'N/D') {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.unavailable,
        'NON DETERMINABILE',
        'Manca almeno una selezione confrontabile.',
      );
    }

    if (first == second) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.same,
        'STESSO MERCATO',
        'Le due AI indicano lo stesso evento. '
            'Le probabilità possono comunque essere differenti.',
      );
    }

    final firstCondition = _condition(first);
    final secondCondition = _condition(second);

    if (firstCondition == null || secondCondition == null) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.unavailable,
        'RELAZIONE NON DETERMINABILE',
        'I mercati sono differenti, ma almeno uno richiede '
            'regole non ancora supportate dal confronto logico.',
      );
    }

    var firstPossible = false;
    var secondPossible = false;
    var both = false;
    var firstOnly = false;
    var secondOnly = false;
    String? sharedExample;

    // Enumerazione deterministica degli esiti full-time.
    // Tutti i mercati qui supportati hanno soglie <= 5 gol.
    for (var home = 0; home <= 12; home++) {
      for (var away = 0; away <= 12; away++) {
        final a = firstCondition(home, away);
        final b = secondCondition(home, away);

        if (a) firstPossible = true;
        if (b) secondPossible = true;

        if (a && b) {
          both = true;
          sharedExample ??= '$home-$away';
        } else if (a) {
          firstOnly = true;
        } else if (b) {
          secondOnly = true;
        }
      }
    }

    if (!firstPossible || !secondPossible) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.unavailable,
        'RELAZIONE NON DETERMINABILE',
        'Non è possibile valutare entrambe le selezioni '
            'con le regole disponibili.',
      );
    }

    if (!both) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.incompatible,
        'INCOMPATIBILI',
        'Non possono risultare entrambe vincenti '
            'sullo stesso risultato finale.',
      );
    }

    if (!firstOnly && !secondOnly) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.same,
        'CONDIZIONI EQUIVALENTI',
        'Le due selezioni hanno condizioni di vincita equivalenti, '
            'pur utilizzando nomi differenti.',
      );
    }

    if (!firstOnly) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.compatible,
        'GOALVDLINE IMPLICA DIEGO',
        'Quando vince la selezione GoalVdLine, '
            'vince anche quella di Diego. Non vale necessariamente il contrario.',
      );
    }

    if (!secondOnly) {
      return const GoalVdLineMarketRelation(
        GoalVdLineMarketRelationKind.compatible,
        'DIEGO IMPLICA GOALVDLINE',
        'Quando vince la selezione Diego, '
            'vince anche quella GoalVdLine. Non vale necessariamente il contrario.',
      );
    }

    return GoalVdLineMarketRelation(
      GoalVdLineMarketRelationKind.compatible,
      'COMPATIBILI',
      'Possono risultare entrambe vincenti, '
          'ad esempio con $sharedExample. '
          'Tuttavia una può vincere mentre l’altra perde.',
    );
  }
}
