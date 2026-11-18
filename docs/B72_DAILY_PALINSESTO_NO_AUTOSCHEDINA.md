# B72 — Riepilogo del palinsesto, nessuna AutoSchedina quotidiana

## Decisione del 18 novembre 2026

- Ritirare la **generazione programmata quotidiana delle schedine**:
  la creazione resta soltanto su esplicita richiesta dell'utente.
- Conservare le notifiche di schedina pronta generate su richiesta.
- Introdurre una **notifica quotidiana del calendario**, di default
  alle 08:00 **Europe/Rome**. Preferenza disattivata finché l'utente
  non dà consenso. L'orario è modificabile nelle preferenze locali.
- Contenuto: totale degli incontri ancora in programma, numero di
  competizioni, nomi dei campionati più rappresentati. Elenco completo
  recuperabile dal riepilogo JSON, non iniettato in una notifica lunga.
- Mai indicare che queste partite siano tutte pronosticabili o giocabili:
  non ci sono analisi AI, quote o controlli di bookmaker.

## Implementato sul ramo feature B72

- Rimossa dalle Impostazioni la UI `AutoSchedina AI quotidiana`.
  Il vecchio widget e il codice di migrazione rimangono nel repository
  per compatibilità storica; **nessun worker quotidiano viene attivato**
  da questa modifica. Le impostazioni on-demand restano invariate.
- Nuova card separata per la preferenza del riepilogo quotidiano.
  Stato OFF di default, ora preferita 08:00, salvataggio su iPhone.
  Il testo chiarisce che salvare la preferenza NON attiva un push:
  non usare una notifica locale con conteggi di ieri come surrogato.
- `backend/daily_palinsesto/digest.js`: conteggio distinti dei
  fixture NS/TBD futuri nel giorno Rome, raggruppamento competizioni,
  supporto all'ora legale; fallisce se mancano dati provider, mai
  conteggio fittizio zero.
- `GET /football/palinsesto/oggi`: read-only sul vecchio backend API,
  usa una sola richiesta `/fixtures` con cache/single-flight condivisa
  con l'app, non richiede `/odds` e non genera pronostici.
  Non è ancora distribuito al servizio Render live.
- `backend/daily_palinsesto/apns_sender.js`: trasporto HTTP/2 Apple
  separato dalle notifiche di schedina, payload `daily_fixture_digest`,
  firma APNs da segreti server, disattivato per default con flag
  `DAILY_PALINSESTO_PUSH_ENABLED`. Nessuna notifica inviata finora.
- Test: digest/profilazione campionati e DST, APNs mock, persistenza
  preferenze e UI. CI `.github/workflows/b72-daily-fixture-digest-qa.yml`.

## Non ancora attivo: prerequisiti reali della notifica alle 08:00

1. Registrazione APNs iOS *indipendente* da quella legata
   all'AutoSchedina, opt-in esplicito, revoca e cancellazione del token.
   Verificare `aps-environment` nel TestFlight firmato.
2. Associare in modo cifrato i token ai dispositivi iscritti e
   l'orario preferito in Neon; deduplicazione invio per utente e giorno.
   Richiede nuova migrazione **da validare prima in staging**; produzione
   da autorizzare separatamente.
3. Scheduler sicuro (ad esempio GitHub Actions come trigger,
   ora europea con gestione DST) che invoca un endpoint privato.
   Una sola lettura del palinsesto per giorno, non per ogni dispositivo.
4. Attivare la feature sul server esistente, SENZA piani a pagamento,
   soltanto dopo APNs/iOS, database e test con iPhone bloccato.
5. Se API-FOOTBALL è in cooldown/429/503, rimandare l'invio:
   **mai inventare conteggi** né sostituirli con uno zero.

Non pubblicare B72 come se il push fosse già operativo. Le altre
notifiche di prova e le schedine su richiesta non vengono modificate.
