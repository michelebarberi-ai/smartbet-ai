# SmartBet AI / GoalVdLine — Roadmap concordata per Build 45

Aggiornamento: 12 novembre 2026. Riferimento: feature/b45-p20-4-multiday, PR #1 draft verso staging/b45-render-linux.

**Vincolo di rilascio:** una sola Build 45 su TestFlight quando tutte le voci release-critical sono verificate. Non modificare silenziosamente i limiti delle funzioni manuali e non attivare worker, notifiche, sincronizzazioni o apprendimento centralizzato senza consenso/gate previsti. Non unire questa PR nella staging usata da Render prima del collaudo specifico.

Legenda:
- [x] Presente nel codice e testato nel perimetro indicato
- [ ] Da completare, correggere oppure collaudare; la sola presenza di codice non costituisce esito positivo
- [~] Funzione presente, ma verifica funzionale/end-to-end non conclusa

## A. Motore AutoSchedina AI e integrazione (P0)

- [x] **P20.4 finestra oggi / oggi+domani / oggi+domani+dopodomani**: preferenze, raccolta fixture, verifiche Europe/Rome e 3 varianti. 145/145 test Node mirati; 642 Flutter globali superati (3 skipped), analisi statica exit 0 con 702 info/segnalazioni non bloccanti; collaudo reale Flutter READY: 3 varianti, 3 stesse fixture, 2 eventi 12/11 + 1 evento 14/11. Queste prove non certificano il sistema automatico remoto.
- [x] Tre varianti P20 con medesime fixture e mercati alternativi verificati; quote reali >= 1,25 e probabilità minima configurabile (default 65%) nel contratto ufficiale; 3–15 eventi richiesti nella AutoSchedina automatica.
- [~] P18/P20.3 headless Render Linux: host privato, autenticazione, job journal persistente e test manuali precedenti; manca end-to-end del nuovo codice P20.4 sul container Linux.
- [ ] Collaudo automatico **coordinatore Neon staging → official engine Render → READY persistito → lettura sul dispositivo**; verificare lease, deduplica e retry. Il vecchio test staging si fermava con `no_coupon`; il READY locale P20.4 non dimostra che questo collegamento sia riuscito.
- [ ] Gestione `no_coupon` separata da errore tecnico di trasporto; motivazioni minimali senza token, quote inventate o dati personali.
- [ ] Scheduler giornaliero reale e APNs: controllo gated, token, consenso, fusi orari, comportamento alla scadenza dei coupon, notifica una sola volta; test unitari esistono, ma attivazione end-to-end e configurazione di produzione non sono certificate.
- [ ] Test isolato del container Linux su feature P20.4 senza modificare il servizio Render esistente; non toccare Neon Primary.
- [ ] Verificare Neon staging branch e sua scadenza prevista 17 novembre 2026 (potrebbe richiedere nuova staging, mai sostituire Primary).

## B. Qualità pronostici e schedine (P0)

- [ ] Regression test e correzione delle selezioni al **7–13%** o di esiti «2» inseriti a causa di una quota sotto il minimo; rifiutare candidati con probabilità insufficiente invece di passare a esiti alternativi deboli.
- [ ] Coerenza fra probabilità del singolo **mercato**, SmartScore, affidabilità, rischio e quota effettiva; nessuna percentuale/calibrazione visualizzata come garanzia di successo.
- [~] CORE e 2–3 schedine alternative su fixture coordinate: strutture presenti in Schedina AI, Combinazioni AI e AutoSchedina; confrontare con screenshot e verificare che le scelte forti restino ferme mentre cambiano i mercati davvero incerti.
- [~] Combinazioni AI: fino a tre famiglie di mercati scelte assieme, con validazione filtri, ordini e assenza di duplicati; codice multimercato già presente, QA schermata ancora aperto.
- [ ] Mercati combinati richiesti: «Goal O Over», «1X O Over», «X O Over», «1 O Over», «X O Under», «2 O Under», «1X O Under». Verificare supporto effettivo nei dati quote/auditor e non sintetizzare quote o probabilità per mercati non quotati.
- [~] Handicap europeo/asiatico, Over/Under, Goal/No Goal e altri mercati estesi presenti in vari servizi; completare matrice disponibile per Schedina AI/Combinazioni AI e test con quote reali.
- [ ] Controllare flussi Risultati esatti, X Premium, marcatori e ranking multimercato (filtri, output, soglie, partite scartate), inclusa esclusione inaspettata di SmartScore maggiori di 70.

## C. Cervello AI e affidabilità reale (P0)

- [ ] **Affidabilità empirica per campionato E mercato**: percentuale successi su pronostici risolti, numerosità campione, intervallo di confidenza/indisponibilità per campioni piccoli, calibrazione e confronti nel tempo. Distinguere successo storico da probabilità stimata e da SmartScore.
- [ ] Il cervello deve imparare automaticamente quali campionati/mercati funzionano meglio e utilizzare un peso calibrato nella generazione; prima in **SHADOW**, con gating e protezioni contro sovradattamento e campioni insufficienti. Non presentare l'obiettivo 80% come risultato acquisito.
- [~] Apprendimento locale, storico, calibrazione e test presenti nel repository. Verificare esplicitamente che la correzione applicata derivi dai risultati reali e che i pronostici originali rimangano nello storico per training/audit.
- [~] Apprendimento centrale Render/Neon, consenso, token mobile, coda e trasferimento storico già presenti in parte; da verificare sincronizzazione automatica consensuale, progressione, deduplica, storico iPhone pregresso e risoluzione risultati, senza alterare dati locali.
- [ ] Dashboard e monitor: affidabilità per campionato/mercato, correzioni SHADOW vs ACTIVE, campioni e motivazione di inclusione/esclusione.

## D. UI e flussi applicazione (P1, necessari prima della Build 45)

- [~] Campionati preferiti persistenti presenti in `competition_filter_sheet.dart`, con test; verificare in tutte le schermate interessate.
- [~] Ordinamento per paesi/campionati in `goalvdline_competition_order.dart`; verificare ordinamento omogeneo in Ranking Multimercato, X Premium, Risultati GoalVdLine, Analisi Partite e Live AI.
- [~] Condivisione schedina presente nel codice Schedina e Combinazioni AI; testare il bottone e il testo esportato sul dispositivo.
- [ ] Ordinamento cronologico effettivo degli incontri e conservazione delle selezioni fra schede e schermata finale.
- [ ] Home: menu espandibile delle statistiche/storico/apprendimento, chiuso per default, senza perdita dei collegamenti; collaudo UI.
- [ ] AutoSchedina AI su iPhone: scelta 1–3 giorni, 3–15 eventi, probabilità minima, ora, mercati, pulsanti e messaggi di stato; test end-to-end con risultato del server.

## E. Rilascio Build 45 (bloccante)

- [ ] Suites backend, Flutter, analisi statica e test UI completi sulla revisione finale; verificare i cambi con screenshot reali.
- [ ] Integrità e privacy: nessun segreto GitHub, nessun URL Render pubblico non autorizzato, nessun dato del dispositivo senza consenso; no merge verso produzione per errore.
- [ ] Collaudo staging dell'intero flusso (Node/Flutter/Render/Neon), push dove abilitato, recupero dati/retry, release notes, commit/PR, poi pipeline GitHub e una sola Build 45 TestFlight.
- [ ] Verificare che i test funzionali non dipendano da fixture del giorno «fortunate»; `no_coupon` è un esito lecito con filtri rigorosi.

## F. Dopo Build 45 (non blocca il rilascio)

- [ ] Sito web ufficiale GoalVdLine con pagina pubblica e area privata dashboard AI: definizione funzionale e rilascio separato, come concordato.

## Note e evidenze

- PR #1 è DRAFT; staging Render tuttora riferimento `staging/b45-render-linux` (commit base `2ee681c`).
- `feature/b45-p20-4-multiday` ospita P20.4 e relativi test. Nessuna attestazione di deployment produzione.
- Le voci [~] richiedono verifica UI/end-to-end prima di essere marcate [x]; le voci [ ] NON implicano necessariamente codice assente, ma accettazione non dimostrata.
- Ogni correzione va accompagnata da test di regressione; aggiornare questa checklist dopo i test, mantenendo un unico obiettivo Build 45.

## P20.6 — Decisione architetturale del 13/11/2026 (IN CORSO)

**Regola non negoziabile, valida per tutta l'app**: la previsione sportiva principale nasce da modello, dati, simulazioni, Auditor e calibrazione consentita. Si conserva immutata dopo l'analisi. Le quote NON entrano nella scelta del pronostico, nell'ordine delle previsioni o nel punteggio di affidabilita'.

**Quote**: soltanto SISAL, minimo **1.20** incluso, consultate dopo ranking. Un bookmaker diverso o una quota Sisal assente non sono sostituiti. L'eventuale mercato alternativo quotato >=1.20 rimane distinto dal forecast originale e deve rispettare il filtro sportivo configurato (default 65%, evitare esiti deboli 7–13%). Se non esiste alternativa sportivamente valida, nessun mercato viene inventato.

**Stato**: codice base introdotto su feature, NON ancora validato dalla suite Mac o da staging. `GoalVdLineQuotePolicy` e `SisalOddsService` sono i confini di prezzo; `SmartBetSportsMarketSelector.recommend` restituisce forecast principale e couponPick separato; Schedina AI, Combinazioni AI, Coupon e Risultati GoalVdLine espongono la distinzione quando un'alternativa viene prodotta. Test mirati aggiunti/aggiornati. La vecchia P20.5 basata sulla selezione quotata non è il contratto prodotto approvato.

**Ancora da verificare/chiudere prima del rilascio:**
- [ ] Flutter/Node suite completa, test provider Sisal reale: verifica copertura per mercati, leghe e fixture (non assumere che Sisal sia nel feed); se assente, mostrare N/D senza quote di terzi.
- [ ] Copertura UI delle previsioni con Sisal **assente** o sotto 1.20 anche quando NESSUN mercato è giocabile: mostrare il pronostico sportivo senza creare schedine false.
- [ ] AutoSchedina remota: preservare nel payload i metadati del forecast principale per mostrare distintamente le alternative sul dispositivo; mantenere serializzazione privacy-safe, firma e validazione lato Node.
- [ ] Audit di ogni schermata e servizio secondario che mostra quote (ranking/Live/risultati esatti/analisi), distinguendo forecast sportivo, probabilita stimata e disponibilita Sisal.
- [ ] Valutare le condizioni di fornitura quote Sisal, i limiti API e l'eventuale servizio dedicato.
- [ ] Verificare che classifiche e ordini non cambino quando cambia solo la quota Sisal (test metamorfici).

Non portare il PR draft in staging/Render prima che i test siano verdi e il vincolo forecast-first sia rispettato anche senza quote.

## P21W — Affidabilità osservata per campionato × mercato (13/11/2026)

- [x] Aggiunto un **servizio in sola lettura** (`smartbet_league_market_reliability_service.dart`) che raggruppa solo pronostici prospettici realmente risolti per paese, campionato, mercato e motore. Non legge quote e non cambia pronostici o schedine.
- [x] Deduplica fixture/mercato/motore, esclude conflitti e dati non noti al momento del report (anti look-ahead).
- [x] Riporta successi osservati, campioni, giornate distinte, probabilità media originaria, gap di calibrazione e Brier Score; aggiunge intervallo Wilson al 95% e stati insufficient / exploratory / signal / strongShadowCandidate (solo suggerimento sperimentale).
- [x] **Mac verificato**: P21W test motore/widget e suite Flutter completati su commit `f37f1d5` (670 superati, 3 saltati, exit 0); analisi exit 0 con `--no-fatal-infos` e 711 segnalazioni. Sono ancora da verificare sul dispositivo i dati reali.
- [ ] UI dashboard locale e conteggi effettivi iPhone: ancora aperti. Il report non contiene dati del dispositivo finché non viene interrogato il suo archivio tramite un flusso di consenso.
- [ ] Solo dopo verifica prospettica SHADOW e gate espliciti valutare come usare queste statistiche nel ranking automatico; **nessun cambiamento automatico al motore adesso**.

### Collaudo precedente P20.6 — commit 34b0f92 (Mac, 13/11/2026)
- Backend: 134 test passati, 0 falliti, exit 0 (`backend/test/auto_coupon_*.test.js`).
- Flutter: 651 superati, 3 saltati, exit 0 (`flutter test --no-pub`).
- Analisi: exit 0 con `--no-fatal-infos`, 706 segnalazioni non bloccanti riportate. L'output condiviso non mostra errori/warning.
- ZIP sorgenti creato e verificato in `~/Downloads`, commit 34b0f92, circa 3,9 MB. È uno snapshot precedente alla P21W.
- Questa evidenza non prova disponibilità live delle quote Sisal né la riuscita end-to-end su Render/Neon.

### P21W — risultati verificati e UI (13/11/2026)
- [x] **Mac, commit 923df91:** 7/7 test del motore P21W superati, `flutter analyze --no-pub --no-fatal-infos` exit 0, 711 segnalazioni non bloccanti (nessun error/warning nell'output filtrato).
- [x] **Nuovi commit di sviluppo:** pannello read-only campionato × mercato integrato sia in `Intelligenza e apprendimento` sia nel `Learning Monitor`, che è raggiungibile direttamente dalla Home > STATISTICHE E IA. Due widget test dedicati (stato senza dati e campione insufficiente).
- [x] **Verifica UI Mac**: test widget P21W e P21W.4 inclusi nella suite Flutter verde; analisi statica exit 0 sulla revisione UI.
- [ ] Verificare sul dispositivo reale campioni, intervalli, cronologia e assenza di riscritture di preferenze; nessuna raccolta o sincronizzazione di dati aggiuntivi è stata abilitata.
- [ ] Full suite Flutter e Node alla revisione finale della Build 45, senza pubblicazione anticipata.


## P21W.4 — Replay prospettico SHADOW campionato × mercato (13/11/2026)

- [x] Implementato `smartbet_league_market_shadow_service.dart`: replay locale di confronto tra Brier originale e Brier corretto; correzione shrinkage con massimo ±10 punti percentuali, dopo almeno 50 esiti precedenti.
- [x] Ogni pronostico viene confrontato solo con risultati già conosciuti **prima** del suo `firstSeenAt`, mai con risultati futuri; dati partizione per motore/paese/campionato/mercato, deduplica, esclusione conflitti, esiti non verificabili e mercati non liquidabili.
- [x] Pannello P21W integrato in `Intelligenza e apprendimento` e `Learning Monitor` con Brier originale/SHADOW, campione di validazione e messaggi di dati insufficienti. Non modifica forecast, quote, ordinamenti, schedine, storage o server.
- [x] Aggiunti test mirati `smartbet_league_market_shadow_service_test.dart` e un widget test P21W.4; `warrantsFurtherResearch` segnala soltanto ricerca esplorativa, **non autorizza promozione/ACTIVE**.
- [x] **Mac, commit `f37f1d5` (13/11/2026)**: suite Flutter completa 670 test superati e 3 saltati, exit 0; `flutter analyze --no-pub --no-fatal-infos` exit 0, 711 segnalazioni; nessuna riga error/warning nell'output filtrato mostrato. Questi risultati NON equivalgono a un collaudo con storico reale iPhone o allo staging Render/Neon.
- [ ] Validare su archivio reale iPhone; poi solo eventuale ricerca su campioni futuri indipendenti e gate espliciti. Nessun deployment Render/Neon e nessuna Build TestFlight autorizzati da questa modifica.

### Stato verifiche al 13/11/2026
- Test backend auto_coupon: 134/134 superati sulla precedente revisione `0d4973f`; ripetere sul commit finale prima del rilascio.
- PR #1 resta **draft** verso `staging/b45-render-linux`; non eseguire merge o deploy senza collaudo integrato.
- Prossima priorità release-critical: P20.6 con test su assenza quote Sisal, forecast originale conservato, nessun coupon inventato; poi Render/Neon staging e iPhone.

### P20.6 — Regressioni forecast-first aggiunte (13/11/2026)
- [x] Aggiunti test in `test/services/smartbet_sports_market_selector_test.dart`: Sisal assente, quota principale sotto 1.20, alternativa almeno al 65%, protezione contro esiti 7–13% e invariabilità del ranking al cambiare delle sole quote.
- [ ] Eseguire nuovi test sul Mac (commit `6757a87`); il codice del selettore non è stato modificato. Questi test non certificano la disponibilità commerciale/reale delle quote Sisal né la UI end-to-end.
