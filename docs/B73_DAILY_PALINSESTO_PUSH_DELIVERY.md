# Build 73 — invio mattutino del palinsesto (non delle schedine)

Ramo: `feature/b73-daily-palinsesto-push-delivery`.
Questa fase NON abilita automaticamente servizi Render, né migra Neon di
produzione, né pubblica una nuova build TestFlight.

## Nuovo comportamento previsto
- L'utente sceglie se ricevere il riepilogo: inizialmente OFF, 08:00 Europe/Rome.
- L'iPhone invia un token APNs cifrabile solo dopo opt-in; le preferenze
  delle schedine automatiche non partecipano alla registrazione.
- I token APNs vengono cifrati AES-256-GCM sul server con chiave separata.
- Il server conta le partite future per campionato in un'unica lettura
  del calendario, **senza** odds, pronostici o schedine automatiche.
- Una notifica APNs con numero di partite e principali competizioni,
  contenente solo la sintesi, non informazioni personali.
- Richiesta idempotente per soggetto/giorno su Neon. Retry sicuro dopo
  timeout, massimo 5 tentativi, stop alle 12:00 Europe/Rome.
- Registrazione revocata alla disiscrizione o revoca delle credenziali.
  Cancellazione completa congiunta alla cancellazione dei dati mobile.

## Endpoints dedicati (sempre protetti)
- POST `/learning/v1/mobile/palinsesto/subscribe`
  (Bearer mobile, JSON `{deviceToken,hour,minute}`).
- POST `/learning/v1/mobile/palinsesto/unsubscribe`
  (Bearer mobile, JSON `{}`).
- POST `/learning/v1/palinsesto/worker/dispatch`
  (segreto worker server-to-server, paginazione <=25).

Tutte le nuove operazioni restano disattivate per default.
`GET /learning/v1/status` fornisce
`dailyPalinsestoRegistrationEnabled` e `dailyPalinsestoPushEnabled`.

## Neon staging verificato — 19 novembre 2026

La migrazione B73 è stata applicata **solo** sul ramo Neon
`smartbet-b45-staging` (`br-delicate-art-bawymk9l`) mediante
transazione additiva. I controlli hanno confermato:
- `sb_daily_palinsesto_subscriptions_v1`: presente, 0 righe;
- `sb_daily_palinsesto_deliveries_v1`: presente, 0 righe;
- chiave primaria, vincoli su ora/minuto/ambiente APNs/stato e indice retry;
- database di produzione invariato, nessuna delle due tabelle B73 presente.

## Provisioning, da eseguire soltanto dopo verifica

1. **Staging completato.** Applicare lo stesso script B73 al database
   **di produzione solo con autorizzazione esplicita**; non migrare i dati
   delle vecchie schedine.
2. Verificare APNs production/TestFlight con token iPhone reale e corretta
   chiave `APNS_PRIVATE_KEY_BASE64`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT=production`.
3. Sull'API learning esistente (nessun nuovo piano), garantire
   `FOOTBALL_API_KEY` e accesso al DB migrato. Attivare separatamente
   `DAILY_PALINSESTO_SCHEMA_READY=true`,
   `DAILY_PALINSESTO_REGISTRATION_ENABLED=true`,
   `DAILY_PALINSESTO_PUSH_ENABLED=true`,
   `DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY` (64 hex)
   e `DAILY_PALINSESTO_WORKER_TOKEN` (minimo 32).
4. Nel repository GitHub configurare soltanto i segreti
   `DAILY_PALINSESTO_DISPATCH_URL` con URL HTTPS completo del worker endpoint
   e `DAILY_PALINSESTO_WORKER_TOKEN`. Il workflow
   `b73-morning-palinsesto-push.yml` schedulato funziona quando è sul
   **default branch**: le versioni feature non lo attivano.
5. Verificare TestFlight con iPhone bloccato, 08:00 Europe/Rome
   e differenza ora solare/legale. GitHub Actions può avviarsi in ritardo:
   non promettere precisione al minuto.
6. Prima di produzione: approvazione separata per la nuova migrazione,
   verifica dei ruoli/permessi e dei costi API (un feed/giorno non equivale
   a 7.500 richieste disponibili garantite).

## Non attivato ora

Le notifiche di prova iOS confermano soltanto la funzionalità locale del
telefono, non la consegna remota APNs. Il ramo B73 richiede ancora
migrazione, ambiente server, segreti GitHub, revisione produzione e
verifica reale. Nessuna schedina quotidiana viene generata.
