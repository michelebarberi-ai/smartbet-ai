enum SmartBetAnalysisSettlement { correct, wrong, unsupported }

class SmartBetAnalysisMarketSettlement {
  const SmartBetAnalysisMarketSettlement._();

  static SmartBetAnalysisSettlement evaluate({
    required String market,
    required int homeGoals,
    required int awayGoals,
  }) {
    if (homeGoals < 0 || awayGoals < 0) {
      return SmartBetAnalysisSettlement.unsupported;
    }

    final normalized = _normalize(market);

    if (normalized.isEmpty ||
        normalized == 'N/D' ||
        normalized == 'COMBO CHANCE') {
      return SmartBetAnalysisSettlement.unsupported;
    }

    // ============================================================
    // COMBO
    // Esempi:
    // 1X + O1.5
    // X2 + OVER 1.5
    //
    // Usiamo " + " come separatore per non spezzare CASA 2+ GOL.
    // ============================================================

    final comboParts = normalized.split(RegExp(r'\s+\+\s+'));

    if (comboParts.length > 1) {
      var hasUnsupported = false;

      for (final rawPart in comboParts) {
        final part = _expandComboToken(rawPart);

        final result = evaluate(
          market: part,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
        );

        if (result == SmartBetAnalysisSettlement.wrong) {
          return SmartBetAnalysisSettlement.wrong;
        }

        if (result == SmartBetAnalysisSettlement.unsupported) {
          hasUnsupported = true;
        }
      }

      return hasUnsupported
          ? SmartBetAnalysisSettlement.unsupported
          : SmartBetAnalysisSettlement.correct;
    }

    final totalGoals = homeGoals + awayGoals;

    // ============================================================
    // 1X2
    // ============================================================

    switch (normalized) {
      case '1':
        return _result(homeGoals > awayGoals);

      case 'X':
        return _result(homeGoals == awayGoals);

      case '2':
        return _result(awayGoals > homeGoals);

      case '1X':
        return _result(homeGoals >= awayGoals);

      case 'X2':
        return _result(awayGoals >= homeGoals);

      case '12':
        return _result(homeGoals != awayGoals);
    }

    // ============================================================
    // OVER / UNDER
    // ============================================================

    final goalsLine = RegExp(
      r'^(OVER|UNDER)\s+(\d+(?:\.\d+)?)$',
    ).firstMatch(normalized);

    if (goalsLine != null) {
      final type = goalsLine.group(1)!;
      final line = double.tryParse(goalsLine.group(2)!);

      if (line == null) {
        return SmartBetAnalysisSettlement.unsupported;
      }

      if (type == 'OVER') {
        return _result(totalGoals > line);
      }

      return _result(totalGoals < line);
    }

    // ============================================================
    // GOAL / NO GOAL
    // ============================================================

    switch (normalized) {
      case 'GOAL':
        return _result(homeGoals > 0 && awayGoals > 0);

      case 'NO GOAL':
        return _result(homeGoals == 0 || awayGoals == 0);
    }

    // ============================================================
    // TEAM GOALS
    // ============================================================

    switch (normalized) {
      case 'CASA SEGNA':
        return _result(homeGoals >= 1);

      case 'OSPITE SEGNA':
        return _result(awayGoals >= 1);

      case 'CASA 2+ GOL':
      case 'CASA ALMENO 2 GOL':
        return _result(homeGoals >= 2);

      case 'OSPITE 2+ GOL':
      case 'OSPITE ALMENO 2 GOL':
        return _result(awayGoals >= 2);

      case 'CASA 3+ GOL':
      case 'CASA ALMENO 3 GOL':
        return _result(homeGoals >= 3);

      case 'OSPITE 3+ GOL':
      case 'OSPITE ALMENO 3 GOL':
        return _result(awayGoals >= 3);

      // Il risultato finale da solo non permette di sapere
      // quale squadra abbia segnato il primo gol.
      case 'CASA SEGNA PRIMA':
      case 'OSPITE SEGNA PRIMA':
        return SmartBetAnalysisSettlement.unsupported;
    }

    // ============================================================
    // MULTIGOL
    // ============================================================

    final multigol = RegExp(r'^MULTIGOL\s+(\d+)-(\d+)$').firstMatch(normalized);

    if (multigol != null) {
      final minimum = int.tryParse(multigol.group(1)!);
      final maximum = int.tryParse(multigol.group(2)!);

      if (minimum == null || maximum == null || minimum > maximum) {
        return SmartBetAnalysisSettlement.unsupported;
      }

      return _result(totalGoals >= minimum && totalGoals <= maximum);
    }

    return SmartBetAnalysisSettlement.unsupported;
  }

  static SmartBetAnalysisSettlement _result(bool correct) {
    return correct
        ? SmartBetAnalysisSettlement.correct
        : SmartBetAnalysisSettlement.wrong;
  }

  static String _expandComboToken(String value) {
    final token = _normalize(value);

    final shortOver = RegExp(r'^O(\d+(?:\.\d+)?)$').firstMatch(token);

    if (shortOver != null) {
      return 'OVER ${shortOver.group(1)}';
    }

    final shortUnder = RegExp(r'^U(\d+(?:\.\d+)?)$').firstMatch(token);

    if (shortUnder != null) {
      return 'UNDER ${shortUnder.group(1)}';
    }

    return token;
  }

  static String _normalize(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
