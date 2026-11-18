# GoalVdLine — diagnostica 502 API-Football (B65)

**Data:** 18 novembre 2026  
**Ramo:** `feature/b64-sports-reading`  
**Stato:** solo codice e test, **nessun deployment Render**.  

## Evidenze disponibili

- Le metriche del servizio Render `smartbet-ai` (istanza `srv-da0u5795efls73agloi0`) tra il 17 novembre 08:00 UTC e il 18 novembre 09:00 UTC hanno riportato 596 risposte HTTP 502, 13 risposte 503, 2200 risposte 200 e 7 risposte 404.
- I log HTTP di tipo `request` non risultano accessibili nel periodo. Un'ulteriore ricerca mirata nei log applicativi `app` del **17 novembre 08:00–16:00 UTC** ha però restituito 100 messaggi di errore: **87** contengono `API-Football HTTP 429` e **13** contengono `API-Football ha restituito un errore`. È un campione di **messaggi**, non il conteggio definitivo delle chiamate fallite; il risultato ha pagine ulteriori.
- Un altro campione di 100 righe `API-FOOTBALL REQUEST` include richieste a `/fixtures`, `/odds`, `/fixtures/headtohead`, `/injuries`, `/fixtures/lineups` e `/leagues`. Non è stato possibile associare ciascuna di queste richieste a una risposta 429.
- Pertanto, gli errori di rate limiting upstream sono **una causa documentata di almeno parte dei 502**, ma non si può attribuire loro l'intera serie di 596 eventi senza maggior dettaglio.
- Questa correlazione è stata ottenuta in sola lettura, senza effettuare richieste al provider o alla produzione.
- Il backend **effettivamente distribuito** (`feature/api`, commit `6b68cfb60947fa99b22572e77b305e1dffc4442f`) contiene tre rami di errore API-Football che convertono errori del fornitore in HTTP 502: HTTP non riuscito, risposta JSON malformata e payload JSON con oggetto `errors` popolato. Questo è un **possibile** meccanismo per i 502, non una diagnosi conclusiva dei 596 eventi.
- Il backend distribuito non contiene ancora la nuova protezione credenziali o i rate limit B65. Non attivare un deploy diretto di `feature/b64-sports-reading` sul servizio di produzione senza audit dei delta tra i rami.

## Diagnostica introdotta (esclusivamente nel branch GitHub)

Moduli: `backend/football_upstream_diagnostics.js` e `backend/server.js`.

- Ogni richiesta upstream continua a essere **una sola richiesta**, senza retry automatici.
- Nuovo `backend/football_provider_gate.js`: blocco per-processo **condiviso fra tutti i path API-Football**. Dopo HTTP 429: cooldown iniziale di 2 minuti, raddoppio in caso di 429 ripetuti fino a 30 minuti, poi **una sola richiesta-sonda** per verificare il recupero. Le altre richieste nel cooldown non arrivano al fornitore e ricevono HTTP 503 con `code=FOOTBALL_PROVIDER_COOLDOWN` e `Retry-After`. Le chiamate upstream contemporanee sono limitate a **4 per processo**, con **coda FIFO fino a 32 richieste** e attesa massima di **8 secondi**, per non respingere le normali analisi di molte partite quando il provider è sano. Quando la coda è piena o una richiesta supera l'attesa massima, la risposta è HTTP 503 `FOOTBALL_PROVIDER_BUSY`. In caso di 429, la coda viene svuotata con `FOOTBALL_PROVIDER_COOLDOWN`: non vengono inviate nuove richieste al fornitore. Nessun messaggio di attesa è considerato un risultato calcistico.
- La cache valida continua a funzionare prima del controllo. I dati scaduti non vengono riproposti come freschi. Nessuna nuova connessione o costo fisso richiesto.
- I codici locali di cooldown e busy sono registrati con massimo un evento per endpoint/minuto per evitare tempeste di log.
- Timeout per richiesta upstream di 25 secondi: protegge dai timeout indefiniti. Il timeout è categorizzato separatamente.
- Le risposte valide del fornitore non cambiano: fixture, quote, statistiche e league vengono restituite nella forma originale.
- Le risposte fallite continuano a usare 502, con eccezione della chiave mancante sul server (503). Errori inattesi del proxy: 500.
- I 502 includono un codice diagnostico sicuro:
  - `FOOTBALL_PROVIDER_RATE_LIMIT` per HTTP upstream 429.
  - `FOOTBALL_PROVIDER_AUTH` per HTTP upstream 401/403.
  - `FOOTBALL_PROVIDER_HTTP_ERROR` per altri status upstream non riusciti.
  - `FOOTBALL_PROVIDER_INVALID_JSON` per body non JSON o non oggetto in risposta 2xx.
  - `FOOTBALL_PROVIDER_REPORTED_ERROR` quando `errors` è presente e non vuoto in un JSON 2xx.
  - `FOOTBALL_PROVIDER_NETWORK_ERROR` per connessione fallita.
  - `FOOTBALL_PROVIDER_TIMEOUT` per timeout della richiesta.
  - `FOOTBALL_PROVIDER_KEY_MISSING` (503) per chiave non configurata.
- Il log `FOOTBALL_UPSTREAM_DIAGNOSTIC` contiene soltanto endpoint, categoria, status HTTP upstream e status HTTP proxy. Non registra: chiave API, query, body di risposta del fornitore, IP o dati del dispositivo.
- I precedenti campi diagnostici con risposta raw `apiResponse` sui fallimenti vengono rimossi: nessun payload arbitrario del provider nel JSON al client. La risposta di successo resta invariata; in errore il client riceve un messaggio stabile, `code` e `success:false`.
- Le righe cache hit/miss/single-flight registrano solo il path, non parametri query.
- Non vengono effettuate nuove chiamate ai fornitori per questa diagnosi.
- Test Node: classificazione di tutte le cause, nessun retry, assenza di informazioni sensibili, coerenza dei quattro handler proxy, timeout, forma della risposta valida. Ulteriori test: cooldown fra path differenti, backoff, recupero con sonda singola, concorrenza massima, `Retry-After`, precedenza della cache, coda FIFO, saturazione, cancellazione della coda dopo 429 e compatibilità con richieste normali. La simulazione HTTP su `127.0.0.1` usa 180 richieste durante il cooldown, 45 durante la sonda e 20 richieste sane contemporanee, senza consumare API-Football. I risultati vanno confermati dalla CI.

## Come validare la causa in sicurezza

1. La CI del ramo deve essere verde prima di ulteriori cambiamenti. Per isolare la verifica del backend AI esiste `.github/workflows/backend-ai-staging-isolated.yml`, che esegue i test HTTP reali e quelli dei componenti con Node 22; non necessita di segreti GitHub, database o servizi a pagamento. Le esecuzioni consumano normali minuti GitHub Actions secondo i limiti del repository.
2. Verificare l'insieme delle differenze con il ramo distribuito, in particolare compatibilità API, chiavi, dipendenze e budget per processo.
3. Il servizio Render `smartbet-b45-flutter-staging` è in realtà un **private service Docker headless** (branch `staging/b45-render-linux`, Dockerfile `deploy/p20_3d/Dockerfile.headless`) usato per l'elaborazione remota delle schedine, non uno staging del backend `smartbet-ai`. Non va riutilizzato né sostituito per testare il proxy calcistico. La prima verifica isolata usa **GitHub Actions e un server HTTP locale** con risposte simulate; non è un test del provider reale su Render. Dal 18 novembre abbiamo anche un test **end-to-end del vero server Express**: `backend/test/football_server_e2e_mock.test.js` avvia `backend/server.js` in un processo figlio su 127.0.0.1, con credenziali fittizie e un preload `backend/test/fixtures/football_server_mock_preload.js` che blocca qualsiasi fetch verso l'esterno. La prova esercita i veri endpoint `/health`, `/football/fixtures`, `/football/leagues`, `/football/odds`, `/football/api/fixtures` e controlla concorrenza, cache, single-flight, cooldown e ripresa. Questo non rappresenta un deployment Render né un test con dati sportivi reali.
4. Prima di qualunque rollout reale, predisporre un endpoint/staging AI separato e compatibile **senza attivare spese aggiuntive senza consenso**; verificare volumi effettivi, latenza e uso della coda sullo staging. Non colpire API-Football con test di carico.
5. Solo dopo un rollout esplicitamente approvato e reversibile, verificare che il tetto di quattro chiamate upstream e la coda da 32/8 secondi non causino ritardi nelle analisi complete. Osservare il nuovo log `FOOTBALL_UPSTREAM_DIAGNOSTIC` nei periodi di 502. Incrociare i timestamp con status edge Render e le richieste `/football/*` per capire quali errori sono effettivamente upstream.
6. Se il fornitore risponde con 429 o `errors.requests`, verificare limiti contrattuali e volume richieste; se 401/403, controllare le credenziali senza stamparle; se 5xx, distinguere disservizio esterno da errori app; se 502 edge senza log app, esaminare disponibilità e configurazione Render.
7. Non attivare servizi o piani a pagamento e non modificare la produzione senza consenso esplicito.

**Nota:** i log applicativi dimostrano che API-Football ha risposto con 429 durante l'incidente. La patch migliora l'osservabilità e introduce un fail-fast contro le tempeste di richieste. Non dimostra né risolve ancora tutte le cause storiche dei 596 errori; deve essere testata in un ambiente non produttivo e distribuita soltanto con un piano di rollback.
