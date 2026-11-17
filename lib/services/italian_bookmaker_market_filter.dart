/// Indizio di disponibilità di una quota nel feed per un bookmaker
/// con marchio operante anche in Italia. NON certifica che il mercato
/// esista sul sito .it o nell'account del singolo utente.
/// Si usa soltanto DOPO l'analisi sportiva per il filtro finale.
class ItalianBookmakerMarketFilter {
  const ItalianBookmakerMarketFilter._();

  static const Set<String> _recognizedBrands = {
    'sisal', 'sisalit', 'snai', 'eurobet', 'lottomatica',
    'goldbet', 'better', 'planetwin365', 'bet365',
    'betfair', 'betano', 'bwin', 'betsson',
  };

  static bool appearsInItalianMarket(String bookmakerName) {
    final normalized = bookmakerName.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _recognizedBrands.contains(normalized);
  }
}
