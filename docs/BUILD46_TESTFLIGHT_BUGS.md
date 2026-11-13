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

## Altri bug del collaudo

L'utente ha segnalato la presenza di **altri bug**, senza ancora fornire i dettagli. Registrarli numerati dal **n. 2** quando li descriverà, senza ipotizzarne natura o gravità.

## Regole di rilascio

- Il registro riguarda la revisione correttiva successiva alla Build 46 TestFlight.
- Non pubblicare automaticamente un aggiornamento App Store e non avviare nuovi deploy Render/Neon.
- Verificare ogni correzione prima di preparare un'altra TestFlight.
