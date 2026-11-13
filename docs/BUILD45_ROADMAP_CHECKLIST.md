# SmartBet AI / GoalVdLine — Roadmap concordata per Build 45

Aggiornamento: 12 novembre 2026. Riferimento: feature/b45-p20-4-multiday, PR #1 draft verso staging/b45-render-linux.

**Vincolo di rilascio:** una sola Build 45 su TestFlight quando tutte le voci release-critical sono verificate. Non modificare silenziosamente i limiti delle funzioni manuali e non attivare worker, notifiche, sincronizzazioni o apprendimento centralizzato senza consenso/gate previsti. Non unire questa PR nella staging usata da Render prima del collaudo specifico.

## Segnalazioni TestFlight Build 46 — 13/11/2026

- [ ] **Modifica 1 / priorità alta:** le schedine **su richiesta** devono continuare a essere elaborate sul server anche se l'iPhone va in background, viene bloccato o l'app si chiude. Riutilizzare **prima** Render/Flutter già pagati e Neon solo dopo verifica, con richiesta autenticata, job persistente, stato e recupero su iPhone, notifica solo a READY. Nessun servizio aggiuntivo o flag AutoSchedina giornaliera abilitato automaticamente.
- [ ] **Modifica 2 / priorità alta:** il pronostico AI con probabilità sportiva maggiore deve apparire sempre per primo, anche con quota reale <1,20 o N/D; subito sotto, quando disponibile, la migliore alternativa con quota reale >=1,20 che supera soglia e Auditor. Se Sisal non offre quote, usare fonte bookmaker verificata alternativa con nome esatto (mai etichettarla Sisal). Non inventare quote né forzare schedine.
- [ ] **Modifica 3 / priorità alta:** Risultati GoalVdLine TOP 5 non deve sparire quando mancano quote Sisal. Classificare i forecast sportivi con qualità, mostrare il migliore e un'alternativa realmente quotata >=1,20 quando disponibile. Distinguere quota mancante da analisi insufficiente.
- [ ] **Modifica 4 / priorità alta:** confronto Diego AI / SmartBet da eseguire anche sui pronostici sportivi non quotati, con deduplicazione e controllo costi. Attualmente Diego viene richiamato solo dopo la selezione con quota, quindi appare assente quando i risultati sono vuoti.
- [~] **X Premium:** visualizza simulazioni senza quota e senza Diego; negli screenshot le X ~25–31% sono sotto soglia e alcune hanno qualità dati N/D. Nessuna modifica automatica della logica, da monitorare.
- [ ] Altri bug del collaudo: numerare dal punto 5 in avanti.
- Registro dedicato: [`docs/BUILD46_TESTFLIGHT_BUGS.md`](BUILD46_TESTFLIGHT_BUGS.md). La modifica 1 è **registrata, non ancora implementata**. Nessun deploy Render, Neon o TestFlight autorizzato dal solo registro.

Legenda:
- [x] Presente nel codice e testato nel perimetro indicato
- [ ] Da completare, correggere oppure collaudare; la sola presenza di codice non costituisce esito positivo
- [~] Funzione presente, ma verifica funzionale/end-to-end non conclusa

### Verifica Mac finale e correzione tap notifica (13/11/2026)
- [x] Commit `0449c23`, `flutter test --no-pub --reporter compact`: EXIT 0, 685 test superati + 3 skipped, 0 falliti.
- [x] Commit `0449c23`, `flutter build ios --no-codesign`: EXIT 0, Runner.app 24.3 MB, Xcode 41,9s; non ha pubblicato TestFlight.
- [x] Individuato limite reale dopo la suite: prima il tap della notifica locale `on_demand_coupon_ready` non apriva la schedina on-demand; le selezioni erano in memoria nella schermata di generazione.
- [x] Implementato senza backend aggiuntivo: snapshot testuale dell'ultimo sistema su richiesta nel dispositivo (`GoalVdLineReadyCouponLocalStore`), salvataggio prima della notifica, route iOS warm/cold tap alla schermata read-only locale, notifica con ID unico latest; aggiunti test unit e widget. I vecchi percorsi APNs AutoSchedina restano invariati e OFF.
- [x] **Nuovo gate Mac su commit `5c969a7` (13/11/2026)**: 5/5 test mirati superati, `EXIT TEST: 0`; `flutter build ios --no-codesign`: `EXIT IOS: 0`, Xcode 82,6 s, Runner.app 24,3 MB. Questi risultati certificano il codice e la compilazione, non il comportamento runtime della notifica.
- [ ] **Test dispositivo reale ancora necessario**: attivazione consenso, generazione su richiesta completata, banner in primo piano, tap e lettura dello snapshot locale dopo riapertura. Una build senza firma non è installabile direttamente: usare una build firmata con percorso già previsto (Xcode o singola Build 45 TestFlight) soltanto quando pronto il release gate.
- [ ] La vista da notifica è un riepilogo testuale locale dell'**ultima** schedina creata su richiesta, non l'intero editor interattivo; quote snapshot al momento della creazione. Richiesta eventuale UI completa dopo release.
### Preparazione Build 45 — revisione GitHub (13/11/2026)
- [x] `pubspec.yaml` preparato come `version: 1.2.4+45` su sola feature branch (commit `52309cd`); **non implica TestFlight già distribuita**.
- [x] Workflow iOS TestFlight predisposto anche per il futuro branch `release/b45-testflight` (commit `ced35bb`), con numero Build 45 fissato su tale branch. Nessuna modifica ai trigger delle branch storiche; nessuna esecuzione del workflow avviata da questa preparazione.
- [x] Release notes interne in `docs/BUILD45_RELEASE_NOTES.md`, con limiti funzionali dichiarati.
- [ ] Prima dell'unica Build 45 TestFlight: verifica quote Sisal e soglie di probabilità nelle schermate, poi **creazione deliberata del branch release**. Il collaudo su iPhone della notifica/snapshot si svolge **con quella stessa Build 45 firmata su TestFlight**, senza generare una build intermedia. Non fare merge PR #1 sullo staging Render.
- [ ] Pipeline GitHub TestFlight e certificati/segreti **non ancora collaudati** su questa revisione; una build senza firma non è un upload Apple.
### Audit quote e probabilità — correzione mirata Build 45 (13/11/2026)
- [x] Identificata incongruenza nel generatore comune delle tre schedine: `GoalVdLineThreeCouponSystem._valid` usava quota fissa **1.25** nonostante `GoalVdLineQuotePolicy.minimumOdd` fosse **1.20**. Corretto nel commit `c64bb62` adottando l'unica policy condivisa. Il 65% minimo non cambia.
- [x] Aggiunti due test regressione (commit `388451c`): CORE/alternative con quota 1.20 ammissibile; quote 1.19 e mercati 7–13% non possono generare false tre varianti.
- [x] **Mac, 13/11/2026, commit `dd09a3b`**: `flutter test --no-pub test/services/goalvdline_three_coupon_system_test.dart test/services/goalvdline_official_coupon_contract_test.dart` — **25/25 test superati, `EXIT TEST: 0`**. Correzione soglia quota minima condivisa 1.20 verificata nei test; resta da verificare la disponibilità reale delle quote Sisal e il collaudo iPhone.
- [x] **Mac, 13/11/2026, commit `a4954ea`**: compilazione finale `flutter build ios --no-codesign`: **`EXIT IOS: 0`**, Xcode 80,3 s, `Runner.app` 24,3 MB; include correzione quote 1.20 e i 25 test mirati eseguiti separatamente. Non è una build firmata né caricata su TestFlight.
- [ ] **Distribuzione Build 45**: il branch di rilascio `release/b45-testflight` va creato solo con autorizzazione di pubblicazione; il push su tale branch avvia il workflow che firma e carica su App Store Connect. Dopo il caricamento, testare sul dispositivo la notifica locale e la consultazione dell'ultima schedina; mantenere l'AutoSchedina server OFF.

- [ ] La presenza di Sisal nel feed reale del giorno è ancora da confermare: assenza quote deve risultare N/D, mai quote sintetiche. In Combinazioni AI l'opzione esplicita 'Qualsiasi' può togliere il filtro minimo solo su richiesta utente, e non va cambiata silenziosamente.
### Riscontro TestFlight 1.2.5 (45) — 13/11/2026, NON PUBBLICARE SU STORE

- [x] Bug visibile negli screenshot utente: Combinazioni AI con SmartScore Qualsiasi e mercato X non genera risultati neppure con probabilità Qualsiasi. Con >=65% un messaggio attribuisce genericamente l'assenza alla probabilità. Anche Crea Sistema fallisce per portfolio insufficiente.
- [x] Audit: SisalOddsService richiede bookmaker Sisal esplicito, OddsService prima memorizzava senza scadenza il miss Sisal, ed entrambe le schermate nascondevano i pronostici quando non c'era quota Sisal. Copertura Sisal in feed non ancora confermata su fixture reali.
- [x] Correzioni isolate su branch fix/b45-noquote-preview (dalla release 1.2.5+45): anteprima sportiva read-only quando schedina vuota, mai in condivisione, nessuna quota inventata e nessuna modifica alle soglie delle selezioni giocabili.
- [x] Messaggi distinti fra quote Sisal mancanti e filtri/auditor; cache negativa 10 minuti, positiva 30 minuti; test per recupero quotazioni.
- [ ] GATE QA: flutter analyze --no-pub --no-fatal-infos e flutter test --no-pub test/services/sisal_odds_service_coverage_test.dart; poi collaudo UI dispositivo.
- [ ] Non approvare per App Store TestFlight 1.2.5 (45) prima della correzione collaudata e di una nuova build firmata. Release branch invariato, nessun nuovo upload automatico.

## SCOPE DI RILASCIO RAPIDO BUILD 45 — 13/11/2026

**Decisione dell'utente: velocizzare senza nuovi costi fissi.** Conservare tutto il codice; rinviato NON significa collaudato.

**Build 45 attuale, su richiesta nell'app:** pronostici AI e combinazioni, forecast separato dalla quota Sisal, soglia sportiva e blocco selezioni 7–13%, gestione assenza quota reale, notifica locale iOS solo a schedina pronta con consenso, contatore Home delle partite future di oggi (candidate, non già pronosticate), preferiti/filtri/condivisione senza regressioni.

**RINVIATO, NON BLOCCANTE per questa Build 45:** AutoSchedina giornaliera lato server, APNs dell'AutoSchedina remota, worker Render, e2e Neon→official Render→READY per auto-generazione, nuovo sito web. Codice conservato e flag OFF. Non fare merge verso staging/produzione e non attivare servizi a pagamento.

**Gate essenziali per una sola Build 45:**
- [ ] Una sola suite Flutter completa finale e controlli Node ancora necessari sulla branch corrente; non ripetere i test già passati senza modifiche rilevanti.
- [ ] Verifica mirata dei casi quote Sisal assenti/sotto 1.20, alternative probabilità inferiori al minimo e UI schedine/Combinazioni.
- [x] Build iOS senza firma riuscita prima dell'ultimo fix nativo (13/11: EXIT 0, Runner.app 24.3 MB).
- [ ] Ricompilare iOS dopo commit 7de226d, poi test dispositivo per notifiche locali reali, autorizzazioni e apertura/recupero schedina. Non promettere che un job locale prosegua dopo chiusura app.
- [ ] Solo al termine: unica Build 45 TestFlight, release notes e piano riduzione costo staging.

**Fix nativo inserito in 7de226d:** correzione di quattro Swift interpolation erroneamente escape doppio nei testi numerici e ID delle notifiche. QA su dispositivo ancora aperta.

---
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
- [x] **Mac, commit `6390f4a`**: test selettore P20.6, 10/10 superati, exit 0. I test non certificano disponibilità reale delle quote Sisal né il comportamento UI end-to-end.

### P20.3/P20.4 — Separazione `no_coupon` da errori di trasporto (13/11/2026)

- [x] Il runner ufficiale esistente restituisce HTTP 503 `{"error":"no_coupon"}` quando il job termina senza schedina valida. L'adapter riconosce **solo questa risposta minimale** dopo ticket/job autenticato sullo stesso host configurato.
- [x] Il coordinatore Neon distingue il risultato `no_coupon` da `provider_unavailable` e da `insufficient_events`, registrando un retry senza `coupon_json` e senza un finto READY. Payload ibridi `no_coupon` + schedina vengono rifiutati.
- [x] Test aggiunti in `auto_coupon_official_headless_runner.test.js` e `auto_coupon_generation_coordinator.test.js` per `no_coupon`, failure tecnica, sicurezza del payload e assenza di READY falso.
- [x] **Mac, commit `84a2c64` (13/11/2026)**: `node --test backend/test/auto_coupon_*.test.js` — 138/138 test passati, 0 falliti, 0 saltati, exit 0. Verificati anche i nuovi casi `no_coupon`/errore remoto; non equivale a un collaudo live Render/Neon.
- [ ] **Bloccante**: collaudo P20.4 sul container Linux isolato con Neon *staging*, READY persistito e letto da iPhone, deduplica/lease/retry, APNs dove consentito. Non usare Neon Primary né fare merge della PR draft verso staging Render senza verifica e gate.

### Preparazione collaudo P20.4 Render/Neon — stato GitHub (13/11/2026)
- PR [#1](https://github.com/michelebarberi-ai/smartbet-ai/pull/1) ancora DRAFT: `feature/b45-p20-4-multiday` → `staging/b45-render-linux`. Base staging invariata `2ee681c`; non è stata effettuata alcuna promozione/merge.
- Nessuna esecuzione GitHub Actions associata alla revisione `84a2c64` mostrata dalla ricerca; i risultati Mac forniti dall'utente sono la sola evidenza dei test per tale revisione.
- [ ] Verificare separatamente la disponibilità e la scadenza di Neon staging prima di collegare un worker (scadenza precedentemente annotata 17/11/2026). Conservare Primary completamente isolata.
- [ ] Individuare e verificare il container Linux P20.4 isolato, confrontare commit/schema/provider, quindi collaudo reale `coordinator → official engine → Neon READY → lettura iPhone`, inclusi casi `no_coupon`, retry, lease e sicurezza. Non dichiarare E2E concluso con i soli test mock.

### Decisione costi infrastrutturali (13/11/2026)
- **Vincolo utente: evitare nuovi costi fissi mensili**. Non creare/attivare il Background Worker Render a pagamento ($7/mese come mostrato nell'interfaccia del 13/11/2026) e non abilitare i suoi feature flag.
- La configurazione del worker esiste soltanto come opzione di sviluppo, non è stata distribuita. Render Flutter staging è alla revisione `2ee681c`; la feature branch recente non è ancora promossa. Neon `smartbet-b45-staging` è separato da production.
- [ ] Esaminare alternativa **senza nuovo costo fisso**: generazione locale on-demand in app oppure GitHub Actions schedulato con il vero motore ufficiale Flutter, scrittura autenticata a staging Neon e quote/API sotto controllo; verificare limiti e affidabilità del cron, protezione segreti, consumo CI ed eventuali costi variabili.
- [ ] Il runner GitHub non accede direttamente all'host privato Render `smartbet-b45-flutter-staging:8799`; non sostituire semplicemente l'URL senza riprogettare il trasporto. L'automazione giornaliera + APNs non è ancora garantita da nessuna alternativa proposta.
- [ ] Audit fatture e piani attivi Render, Neon, API sportive/quote e Apple Developer prima di ulteriori attivazioni a pagamento. Non interpretare il piano Free o il credito CI come promessa di costo totale nullo.

### Decisione di prodotto: notifiche schedina sì, AutoSchedina giornaliera rimandata (13/11/2026)

- **Obiettivo immediato**: mantenere la creazione di schedine su richiesta nell'app e notificare l'utente quando una schedina richiesta è pronta. Privilegiare completamento visibile in-app e, se utile, una notifica locale iOS con permesso esplicito; nessun worker sempre acceso necessario per il solo evento locale.
- **Rimandato**: generazione giornaliera autonoma sul server per tutti gli utenti, schedulazione remota, invio push di AutoSchedina e worker Render. Rivalutare dopo lancio del sito ufficiale e prime entrate.
- **Limite tecnico da esplicitare**: su iOS la continuazione di un calcolo dopo la chiusura dell'app non è garantita da una notifica locale; non promettere la notifica di un job remoto non eseguito. Se l'utente intendesse notifiche su risultati finali delle partite, serve progettare un servizio separato di verifica esiti.
- **Costi Render verificati da Billing**: smartbet-ai Starter 0.0097 USD/h (~6.98 USD/30 giorni); staging Flutter 1c-2g 0.0347 USD/h (~24.98 USD/30 giorni) più disco 0.0003 USD/(GB·h) (~0.22 USD/30 giorni per 1GB); addebiti parziali novembre 2.89+2.07=4.96 USD e proiezione Render novembre 23.90 USD. I valori 30gg sono simulazioni di 720 ore, non importi fatturati.
- [ ] **Prima di spegnere staging**: verificare che il runner non sia usato da altri servizi e che i dati persistenti siano preservati; decidere se sospendere/eliminare lo staging rispettando le regole e i costi di Render (disco incluso). Non toccare smartbet-ai e learning-api senza audit dipendenze.
- [x] Notifica locale su richiesta implementata con consenso separato: test Dart verificati su Mac (commit `fbe3231`, 11/11 mirati); **collaudo iPhone ancora aperto**. Non confondere con APNs dell'AutoSchedina remota.

### Build 45 — Notifica locale a fine schedina e riepilogo mattutino (13/11/2026)

- [x] Aggiunto un canale **locale iOS** `goalvdline/local_coupon_notifications` distinto dall'APNs dell'AutoSchedina server. L'utente può abilitare/disabilitare in Impostazioni > Notifiche schedina su richiesta; domanda consenso iOS, OFF di default, nessun worker o abbonamento aggiuntivo.
- [x] Nella creazione manuale/automatica su richiesta, a fine analisi riuscita l'app mostra un messaggio in primo piano e, solo se autorizzata, programma la notifica iOS. Nessun avviso "schedina pronta" per esito vuoto/errore.
- [x] Mostrato in Home al mattino un riepilogo del numero di fixture future con dati di calendario potenzialmente analizzabili, **riutilizzando** il numero già caricato da DashboardStore (nessuna richiesta API aggiuntiva). Distinto esplicitamente dai pronostici realmente qualificati dopo SmartCore, Auditor e filtri.
- [x] Aggiunti test Dart `test/services/goalvdline_coupon_ready_notifier_test.dart` (consenso, opt-out, assenza native handler, risultato vuoto, fallimento notifiche).
- [x] **Mac, commit `fbe3231` (13/11/2026)**: 11/11 test mirati superati, exit 0. `flutter analyze --no-pub --no-fatal-infos`: exit 0, 711 info, nessun `error •`/`warning •` nel log fornito. Non sono la suite Flutter completa né una build iOS.
- [x] **Compilazione iOS senza firma su Mac (13/11/2026)**: `flutter build ios --no-codesign` completata in 90,8 s, `build/ios/iphoneos/Runner.app` (24,3 MB), `EXIT BUILD IOS: 0`; NON distribuita a TestFlight.
- [ ] **Collaudo runtime su iPhone**: autorizzazione notifiche, completamento reale, banner in primo piano, comportamento a schermo bloccato/app in background, tap, compatibilità AppDelegate/FlutterImplicitEngine. L'app non garantisce l'esecuzione del calcolo dopo chiusura forzata.
- [x] Conteggio corretto per il giorno **locale effettivo**: `DashboardStore` interroga `MatchRepository.getMatchesByDate(now)` e `GoalVdLineDailyMatchCounter` scarta date diverse, iniziate, rinviate, anomalie e fixture duplicate; UI Home con azione di analisi e stato N/D distinto da 0. Prima `getTodayMatches()` restituiva le prossime fixture senza garanzia di giorno.
- [x] Notifica in primo piano: `AppDelegate` presenta un banner solo per `on_demand_coupon_ready`, senza modificare il tap delle push remote; rimosso il canale locale duplicato. Restano verifiche di compilazione iOS e permessi reali.
- [x] Nuovi test mirati: `test/services/goalvdline_daily_match_counter_test.dart` e `test/widgets/goalvdline_daily_matches_card_test.dart`, **eseguiti insieme al test notifica su Mac: 11/11 passati**.
- [ ] La notifica delle **quantità aggiornate alle 08:00 senza aprire l'app** richiederebbe un job remoto o un esecuzione background iOS non garantita; non mentire sui conteggi. Per ora il numero è aggiornato quando si apre/aggiorna la Home, non in un push mattutino con quantità calcolata automaticamente.
- [ ] Nessuna generazione autonoma quotidiana: il motore remoto e i job cron rimangono in pausa in attesa del sito e dei ricavi.
