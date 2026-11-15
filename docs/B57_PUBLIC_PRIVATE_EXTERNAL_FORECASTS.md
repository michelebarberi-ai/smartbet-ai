# GoalVdLine B57 — Edizione pubblica e area tecnica

## Stato implementazione

- **Pubblico (default):** Home mostra solo `Qualità e apprendimento`, con conteggi di previsioni realmente prepartita e concluse; non mostra token, sincronizzazioni, audit, Brier, SHADOW, QuoteLab e pulsanti di backtest.
- **Edizione interna (distribuzione separata):** con `--dart-define=GOALVDLINE_INTERNAL_DIAGNOSTICS=true` conserva le attuali schermate di diagnostica, monitor, revisioni e amministrazione sul dispositivo.
- **Impostazioni pubbliche:** rimangono opt-in/revoca della raccolta di nuove previsioni locali e cancellazione remota tramite **credenziale mobile dell'utente salvata in Portachiavi**, se presente; mai token amministratore. Nessun invio automatico viene attivato da questa patch.
- **Web Consensus:** servizio matematico read-only per osservazioni provenienti solo da fonti esterne autorizzate. Esclude fonti non autorizzate, osservazioni registrate dopo kickoff, conflitti e duplicati. Calcola il rapporto di concordanza solo con almeno 3 editori indipendenti, **non una probabilità di vittoria**; non cambia SmartBet, Diego, QuoteLab o Coupon.

## Sicurezza: non scambiare UI interna per accesso amministratore

`GOALVDLINE_INTERNAL_DIAGNOSTICS` è solo un **profilo di distribuzione**, non prova l'identità dell'utente e non autorizza alcun endpoint server. Non contiene né deve mai contenere `LEARNING_ADMIN_TOKEN` o altre credenziali admin. Un utente che controlla il proprio dispositivo può modificare un client, quindi **l'accesso effettivamente privato richiede un sistema di login con identità verificata lato server**.

Prima del rilascio pubblico dell'area amministrativa:
1. Implementare un login amministratore verificato lato server (preferibilmente Apple/Passkey/OIDC), sessioni brevi e revoca.
2. Conservare un elenco di subject-id autorizzati **solo sul backend**; verificare ogni endpoint di lettura dati tecnici e modifiche, non fidarsi di flag Dart, nome, email non attestata o semplice nascondimento del menu.
3. Tenere le informazioni aggregabili per tutti gli utenti separate da dati personali o token; audit degli accessi, policy di ritenzione e cancellazione.
4. Generare due artefatti/edizioni distinti con Github pipeline verificata; produzione sempre default pubblico; build interna solo canale di distribuzione controllato.
5. La sola build interna non basta per endpoint privilegiati. Non pubblicare TestFlight con questa patch prima della verifica delle edizioni.

## Automazione da rendere predefinita

**Automatico sul dispositivo, solo mentre l'app è attiva:**
- Controlli delle previsioni concluse: `HomeScreen.initState` già richiama `_refreshAnalysisHistory` e `SmartBetLearningCoordinator.refresh`. Aggiungere scheduler del ciclo vita applicazione e controlli anti-duplicato senza dipendere da un bottone.
- Riepilogo locale: già ricalcolato automaticamente nel widget da snapshot storico e risultati risolti, senza quote o nuove API.
- Aggiornamenti classifica affidabilità per campionati e segmenti QuoteLab: read-only sui dati già osservati, senza intervento dell'utente.
- Applicare correzioni AI **solo** dopo gate statistico e senza toccare previsioni congelate per valutazione.

**Automatico sul server, quando configurato e autorizzato:**
- Risoluzione fixture e learning prospettico tramite job schedulato con token amministratore esclusivamente lato server. Un endpoint `/learning/v1/resolve` protetto esiste già; una schedule persistente non è stata ancora attivata con B57.
- Normalizzazione di feed di pronostici web/licenziati (fixture, mercato, autore, esito, orario pubblicazione e first-seen), consolidamento con risultati reali, misure qualità per fonte, eliminazione duplicati.
- Raccolta quote storiche sotto le licenze accordate e con budget di chiamate. Nessuna richiesta bulk indiscriminata, nessun nuovo piano a pagamento automatico.

**Non automatico senza consenso:**
- Invio al server di dati dell'utente, trasferimento storico retrospettivo, notifiche push, nuove autorizzazioni a trattare dati personali. Revoca e cancellazione devono restare azioni volontarie, semplici e visibili.

## Sorgenti web / Telegram

- Limitare ingestione a API/feed dove i termini autorizzano memorizzazione e riutilizzo statistico, oppure previsioni **volontariamente** fornite da autori/editori con consenso esplicito e revocabile.
- `https://telegram.org/tos/bot-developers`: vieta esplicitamente l'uso di Bot Platform per collezionare dataset massivi di messaggi pubblici di gruppi/canali per training/produzione AI. Nessuno scraping Telegram è stato implementato.
- Il consenso o il permesso di leggere un canale non implica permesso di redistribuirne i contenuti o creare un dataset AI; conservare accordi con gli editori e applicare retention e attribuzione.
- Web Consensus è una quarta dimensione **esterna**: conteggio per editore indipendente, mai convertito direttamente in probabilità o usato per smentire SmartBet e Diego senza validazione prospettica.

## Limiti attuali

B57 è una struttura preparatoria, non un sistema completo di autorizzazione admin, né una raccolta live. Nessun nuovo account, cron job, costo server, migrazione database, invio dati o distribuzione TestFlight da questo ramo.
