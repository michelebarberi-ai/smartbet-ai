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

## Credenziali per installazione — rollout B65, ancora OFF

**Regola di sicurezza:** il vecchio token mobile ha scope `learning:predictions`
e NON autorizza chiamate a OpenAI. Un token con permesso `ai:analyze` può
essere emesso soltanto da un endpoint amministrativo protetto e separato.

- La migrazione additiva `token_scopes` è stata **separata** dall'avvio automatico in `backend/learning/migrations/2026_11_mobile_ai_scopes.sql`. `LearningRepository.initialize()` applica soltanto `learning_schema.sql` e **non modifica implicitamente la colonna dei permessi**. Lo schema Neon produzione è ancora quello legacy, senza `token_scopes`. Le chiamate learning e il provisioning learning-only restano compatibili, mentre emissione e verifica `ai:analyze` richiedono la migrazione approvata separatamente e falliscono in modo chiuso quando manca.
- `LearningRepository.findValidClientForScope(..., 'ai:analyze')` verifica scope, hash, scadenza e revoca. Gli altri scope sono rifiutati dalla nuova API.
- `POST /learning/v1/clients/provision-ai` è accessibile SOLO al server amministrativo, richiede `LEARNING_AI_SCOPE_PROVISION_ENABLED=true`, che è **disattivato di default**. I client iOS non possiedono la chiave amministrativa e non possono autoassegnarsi privilegi.
- I nuovi token hanno la forma opaca già prevista e scadono secondo la durata del servizio learning (30 giorni). Serve un piano di rinnovo che NON ricorra all'emissione anonima.
- Sul telefono `GoalVdLineAiScopedTokenVault` usa una chiave Portachiavi diversa da `GoalVdLineMobileTokenVault`. Nessun fallback al token learning; accetta il salvataggio solo se l'emissione ha dichiarato `ai:analyze`.
- `SmartBetAiService` allega il token AI solo con `--dart-define=GOALVDLINE_AI_MOBILE_AUTH=true`; il valore predefinito è `false`. `/analyze` e `/audit` usano HTTPS origin fissata e non seguono redirect con la credenziale.
- Backend: `PUBLIC_AI_MOBILE_TOKEN_MODE=off` è il default. `prefer` consente la transizione: anonimi con budget ridotti, verificati AI-scoped con quota per installazione. `require` blocca tutti i client privi di token: **non attivare** finché non è pronta la distribuzione delle credenziali per gli utenti.
- Per collegare il server AI allo storico dei token, predisporre `PUBLIC_API_AUTH_DATABASE_URL` con privilegi minimi **di sola lettura** sulla tabella delle credenziali; aggiungere connessione TLS e verifica certificate secondo configurazione Neon. Non esporre credenziali in Flutter.
- I token AI non sono ancora provisionati sul telefono via UI pubblica. Non promettere che tutti possano effettuare l'accesso a `require` o che una credenziale esistente abbia scope AI.
- Per qualunque rollout verificare privacy e cookie/log, il reale host del reverse proxy, traffico per IP/NAT, rischi di blocco e possibilità di rollback. I limiti attuali sono **per processo**, non un tetto economico globale.
- L'informativa `GET /privacy` è stata aggiornata **nel codice** per descrivere Neon, Render, OpenAI, provider sportivi, APNs, consenso e diritti. Prima del rilascio pubblico deve essere controllata per titolare, informazioni di contatto, periodi di retention, trasferimenti e aggiornamento della scheda privacy App Store. Il valore di default `support@example.com` va sostituito con un contatto reale in configurazione.
- Non attivare servizi a pagamento, non aggiornare Neon di produzione, non cambiare impostazioni Render e non pubblicare TestFlight senza il gate di rilascio.

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
