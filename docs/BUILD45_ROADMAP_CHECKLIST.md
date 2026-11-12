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
