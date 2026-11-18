# Build 68 — Quote reali: diagnosi errori, senza quote inventate

## Motivazione: test iPhone 18/11/2026

Build 67 ha mostrato 86 partite, 79 pre-analisi, 36 analisi
approfondite, 0 selezioni con quota idonea e 0 blocchi Auditor.
Un mercato combinato `1X O OVER 1.5` era stimato al 98% senza
quota confermata, e Diego AI era N/D perché il provider non aveva
dati storici sufficienti.

**Una previsione sportiva, anche al 98%, non equivale a un mercato
reale acquistabile.**

## Correzione

La Build 68 mantiene le quote da più bookmaker, minime **>1.20**,
e non modifica AI, mercati o ranking. Misura per ogni fixture interrogata:
- richiesta senza righe `response` dal provider;
- risposta con zero bookmaker;
- eventuale filtro Italia senza marchio eleggibile;
- bookmaker trovati, ma nessun mercato riconosciuto;
- mercati reali parsati con / senza prezzo superiore a 1.20;
- errore HTTP, risposta corrotta, errore del provider, timeout;
- eventuale messaggio di limite/rate quota API.

I contatori compaiono sotto «DIAGNOSTICA RICERCA» e la spiegazione
quando manca un portfolio distingue **assenza di quote** da **errore
di interrogazione**. La conta «Blocchi Auditor» viene aggiornata
anche se nessun portfolio può essere costruito.

Le diagnosi sono locali, non contengono token, nomi o dati personali,
non provocano richieste extra e non cambiano puntate o probabilità.

## Limiti noti

- I test automatici dimostrano che i casi sono distinti, NON che oggi
  il feed API-FOOTBALL pubblica prezzi per quelle specifiche partite.
- 86 partite in calendario ≠ 86 partite con mercato quotato.
- API-Football può non fornire odds per competizioni piccole e lontane,
  e in caso di quota API esaurita il client deve segnalare l'errore.
- Una linea OPPURE teorica è selezionabile nella schedina soltanto
  se il feed pubblica esplicitamente quel mercato e prezzo.
- «Diego N/D» non è causato dalla mancanza di quota; sono necessari
  dati statistici indipendenti sufficienti.
- Non inviare pronostici fittizi, non simulare prezzi, non abbassare
  soglia minima di mercato o quota per riempire una schedina.
- Un'eventuale seconda fonte reale di quote e la selezione
  automatica di leghe con copertura confermata richiedono
  ulteriore integrazione e verifica delle condizioni del provider.

## Test, rilascio e costi

GitHub-only TestFlight su `release/b68-testflight` con
`version: 1.2.5+68` e messaggio esatto
`release(build68): authorize TestFlight upload`.
Backend, Flutter analyze e full Flutter tests prima della firma.
Nessun Render/Neon deploy, nessuna nuova spesa o piano a pagamento.

- QA: `.github/workflows/b68-odds-diagnostics-qa.yml`
- Regression tests: `test/services/goalvdline_odds_lookup_diagnostics_test.dart`
- Backend release protection:
  `backend/test/b68_release_workflow_contract.test.js`
