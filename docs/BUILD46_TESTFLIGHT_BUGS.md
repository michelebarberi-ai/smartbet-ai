# GoalVdLine AI — Registro bug e modifiche dal collaudo TestFlight 1.2.5 (46)

Data prima segnalazione: 13/11/2026. Fonte: collaudo utente su iPhone. Stato: **aperto**, non implementato.

## 1. PRIORITÀ ALTA — Schedina su richiesta: elaborazione indipendente dall'iPhone

**Problema osservato:** l'utente segnala che la generazione della schedina sembra interrompersi o non progredire quando l'app passa in background o l'iPhone viene bloccato. La versione 1.2.5 (46) calcola la schedina su richiesta nell'app Flutter. iOS può sospendere le attività; una notifica locale dopo il completamento non garantisce il proseguimento dei calcoli.

**Modifica richiesta:** sfruttare **prima** l'infrastruttura Render già pagata (server smartbet-ai e servizio Flutter staging, con Neon dove opportuno) per eseguire *le schedine richieste esplicitamente dall'utente* su un host remoto. L'iPhone deve poter inviare la richiesta, uscire dall'app, riaprire la schermata e recuperare lo stato e i risultati. Nessun nuovo server o servizio a pagamento senza verifica dei costi e autorizzazione distinta.

**Criteri di accettazione e verifiche:**
- [ ] Confermare servizi Render realmente attivi, versioni, capienza, dipendenze e limiti; tariffe già registrate nella roadmap non provano che il motore sia ora in servizio.
- [ ] Riutilizzare il vero motore ufficiale SmartBet/GoalVdLine, senza duplicare in Node un secondo modello o inventare pronostici/quote; mantenere soglie e mercati coerenti con la generazione locale.
- [ ] Richiesta autenticata e idempotente; stato persistito `queued/running/ready/error` con recupero dopo riavvio e senza dati sensibili nel client o nei log.
- [ ] L'iPhone mostra avanzamento, errori espliciti e ultima schedina completata anche dopo blocco schermo e riapertura; evitare duplicazioni e risultati scaduti.
- [ ] Notifica di completamento **solo con consenso** e soltanto dopo reale READY; verificare APNs e tap da app chiusa su iPhone, non scambiare l'avviso locale con l'esecuzione background.
- [ ] Validazione end-to-end prima su ambiente isolato e senza attivare nuovi costi, quindi autorizzazione esplicita prima di produzione.
- [ ] NON attivare automaticamente la generazione **giornaliera** per tutti gli utenti: è una funzionalità separata, precedentemente rinviata.

**Stato tecnico noto:** codice headless/Neon/worker e servizio Flutter staging presenti nel progetto, ma il collegamento e2e tra richiesta client, motore remoto e risultato persistito non è ancora collaudato. Nessuna modifica ai server o alla build pubblicata è autorizzata da questa segnalazione.

## 2. PRIORITÀ ALTA — Pronostico principale e alternativa con quota reale

**Problema Build 46:** Crea Sistema mostra «feed senza quote Sisal utilizzabili» e soltanto «PRONOSTICI AI — SOLO ANALISI, NON SCHEDINA», anche con stime modello elevate. La versione non offre più la presentazione attesa di pronostico principale + alternativa quotata.

**Comportamento richiesto:**
- **Prima** il mercato più probabile secondo il modello, indipendentemente dalla quota: mostrarne probabilità e quota realmente rilevata anche se <1,20, oppure «quota N/D» se non quotato.
- **Sotto** il migliore mercato alternativo con quota reale **>=1,20**, probabilità sufficiente e controlli Auditor superati, se disponibile. Il principale non deve essere rimpiazzato o ricalcolato in funzione delle quote.
- Preferire Sisal se disponibile; se il feed non offre quote Sisal sufficienti, recuperare le quote REALI del provider/bookmaker precedente senza attribuirle falsamente a Sisal. Mostrare il bookmaker corretto per ogni prezzo. Nessun prezzo inventato.
- Se nessun bookmaker offre una selezione ammissibile, mostrare comunque il pronostico principale e indicare che nessuna alternativa verificata è disponibile. Non garantire artificialmente una schedina completa.

**Criteri di accettazione / regressione:**
- [ ] Primo mercato = probabilità sportiva più alta, senza filtri sulla quota (anche 1,10 o N/D).
- [ ] Se primo mercato è sotto 1,20, ricercare mercato DIVERSO con quota >=1,20, probabilità >= soglia selezionata e Auditor; non usare mercati 7–13% per alzare la quota.
- [ ] Se primo mercato è già >=1,20 e supera i controlli, può coincidere con la selezione giocabile, evitando un duplicato inutile.
- [ ] Quote Sisal vere, fallback ad altri bookmaker con fonte esplicita; mai attribuire quote di terzi a Sisal o mescolare quote simulate con reali.
- [ ] Interfaccia coerente in Crea Schedina e Combinazioni AI, inclusi i casi in cui non si riesce a generare un portfolio completo.
- [ ] Test dei casi: Sisal completo; Sisal assente e altro bookmaker presente; principale 1,10 con alternativa 1,25; nessuna quota; alternativa sotto soglia; nessuna selezione inventata.
- [ ] Validare su iPhone prima della prossima pubblicazione.

**Stato:** registrata, **non ancora implementata**. Accorpare con modifica n. 1 per la prossima build correttiva; non pubblicare direttamente.

## 3. PRIORITÀ ALTA — Risultati GoalVdLine / TOP 5 non deve sparire senza quote

**Screenshot TestFlight 1.2.5 (46), 13 novembre 2026:** la scheda **Risultati GoalVdLine**, periodo OGGI, mostra «GoalVdLine non ha trovato selezioni ... con qualità, Auditor e quota reale sufficienti» e nessun risultato.

**Causa verificata nel sorgente:** in `lib/screens/prediction_screen.dart`, `_generate` filtra anzitutto le candidate attraverso `SisalOddsService` e `_bestPickForMatch` (che restituisce null per odds null o tutte le quote sotto 1,20). `quoteQualified` può quindi essere vuoto, determinando pool AI vuoto, Top 5 vuoto e nessuna chiamata a Diego. Non è una prova che le partite non abbiano forecast sportivi validi.

**Correzione richiesta:**
- [ ] Effettuare ranking / shortlist **sportivo** prima del filtro prezzi anche nella pagina Risultati GoalVdLine, mantenendo il Top 5 dei pronostici principali stimati con controllo qualità e spiegazione trasparente.
- [ ] Presentare sotto ogni principale la migliore alternativa con quota reale >=1,20, probabilità minima e Auditor, **se disponibile** (vedere modifica n. 2). Una schedina quotata va costruita solo con selezioni realmente ammissibili; niente quote finte.
- [ ] Se Sisal non c'è, verificare il fallback a fonte quote reale alternativa con nome bookmaker; niente etichetta Sisal su prezzo di terzi.
- [ ] Distinguere a livello UI «nessun evento futuro analizzabile», «qualità dati insufficiente», «quote non disponibili», «nessuna alternativa giocabile», invece di mostrare un generico vuoto.
- [ ] Test con quote Sisal assenti ma analisi AI valida, e integrazione con la modalità TOP 5 / 2-3 giorni / personalizzato; collaudo iPhone prima del prossimo TestFlight.

**Stato:** analizzato e registrato; non corretto né distribuito.

## 4. PRIORITÀ ALTA — Confronto Diego AI assente dove mancano quote

**Screenshot TestFlight:** nelle Combinazioni normale e nella pagina Risultati AI non compare più il confronto Diego / SmartBet. La modalità manuale mostrava talvolta il confronto «N/D». Distinguere questi casi: la sola assenza grafica non prova un servizio Diego offline.

**Causa verificata:** `lib/screens/combinations_ai_screen.dart` richiama `_dualEngineService.attachDiego` **soltanto dopo** la validazione delle selezioni quotate (singola o sistema). `lib/screens/prediction_screen.dart` richiama `attachDiego` solo per il Top 5 finale. Se il filtro quote azzera i candidati finali, Diego non viene elaborato. Il servizio `DualEngineAnalysisService` resta nel codice, non è stato rimosso.

**Correzione richiesta:**
- [ ] Lanciare/conservare una valutazione Diego per i forecast sportivi selezionati **indipendentemente** dall'esistenza di una quota Sisal, in Crea Schedina, Risultati e Combinazioni; non attendere una schedina quotata.
- [ ] Preservare l'indipendenza di Diego e SmartBet: visualizzare pronostici, percentuali, confronto/accordo e segnali di affidabilità; non trasformare la stima Diego in una selezione giocabile senza quote e Auditor.
- [ ] Se Diego ha un errore concreto, mostrare motivo e stato tecnico leggibile senza esporre segreti; se non è stato eseguito, scrivere «non ancora analizzato» invece di «N/D» ambiguo.
- [ ] Deduplicare le chiamate Diego per fixture, mantenere cache, limite costi e verificare che l'assenza quote non aumenti imprevedibilmente le richieste pagate.
- [ ] Test: combinazioni normali senza Sisal, risultati Top 5 senza Sisal, manuale, Diego temporaneamente indisponibile e ripristino; poi collaudo iPhone.

**Stato:** analizzato e registrato; non corretto né distribuito.

## Verifica di X Premium (non classificata come guasto)

La modalità X Premium appare funzionante negli screenshot; usa `SmartBetXPremiumService` e non richiede quote o Diego. Le X mostrate (~25–31%) sono **simulazioni** sotto le soglie operative, e alcune partite hanno qualità dati N/D. Non confondere la visualizzazione con un pronostico affidabile. Monitorare, senza alterare automaticamente le soglie o promuovere queste X alla schedina.

## Altri bug del collaudo

Registrare altri bug dal **n. 5** quando l'utente li descriverà.

## Regole di rilascio

- Il registro riguarda la revisione correttiva successiva alla Build 46 TestFlight.
- Non pubblicare automaticamente un aggiornamento App Store e non avviare nuovi deploy Render/Neon.
- Verificare ogni correzione prima di preparare un'altra TestFlight.
