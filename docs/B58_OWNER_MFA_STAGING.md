# B58 — Accesso proprietario a due fattori (STAGING, non abilitato)

## Decisione

Non richiedere una password diversa ogni giorno, che sarebbe difficile da ricordare e facilmente riutilizzata. Usare:
1. **Password robusta e stabile** (modificabile dall'account owner, derivata con scrypt e salt casuale dal server).
2. **Codice TOTP di 6 cifre che cambia ogni 30 secondi**, generato da un'app compatibile come iCloud Passwords, Google Authenticator o Microsoft Authenticator. TOTP non richiede SMS, email, connessione del dispositivo né costi per messaggio.
3. **Sessione breve** (15 minuti in B58) e rinnovo solo dopo nuova verifica in questa fase. Opzionale biometria Face ID solo per sbloccare materiale protetto nel Portachiavi, mai come prova di ruolo lato backend.

**B58 è solo una fondazione disabilitata di default:** `GOALVDLINE_OWNER_MFA_STAGING_ENABLED` non è impostata né attivata in Render. Non sono stati impostati password, codici, indirizzi email o numeri di telefono. Non c'è ancora una schermata login Flutter collegata; la sessione di prova **non concede accesso agli endpoint di amministrazione** già esistenti e non è integrata con la UI del Learning Monitor.

## Componenti nel repository

- `backend/admin/owner_mfa_staging.js`: verifica scrypt e TOTP RFC 6238, rifiuta il riutilizzo dello step, mantiene massimo 3 token temporanei hashati, limita a 5 tentativi falliti e blocca per 15 minuti. Nessuna password/codice in log.
- `/owner/v1/login`, `/owner/v1/session`, `/owner/v1/logout`: sessione di prova senza permessi applicativi, registrata sul server learning esistente.
- `backend/test/owner_mfa_staging.test.js`: test RFC, mancata configurazione, password sbagliata, OTP monouso, tentativi, scadenza, revoca e controllo assenza privilegi.

Per un eventuale ambiente STAGING isolato servirebbero **in variabili server private**, mai nel codice o in un client Flutter:
- `GOALVDLINE_OWNER_MFA_STAGING_ENABLED=true` (default assente/false).
- `GOALVDLINE_OWNER_PASSWORD_SCRYPT=scrypt$16384$8$1$<64-hex-salt>$<64-hex-hash>`; hash da generare con un processo di provisioning autenticato oppure OFFLINE, e password mai stampata nei log.
- `GOALVDLINE_OWNER_TOTP_SECRET_BASE32=<segreto TOTP almeno 160-bit>`; scambio soltanto in un flusso di provisioning altamente protetto. Non esporre il segreto in API o screenshot.
- HTTPS obbligatorio alla frontiera TLS (Render). Client owner deve usare TLS pinning o policy piattaforma e il Portachiavi.

## Prima di usare questo login per leggere dati privati o lanciare operazioni

1. **Sessioni e anti-replay centralizzati su Neon** con transazioni atomiche, rate limiting persistente anche su più istanze / riavvii. L'attuale versione usa memoria di processo, quindi il controllo replay TOTP e i tentativi potrebbero essere resettati da un restart o su più container: **non è pronta per la produzione**.
2. Autorizzazione del ruolo `owner` lato server (ID verificato, endpoint consentiti, nessuna possibilità di autoproclamarsi amministratore); distinguere API `/owner/..` dalle credenziali `LEARNING_ADMIN_TOKEN` destinate solo al server.
3. Provisioning iniziale del segreto con verifica forte, recupero tramite codici monouso custoditi offline, rotazione/revoca segreti e notifiche di sicurezza.
4. Gestione di sessioni e logout globale, audit minimizzato dei tentativi senza registrare password, OTP, token o IP in chiaro, e test penetrazione/CSRF/CORS.
5. Controlli di sicurezza dell'app iPhone: token effimero nel Portachiavi, nessun token hardcodato, visualizzazione area interna soltanto dopo sessione owner verificata. Il flag `GOALVDLINE_INTERNAL_DIAGNOSTICS` non è autenticazione.
6. Nessuna apertura pubblica fino alla conclusione di una prova isolata.

## Invio codice via email o SMS (fase successiva, OPZIONALE)

**Email OTP:** endpoint che genera un codice casuale monouso di breve validità, lo invia a un solo indirizzo *verificato* tramite un provider transazionale, conserva soltanto una verifica protetta (con rate limit/replay/tentativi) e non risponde con il codice. Richiede credenziali e configurazione di un servizio email; l'invio non è attivato in B58. Email compromessa può compromettere anche l'OTP.

**SMS OTP:** possibile con un provider di invio, ma ogni SMS costa ed è vulnerabile a SIM swap; quindi prevederlo al più come recupero d'emergenza, con limiti di spesa e antifrode. Nessun costo di invio attivato.

**Opzione consigliata per costi zero per codice e maggior affidabilità:** password personale + TOTP via Authenticator, email di notifica (non necessariamente email OTP) e codici di recupero offline. La password NON ruota ogni giorno; il secondo fattore ruota ogni 30 secondi.

## Trattamento dati / altre automazioni

Le operazioni automatiche di apprendimento già consentite non devono dipendere da una sessione owner aperta sull'iPhone. Usare worker server-to-server con credenziali separate, solo per scopi approvati; non riutilizzare i token personali per schedini, controlli quote o acquisizione web. Nessun invio dati utente senza consenso, nessuna modifica delle scelte di SmartBet/Diego/QuoteLab.

Riferimenti: NIST SP 800-63B (rev. 4), OWASP MFA Cheat Sheet, RFC 6238.
