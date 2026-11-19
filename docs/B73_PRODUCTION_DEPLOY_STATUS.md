# B73 — produzione, stato di attivazione (19 novembre 2026)

- Backend distribuito con PR #19 sul servizio Render esistente
  `goalvdline-learning-api` (piano Free). Deploy `8a5d041e7cf74c42f88498f9622792ea313f359a` live.
- Migrazione additiva B73 su Neon production effettuata con successo;
  due nuove tabelle, entrambe inizialmente vuote.
- `DAILY_PALINSESTO_SCHEMA_READY=true` e
  `DAILY_PALINSESTO_REGISTRATION_ENABLED=true`.
  Chiave di cifratura dedicata generata sul server e non condivisa.
- `APNS_ENVIRONMENT=production` per l'ambiente TestFlight.
- `DAILY_PALINSESTO_PUSH_ENABLED=false` fino a collaudo sul dispositivo.
- L'attuale provisioning profile `SmartBet App Store` **non contiene**
  `aps-environment=production`. Il token APNs del telefono non può
  essere considerato pronto per notifiche remote finché il profilo
  non viene rigenerato con Push Notifications attive.
- La chiave App Store Connect usata dalla pipeline non è autorizzata
  a interrogare gli endpoint Apple Developer delle capability.
  Per questo nessun aggiornamento Apple lato Developer è stato eseguito.
- Il modulo provider usa il proxy esistente
  `https://smartbet-ai-y6gw.onrender.com/football/fixtures`,
  con cache e conteggio dei soli incontri futuri; no quote, no
  generazione automatica della schedina.
- Il workflow GitHub del riepilogo rimane inerte fino a configurazione
  dei segreti worker e `vars.DAILY_PALINSESTO_ENABLED=true`.
  Nessun nuovo piano né invio push reale attivati.

**Da completare**: Apple Developer Bundle ID Push Notifications, nuovo profilo
App Store con APS produzione, aggiornamento della secret GitHub
`IOS_PROVISIONING_PROFILE_BASE64`, credenziali APNs provider sul server
(`APNS_PRIVATE_KEY_BASE64`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
`APNS_BUNDLE_ID`) e test con iPhone bloccato.
