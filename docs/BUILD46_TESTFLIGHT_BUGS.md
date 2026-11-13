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

## Altri bug del collaudo

Registrare altri bug dal **n. 3** quando l'utente li descriverà.

## Regole di rilascio

- Il registro riguarda la revisione correttiva successiva alla Build 46 TestFlight.
- Non pubblicare automaticamente un aggiornamento App Store e non avviare nuovi deploy Render/Neon.
- Verificare ogni correzione prima di preparare un'altra TestFlight.
