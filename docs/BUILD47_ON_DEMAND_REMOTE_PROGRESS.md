# GoalVdLine Build 47 — Schedina su richiesta indipendente da iPhone

Stato del 13 novembre 2026: **sviluppo isolato, NON attivo in produzione**.
Questo documento riguarda la Modifica n. 1 del collaudo TestFlight 1.2.5 (46).

## Obiettivo utente

Premere «Crea Schedina» su iPhone, bloccare lo schermo o chiudere l'app
e ritrovare la schedina senza ricominciare il calcolo; avviso di completamento
solo con consenso. Riutilizzare prioritariamente Render/Neon gia' pagati,
senza aprire altri servizi o aumentare i costi senza verifica.

## Implementato nel branch `feature/b47-corrections`

- Backend: coda Neon separata `sb_on_demand_coupon_jobs_v1` in
  `backend/learning/learning_schema.sql` con job UUID, richiesta idempotente,
  tenant isolato tramite hash, stato, risultato validato, limite 5 richieste al
  giorno e un solo job attivo per soggetto.
- Repository: creazione, lettura per soggetto, claim atomico con
  `FOR UPDATE SKIP LOCKED`, lease UUID, rinnovo, finalizzazione con fencing
  e cancellazione dei job in erase GDPR; restart Render recuperabile.
- Motore: `backend/auto_coupon/on_demand_coupon_service.js` chiama
  esclusivamente l'adapter Flutter headless esistente; non ricrea i pronostici
  in Node, non inventa quote, controlla la quota **strettamente >1,20**.
- API mobile autenticata:
  `POST /learning/v1/mobile/on-demand-coupon/jobs` -> 202 e job UUID,
  `GET /learning/v1/mobile/on-demand-coupon/jobs/:jobId` -> stato/coupon.
  La richiesta NON attende il calcolo e NON contiene token amministratore.
- Trigger worker separato:
  `POST /learning/v1/on-demand-coupon/worker/run`, autorizzato con token
  server distinto. Loop opt-in sul processo `backend/learning_only_server.js`
  tramite `on_demand_scheduler.js`, disattivato di default.
- iOS/Flutter: client HTTP `goalvdline_on_demand_coupon_client.dart` con
  HTTPS, niente redirect, bearer mobile dal Keychain fornito dal chiamante,
  request UUID salvato PRIMA dell'invio e job UUID ricordato localmente.
  Il client evita di lanciare un secondo job quando riapri l'app.
- UI beta separata in `lib/widgets/goalvdline_on_demand_coupon_panel.dart`,
  collegata a `create_ai_coupon_screen.dart`. Visibile solo se Render
  certifica flag on-demand attivo; non modifica il percorso locale.
- Test widget per flag OFF/ON e presenza delle azioni esplicite.
  Le quote del JSON remoto non riportano ancora la fonte bookmaker e
  l'headless AutoSchedina non garantisce mercati OR, confronto Diego,
  filtri per campionato e corrispondenza con la generazione manuale.
  **Questi sono blocchi di parità funzionale**, non funzionalità già approvate.
- Test automatici backend: validazione richiesta, idempotenza, isolamento
  dispositivi, lease, quote, nessun risultato fittizio, flag disabilitati,
  worker autenticato, scheduler no-overlap. Test Flutter client: trasporto
  autorizzato, resume senza doppio POST, struttura e parametri rifiutati.

## Flag richiesti, tutti OFF di default

- `LEARNING_SERVER_ENABLED`, `LEARNING_MOBILE_INGEST_ENABLED` e credenziali
  centrali già amministrate: necessari prima di qualsiasi API mobile.
- `ON_DEMAND_COUPON_REQUESTS_ENABLED=true`: abilita POST/GET mobile, ma
  NON avvia da sola il motore.
- `ON_DEMAND_COUPON_WORKER_ENABLED=true` + token worker >=32 caratteri:
  abilita trigger server protetto.
- `ON_DEMAND_COUPON_SERVER_POLL_ENABLED=true`: abilita polling su processo
  centrale esistente (non richiede un worker Render separato se capacità e
  configurazione vengono verificate).
- `AUTO_COUPON_OFFICIAL_ENGINE_ENABLED` + URL/hostport, token e revisione
  pin della macchina Flutter headless: il backend deve avere davvero il motore
  ufficiale installato e raggiungibile.

**MAI attivare in produzione da questo branch senza collaudo.**
Non impostare alcun flag AutoSchedina giornaliera né APNs prima di una verifica
indipendente. Non incorporare segreti nel repository o nel bundle iOS.

## Blocchi da risolvere prima di TestFlight/Store

1. Verificare da Render Dashboard **quale servizio pagato** avvia
   `backend/server.js` e quale `backend/learning_only_server.js`.
   Il primo non espone automaticamente queste nuove route. Confermare
   CPU/memoria, spese e stato effettivo del Flutter staging.
2. Migrare schema su Neon **staging**, testare claim multiprocesso, riavvii,
   revoca token, cancellazione dati, rate limiting e ripresa. Nessuna migrazione
   live eseguita da ChatGPT.
3. **Collegamento UI implementato nel branch:** il riquadro
   «ELABORAZIONE SERVER · BETA» appare SOLO in modalità automatica/OGGI
   e SOLO se il server risponde con il feature flag abilitato.
   Offre invio esplicito, recupero dell'ultima richiesta su riapertura
   o riattivazione dell'app e visualizzazione delle tre varianti.
   Il pulsante locale esistente resta funzionante e distinto.
   **ANCORA DA VERIFICARE** su iPhone/Render con dati reali, inclusi
   SmartBet/Diego, mercati OR, bookmaker e quota esatta: non dichiarare
   equivalenza con il sistema locale e non attivare l'interfaccia prima
   del collaudo staging.
4. Verificare equivalenza dell'output del motore server con l'analisi
   su richiesta del dispositivo: l'adapter headless attuale deriva
   dall'AutoSchedina ufficiale e non garantisce tutte le opzioni manuali,
   le spiegazioni e il confronto Diego. Non sostituire tacitamente una UI
   con un motore diverso.
5. Validare APNs reale da app chiusa e tap della notifica con consenso;
   la notifica locale iOS non risolve l'elaborazione in background.
6. Eseguire Flutter analyze, suite Flutter completa, suite Node e compilazione
   iOS; poi collaudo TestFlight limitato. Non pubblicare App Store finché
   il blocco dell'iPhone non è verificato su dispositivo reale.

Nessun nuovo acquisto, deploy Render, migrazione Neon o upload TestFlight
è stato autorizzato da questa patch di sviluppo.
