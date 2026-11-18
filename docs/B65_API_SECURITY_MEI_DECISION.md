# GoalVdLine B65 — sicurezza API e MEI, decisione tecnica (18 novembre 2026)

## Stato del codice e della pubblicazione
- Codice di sicurezza in `backend/public_api_access_guard.js`, con test Node e middleware registrato in `backend/server.js`.
- Il middleware riguarda `/analyze`, `/audit` e l'albero `/football`.
- Fino alla distribuzione del ramo sul backend di produzione, i limiti NON sono attivi sul server Render pubblico.
- La Build 64 installata NON include il nuovo supporto credenziale per il server AI.
- Non è stata richiesta né autorizzata l'attivazione di servizi a pagamento, né nuove modifiche al database.

## Difesa base abilitata dal codice quando distribuito
- AI: limite per IP di 90 richieste/ora, budget globale **per processo** di 1200 richieste/giorno e massimo 6 richieste AI simultanee.
- Football: limite per IP di 120 richieste/minuto, budget globale **per processo** di 30000 richieste/giorno e massimo 20 simultanee.
- Risposta 429 con `Retry-After`. Identità IP basata sul trasporto Express, NON sul valore X-Forwarded-For fornito dal client.
- Gli indirizzi di proxy/NAT possono raggruppare più dispositivi. I limiti per processo NON sono limiti globali tra replica/riavvii e non garantiscono un tetto monetario OpenAI. Un sistema distribuito richiederebbe contatori condivisi (es. Neon/Redis) e un budget ufficiale separato.
- I parametri si modificano con le variabili `PUBLIC_AI_CLIENT_HOURLY_LIMIT`, `PUBLIC_AI_GLOBAL_DAILY_LIMIT`, `PUBLIC_AI_MAX_CONCURRENT`, `PUBLIC_FOOTBALL_CLIENT_MINUTE_LIMIT`, `PUBLIC_FOOTBALL_GLOBAL_DAILY_LIMIT`, `PUBLIC_FOOTBALL_MAX_CONCURRENT` solo dopo aver valutato il traffico.

## Credenziali installazione — da attivare in un rilascio coordinato
- Le installazioni con token provisionato possono usare `GoalVdLineMobileTokenVault`; il token è quello rilasciato dal learning server e conservato nel Portachiavi.
- `SmartBetAiService` invia tale Bearer a `/analyze` e `/audit` solo se la nuova app viene compilata con `--dart-define=GOALVDLINE_AI_MOBILE_AUTH=true`. Default false: nessuna trasmissione nuova di credenziali.
- Per la verifica server-side, configurare in modo riservato `PUBLIC_API_AUTH_DATABASE_URL` sul backend AI con accesso minimo alla tabella `sb_learning_clients_v1`; opzionale `PUBLIC_API_AUTH_PG_SSL=true`.
- **Non** attivare `PUBLIC_AI_MOBILE_TOKEN_MODE=require` prima che le installazioni ammesse abbiano token validi e che la nuova app sia distribuita. Questa azione bloccherebbe i client più vecchi e gli utenti senza credenziale learning.
- `PUBLIC_FOOTBALL_MOBILE_TOKEN_MODE` resta `off`: per attivarlo servirebbe aggiornare anche tutti i client di fixture, quote, catalogo e dossier; oggi solo il rate limit automatico protegge i loro percorsi.
- Non inserire token amministratore, chiavi di Neon, OpenAI o di altri provider nel client.
- Prima dell'attivazione aggiorna privacy e flussi di consenso se estendi l'uso della credenziale learning.
- In presenza di errore DB, la modalità `require` rifiuta la richiesta; non degrada mai a modalità anonima.
- Un provider di auth più stabile, budgeting condiviso e una strategia di migrazione utenti saranno necessari per il rilascio pubblico.

## Valutazione idea MEI di Emergent
Il testo di Emergent è una proposta, **non codice verificato**. Il percorso `/app/uploads/GoalVdLine_B64_MEI_trial.zip` appartiene al suo ambiente e non era allegato in questa conversazione.

Il modello di affidabilità lega/mercato già memorizza `wilsonLower95Percent`, `observedAccuracyPercent`, `brierScore`, `calibrationGapPoints`, `distinctMatchDays`, `sampleSize` e `probabilitySampleSize`. Non duplicare il calcolo.

### Cosa adottare
1. INDICE puramente diagnostico per `engine + country + league + market`; preferire l'etichetta 'Indice affidabilità storica' a 'Facilità mercato'. Lo storico non è la probabilità della prossima partita.
2. Gate preliminare: almeno 100 partite indipendenti, 14 giornate, e almeno 100 probabilità effettivamente salvate per calcolare Brier e calibrazione. Le soglie esistenti: signal >=100, strong >=200; non presentare signal come validazione live.
3. Wilson inferiore, overconfidence (segno del gap di calibrazione) e qualità probabilistica rispetto a un baseline; non costruire immediatamente un numero unico con pesi arbitrari.
4. Assoluta separazione tra probablità sportive e quote. La quota e l'eventuale EV vengono valutati DOPO la classificazione di affidabilità, non sono un requisito del MEI.
5. Solo SHADOW per il primo rilascio, nessun riordino di mercati, nessun cambiamento del pronostico, nessun passaggio automatico in live.
6. Confronto prospettico tra motori sullo stesso insieme di partite/mercati, per non confondere la difficoltà del campione con la qualità del motore.
7. Finestre mobili, freeze pre-partita, deduplica fixture, audit e controlli su multi-test, variazioni del regime e leakage.
8. Trial e kill-switch solo dopo validazione statistica out-of-sample. Non attivare la calibrazione live generale insieme a una nuova formula MEI: impossibile attribuire in modo affidabile l'effetto al MEI.

### Cosa rifiutare
- MEI come 'mercato facile se batte la quota bookmaker': sarebbe un indice di vantaggio economico, non di precisione del pronostico.
- Premio automatico per Brier più basso senza benchmark: un mercato facile e ad alta prevalenza può ottenere punteggi migliori senza maggiore capacità predittiva del motore.
- Badge 'Affidabile 86%' che si possano scambiare per la probabilità della singola partita; mostra sempre N, Wilson e data aggiornamento.
- 'Additive, fail-safe' considerato verificato senza compilazione, test e confronto del diff.
- Riscrittura/attivazione di più strategie contemporaneamente (MEI live, calibrazione, metamodel e trial) prima del confronto prospettico.

## Prossimo passaggio prima di un nuovo TestFlight
1. Fare verde la CI del branch con backend + Flutter.
2. Distribuire rate limits tramite il flusso Render/GitHub esistente solo dopo la verifica dei limiti sul traffico reale e dell'impatto sui client.
3. Allineare le credenziali mobile per tutti gli utenti/servizi, realizzare onboarding e privacy; solo allora richiedere token in produzione.
4. Implementare MEI in sola lettura partendo dal servizio affidabilità già presente, con dati reali, senza cambiare selezioni né calibrazione.
