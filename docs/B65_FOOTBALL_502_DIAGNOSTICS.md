# GoalVdLine — diagnostica 502 API-Football (B65)

**Data:** 18 novembre 2026  
**Ramo:** `feature/b64-sports-reading`  
**Stato:** solo codice e test, **nessun deployment Render**.  

## Evidenze disponibili

- Le metriche del servizio Render `smartbet-ai` (istanza `srv-da0u5795efls73agloi0`) tra il 17 novembre 08:00 UTC e il 18 novembre 09:00 UTC hanno riportato 596 risposte HTTP 502, 13 risposte 503, 2200 risposte 200 e 7 risposte 404.
- I tentativi di consultare i log granulari dell'intervallo tramite il connettore Render non hanno restituito righe. Non possiamo attribuire con certezza i 502 a un endpoint specifico né distinguerli da errori generati dal proxy Render.
- Il backend **effettivamente distribuito** (`feature/api`, commit `6b68cfb60947fa99b22572e77b305e1dffc4442f`) contiene tre rami di errore API-Football che convertono errori del fornitore in HTTP 502: HTTP non riuscito, risposta JSON malformata e payload JSON con oggetto `errors` popolato. Questo è un **possibile** meccanismo per i 502, non una diagnosi conclusiva dei 596 eventi.
- Il backend distribuito non contiene ancora la nuova protezione credenziali o i rate limit B65. Non attivare un deploy diretto di `feature/b64-sports-reading` sul servizio di produzione senza audit dei delta tra i rami.

## Diagnostica introdotta (esclusivamente nel branch GitHub)

Moduli: `backend/football_upstream_diagnostics.js` e `backend/server.js`.

- Ogni richiesta upstream continua a essere **una sola richiesta**, senza retry automatici.
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
- Test Node: classificazione di tutte le cause, nessun retry, assenza di informazioni sensibili, coerenza dei quattro handler proxy, timeout, forma della risposta valida.

## Come validare la causa in sicurezza

1. La CI del ramo deve essere verde prima di ulteriori cambiamenti.
2. Verificare l'insieme delle differenze con il ramo distribuito, in particolare compatibilità API, chiavi, dipendenze e budget per processo.
3. Abilitare la diagnostica prima su ambiente non di produzione; utilizzare richieste innocue e una quota limitata, senza esporre credenziali.
4. Solo dopo un rollout esplicitamente approvato e reversibile, osservare il nuovo log `FOOTBALL_UPSTREAM_DIAGNOSTIC` nei periodi di 502. Incrociare i timestamp con status edge Render e le richieste `/football/*` per capire quali errori sono effettivamente upstream.
5. Se il fornitore risponde con 429 o `errors.requests`, verificare limiti contrattuali e volume richieste; se 401/403, controllare le credenziali senza stamparle; se 5xx, distinguere disservizio esterno da errori app; se 502 edge senza log app, esaminare disponibilità e configurazione Render.
6. Non attivare servizi o piani a pagamento e non modificare la produzione senza consenso esplicito.

**Nota:** questa patch migliora l'osservabilità; **non dimostra né risolve ancora** la causa storica dei 596 errori.
