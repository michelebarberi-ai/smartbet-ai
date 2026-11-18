# GoalVdLine — Build 70: weekend, shortlist sportiva e motori visibili

## Bug riprodotti il 18/11/2026

Con «Fine settimana», l'app caricava oggi + domani anziché sabato +
domenica. Gli screenshot riportavano 2.222 fixture, 328 con preanalisi,
36 approfondite, 0 quote valide, HTTP 503 su 19 richieste. La shortlist
di 36 si basava sulla *massima* probabilità di qualunque mercato,
compresi mercati «OPPURE» al 98–99%; il peso del campionato interveniva
solo dopo tutti gli altri spareggi.

L'opzione «Palinsesto Italia» veniva applicata al mercato quotato
solo alla fine, dopo avere già selezionato le 36 fixture per analisi
approfondita. Giovanili/riserve non selezionabili potevano quindi
occupare posti preziosi senza poter entrare nella schedina.

## Correzioni

- `_CouponPeriod.weekend` calcola il prossimo sabato e domenica:
  mercoledì 18/11/2026 => sabato 21/11 e domenica 22/11.
- Quando `Palinsesto Italia` è attivo, `ItalyScheduleFilter` si
  applica prima della preanalisi per non selezionare categorie già
  escluse dal filtro finale. Se l'opzione è disattivata il calendario
  globale rimane disponibile.
- La shortlist usa mercati sportivi ordinari confrontabili e non i
  mercati OR, più Score, qualità dati e peso competizione. Quote e
  bookmaker NON influenzano questa fase né le probabilità.
- I 36 slot di analisi approfondita vengono distribuiti
  inizialmente entro quattro fixture per campionato. Se sono
  insufficienti, la graduatoria originale riempie i posti rimanenti.
  Non vengono aggiunte partite sotto soglia o prezzi sintetici.
- Le altre stime AI non quotate mostrano anche il pannello espandibile
  «Analisi motori AI», con SmartBet, Diego N/D se necessario,
  simulatore e quarto Meta AI solo in SHADOW.
- Una vecchia registrazione SHADOW del Meta AI non è una conferma
  dell'analisi corrente se Diego è N/D.

## Limiti

Il 503 non è risolto da questa modifica: può dipendere da servizio,
proxy o provider. Gli screenshot non dimostrano che le quote non
esistano; il server ha restituito errori. È necessario verificare
i log Render del workspace autorizzato per risalire alla causa.
Nessuna modifica Render/Neon o nuovo piano a pagamento.

La presenza di quote internazionali con bookmaker noti in Italia
non equivale a disponibilità certificata nel sito italiano.
Il sistema mantiene soglia >1,20, probabilità minima selezionata,
consenso dati e separazione fra analisi AI e fattibilità bookmaker.

## Validazione e TestFlight

- QA: `.github/workflows/b70-unquoted-ai-panels-qa.yml`.
- Test: `test/services/goalvdline_coupon_screening_policy_test.dart`,
  `test/widgets/goalvdline_three_brains_expansion_test.dart`,
  `backend/test/b70_unquoted_analysis_contract.test.js` e
  `backend/test/b70_release_workflow_contract.test.js`.
- Il rilascio GitHub-only richiede `release/b70-testflight`,
  `version: 1.2.5+70` e commit di autorizzazione esatta
  `release(build70): authorize TestFlight upload` dopo full QA verde.
