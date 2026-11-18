# Build 71 — Calendario italiano, palinsesto Italia e gestione quote

## Riscontri reali del 18 novembre 2026

- Calendario personalizzato iPhone mostrava 'Nov 20 – Nov 20' e intestazioni
  dei giorni in inglese pur avendo l'app in italiano.
- Palinsesto Italia veniva inizialmente spento perché
  `GoalVdLineQuotePolicy.italianOnlyByDefault` era `false`.
- Prova TestFlight: 368 fixture, 168 pre-analisi valide, 36 analisi avanzate;
  19 richieste odds fallite tutte HTTP 503; 62 candidate non interrogate.
- Render: servizio reale `smartbet-ai-y6gw.onrender.com`, backend sul ramo
  `feature/api`. Log `FOOTBALL_UPSTREAM_DIAGNOSTIC` alle ore 18:09 e
  20:31 UTC con `FOOTBALL_PROVIDER_RATE_LIMIT` (HTTP 429, talvolta errori
  in JSON HTTP 200) e `FOOTBALL_PROVIDER_COOLDOWN` (proxy 503).
  La chiave del provider non risulta assente: il server arriva a tentare
  chiamate API-FOOTBALL. Le richieste senza quote non dimostrano che il
  mercato bookmaker non esista.

## Modifiche

1. `lib/app.dart`: locale italiana `it_IT`, delegati Material, Widgets e
   Cupertino da `flutter_localizations` SDK. Il calendario e il picker
   mostrano mesi e giorni italiani; picker con locale esplicita e ANNULLA.
2. `Palinsesto Italia` ora è **acceso di default**, resta disattivabile
   e continua a essere un filtro per marchi presenti in Italia, non una
   certificazione di disponibilità sul sito .it.
3. `Fine settimana` è etichettato chiaramente e resta fissato al prossimo
   sabato e domenica (correzione calendario B70).
4. `OddsService`: riconosce i codici backend non sensibili
   `FOOTBALL_PROVIDER_RATE_LIMIT` e `FOOTBALL_PROVIDER_COOLDOWN`, rispetta
   l'header `Retry-After` con pausa limitata e condivisa fra fixture,
   applica timeout client 18 s, e interrompe nuove HTTP durante la pausa.
   Differenzia `providerCooldownActive` dai normali 503 non quota e
   da errori configurazione. Una risposta negativa non crea un prezzo finto.
5. Diagnostica nella schedina: richieste HTTP effettivamente inviate
   separate da quelle evitate per cooldown. Il guard del blocco ripetuto
   interrompe anche gli esiti `providerCooldownActive`.
6. Le altre stime solo informative mostrano come prima proposta il miglior
   mercato **ordinario**, non sempre un mercato OR 98-99%. Mercati OR rimangono
   consultabili nel pannello motori e non sono cancellati dal modello.

## Confini e verifiche

- Il limite API reale non si può eliminare con codice del telefono:
  se i crediti o le richieste del provider restano esauriti, non sono
  disponibili nuove quote verificate. Non si aggirano limiti di piano.
- Nessuna modifica ai server Render, a Neon, a segreti o a piani a pagamento.
  Non sono inventate quote; soglia giocabile >1,20 e limiti sportivi scelti
  dall'utente non cambiano.
- CI GitHub: `.github/workflows/b71-calendar-odds-qa.yml`. Test backend,
  Flutter analyze, localizzazioni calendario, timeout/backoff provider,
  guard, screening weekend/Italia, regressione completa.
- Rilascio iOS solo da GitHub su `release/b71-testflight`, versione
  `1.2.5+71` con commit esplicito
  `release(build71): authorize TestFlight upload`, tutti i test prima
  della firma.
