# Build 69 — quote HTTP / scansione protetta / Auditor leggibile

## Osservazione reale, iPhone 18 novembre 2026

Build 68, `Crea Schedina GoalVdLine` con Equilibrato, >=65%,
15 eventi: 71 incontri nel periodo, 34 preanalisi e 34 analisi avanzate;
**34 interrogazioni quote, 34 errori**, 0 quote idonee e 0
veto Auditor. L'app NON ha dimostrato che nessuna partita fosse
quotata: sono falliti i contatti col servizio.

Nello stesso giorno, `Combinazioni` aveva trovato 8 selezioni
con prezzo nel feed internazionale. I percorsi non condividono
necessariamente gli stessi fixture/mercati/istanti; non trattarli
come una singola ricerca identica.

## Diagnosi e modifica

- `OddsService` chiama il proxy esistente
  `/football/odds?fixture=...` su `smartbet-ai-y6gw.onrender.com`.
- Il backend espone quella rotta e usa `FOOTBALL_API_KEY`
  per API-FOOTBALL. Il proxy può rispondere 503 con configurazione
  mancante, 502 per errore upstream, altri codici di accesso e
  risposte 200 con campo `errors`.
- Prima la diagnostica aggregava tutto in «errore del servizio».
  Adesso distingue:
  - HTTP (contatori 429/500/502/503...), anche con JSON non valido;
  - blocco/rate quota e errori provider;
  - configurazione proxy mancante (solo se il backend lo esplicita);
  - 401/403, rotta 404, rete, payload invalido;
  - quota non trovata reale e mercato non riconosciuto.
- Il backend non espone chiavi, credenziali o payload sensibili nel UI.
- La scansione quote del coupon è passata da 6 richieste parallele
  a **2**; `Combinazioni` effettua richieste sequenziali.
- Se uno o due batch consecutivi sono *interamente* in errore
  infrastrutturale, la scansione si interrompe per non sprecare
  richieste. Contiamo **quante partite non sono state interrogate**;
  non le classifichiamo come «senza quote».
- Una quota realmente mancante, un bookmaker non coperto o
  un mercato assente NON sono errori sistemici e non interrompono
  la ricerca.
- Mai generare quote false, abbassare 1.20, inventare mercati
  «OPPURE» o usare ranking storico come garanzia.

## Analisi fra i motori e Auditor

- L'Auditor locale che accetta le combinazioni finali è distinto
  dall'Auditor sportivo avanzato, che può risultare NON ESEGUITO.
- Una combinazione già localmente verificata è etichettata
  `QUOTE + AUDITOR LOCALE`, non la generica `PRE-ANALISI`.
- I dati delle due AI vengono confrontati a parità di mercato 1/X/2,
  quando entrambe le distribuzioni sono disponibili; le stime
  per «CASA SEGNA» non vengono scambiate con «1».
- I 94–98% dei mercati «OPPURE» sono stime su eventi molto ampi
  calcolate sulla distribuzione Poisson dei punteggi. Questo
  **non prova** una affidabilità storica pari a 94–98% e non
  assicura che il mercato esista nel feed di un bookmaker.

## Stato, limiti e controlli

- La causa backend REALE dei 34 errori non è verificabile
  esclusivamente dal codice e dagli screenshot: richiede
  HTTP status o i log Render del servizio corretto.
- La correzione client è utile per *identificare* la causa e
  ridurre i burst; non garantisce che API-Football offra
  oggi quote per le specifiche partite.
- Questa feature non migra Neon, non modifica Render,
  non acquista piani e non abilita Meta AI per le schedine.
- QA: `.github/workflows/b69-audit-clarity-qa.yml`.
- Test: `test/services/goalvdline_odds_lookup_diagnostics_test.dart`,
  `test/services/goalvdline_odds_scan_guard_test.dart`,
  `test/widgets/goalvdline_b69_audit_clarity_test.dart`.
- Solo GitHub TestFlight, con
  `release/b69-testflight`, `version: 1.2.5+69` e
  `release(build69): authorize TestFlight upload` dopo
  backend, Flutter analysis e regressione completa verdi.
