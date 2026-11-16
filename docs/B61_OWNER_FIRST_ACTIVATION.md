# GoalVdLine B61 — prima attivazione proprietario su iPhone

## Stato
**Solo ramo di sviluppo. Non abilitato in produzione, né inviato a TestFlight.**
La build B60 pubblicata conserva ancora la schermata di login senza account configurato.

B61 aggiunge una procedura di prima attivazione:
1. L'iPhone richiede un codice email **senza inviare alcun indirizzo email scelto dal client**. Il server invia soltanto all'indirizzo proprietario già autorizzato e fissato nelle sue variabili private.
2. Dopo il codice email di 8 cifre, valido 10 minuti, il server rilascia un ticket monouso di breve durata.
3. Soltanto con quel ticket viene generato sul server un segreto TOTP da 160 bit; l'app mostra una chiave manuale temporanea da inserire in Authenticator.
4. Il proprietario sceglie una password lunga (minimo 16 caratteri) e conferma un codice Authenticator di 6 cifre.
5. L'attivazione viene registrata **in una transazione PostgreSQL**; il seed TOTP è cifrato con AES-256-GCM, la password è salvata come hash scrypt con salt, i codici email sono verificati via HMAC, i token di sessione sono conservati solo come digest SHA-256 con scadenza dopo 15 minuti.
6. Una volta attivato l'account, la registrazione non può essere ripetuta usando soltanto la posta. L'accesso normale rimane password + TOTP; recupero di emergenza password + OTP inviato all'email fissata.
7. Nel passaggio fra app e server non viene mai usato il token amministratore degli altri servizi.

## Configurazione richiesta prima di una prova reale

Scegliere esplicitamente il workspace Render corretto e il servizio learning previsto; non scegliere un workspace per inferenza. Conservare solo nell'ambiente server:

- `GOALVDLINE_OWNER_ACCESS_V2_ENABLED=true` **solo dopo QA e migrazione**.
- `GOALVDLINE_OWNER_RECOVERY_EMAIL`: casella iCloud autorizzata dal titolare, **non** hardcoded nel repository.
- `GOALVDLINE_OWNER_RECOVERY_ENABLED=true`.
- `GOALVDLINE_OWNER_RECOVERY_EMAIL_FROM`: mittente di dominio verificato.
- `GOALVDLINE_OWNER_RECOVERY_RESEND_KEY`: chiave privata del provider per le email; richiede configurazione del mittente e verifica quota gratuita.
- `GOALVDLINE_OWNER_AES256_KEY_B64`: nuova chiave base64 32 byte generata con RNG CSPRNG in un ambiente protetto, mai stampata nei log e con copia di recupero sicura.
- `GOALVDLINE_OWNER_SETUP_HMAC_KEY`: nuovo segreto HMAC casuale di almeno 32 caratteri ad alta entropia.
- `DATABASE_URL` Neon già autorizzato per il servizio learning; SSL configurato secondo il certificato valido.

La migrazione proposta è `backend/admin/migrations/b61_owner_identity_v1.sql`. **Non è stata applicata a Neon di produzione**. Verificare la migration su un branch temporaneo, collaudare attivazione, ripresa dopo riavvio, collisioni concorrenti, timeout e rollback; poi richiedere l'autorizzazione per la migrazione di produzione.

## Controlli sicurezza e limiti

- 3 email massimo nell'ora con minimo un minuto fra invii.
- 5 tentativi errati di email/TOTP prima di invalidare challenge.
- 5 tentativi login errati e blocco temporaneo di 15 minuti, in modo persistente.
- TOTP anti-replay: uno stesso intervallo temporale non può essere riutilizzato.
- Un solo account proprietario; la migrazione contiene una riga singleton bloccata in transazione.
- Il ticket di iscrizione non viene salvato nel Portachiavi. L'app mostra il segreto Authenticator soltanto durante il pairing, e lo scarta dopo l'attivazione.
- Password e token non vengono registrati in analytics/log.
- I token login hanno scope esplicito `owner-staging-login-only`. **Non autorizzano automaticamente gli endpoint amministrativi del backend**, che necessitano di controlli di ruolo granulari successivi.
- Le operazioni automatiche di learning server-to-server restano separate dall'account proprietario; non necessitano di un telefono sbloccato.
- La casella email è un metodo di recupero dell'accesso, NON un metodo per reimpostare la password senza la password corrente.
- Nessun provider email, SMS o piano a pagamento è stato attivato con questa PR; nessun segreto personale è stato creato nella chat.

## Per l'utente

Una volta configurato il server e pubblicata una nuova versione TestFlight, aprire:
**Impostazioni → Area proprietario → Prima attivazione: scegli la password**.
Inviare il codice alla casella autorizzata, inserire le 8 cifre ricevute, aggiungere la chiave di 32 caratteri in Authenticator, scegliere una password ed entrare con il codice successivo.
Non condividere codici, la chiave TOTP o password con altre persone né in ChatGPT.

## Test
- `node --test backend/test/owner_first_activation_v2.test.js`
- `flutter test test/services/goalvdline_b61_owner_setup_test.dart`
- suite completa backend e Flutter su GitHub Actions B61.
