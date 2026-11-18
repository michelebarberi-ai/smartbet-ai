# GoalVdLine — roadmap tecnica unica (18 novembre 2026)

> Questa roadmap consolida le idee esterne (Emergent/Claude) e le verifiche del **nostro** repository. Nessun codice esterno va importato. Versione di sviluppo: ramo `feature/b64-sports-reading`, successiva alla Build 64 distribuita. Nessun aggiornamento automatico di Render, Neon, TestFlight o servizi a pagamento è autorizzato da questo documento.

## Prodotto: regola fondamentale

1. Ogni motore produce **una previsione sportiva autonoma** e probabilità per mercati standard, con fonti, timestamp, qualità e versione modello.
2. Il pronostico più affidabile **rimane visibile** anche se la sua quota è inferiore a 1,20.
3. Solo dopo la stima sportiva si esaminano **alternative** per probabilità e affidabilità, evitando mercati incoerenti e verificando quote REALI e disponibilità sul bookmaker italiano. Le quote non modificano la probabilità sportiva.
4. SmartBet/SmartCore, Diego e Terzo cervello rimangono separati. La quarta identità è una prospettiva futura da validare prospetticamente, non una media automatica. Il terzo cervello ora può usare propri risultati FT per casa/trasferta, ma la fonte calcistica è condivisa e il fallback usa xG SmartBet o Diego.
5. Se mancano dati, quote valide o affidabilità sufficiente, mostrare **N/D**, non inventare una selezione.
6. Quote e EV sono aspetti **di giocabilità**, non dell'Indice di Affidabilità Storica (MEI). Non confondere probabilità stimata, accuratezza storica, Wilson ed edge.
7. Nessuna nuova funzione complessa finché sicurezza, confronto dati e funzioni già esistenti non sono stabili.

## P0 — Sicurezza e costi dell'analisi AI

### Stato verificato
- Il codice `backend/public_api_access_guard.js` e la registrazione del middleware in `backend/server.js` esistono sul ramo di sviluppo. I limiti sono **per processo**, non condivisi fra istanze; senza deployment non proteggono Render.
- `/analyze`, `/audit`, `/football/*` possono richiedere token solo tramite feature flag: modalità predefinita `off`, per non interrompere la Build 64.
- `app.use(cors())` resta aperto: restringerlo può ridurre chiamate dal browser, ma NON sostituisce l'autenticazione.
- Esiste una credenziale mobile sul learning backend/Keychain; vanno coordinati policy/privacy, distribuzione client e verifica della credenziale sul server di analisi.
- I limiti di traffico non garantiscono da soli un tetto monetario ai consumi OpenAI.

### Prossimi passi
1. Inventario di tutti i percorsi AI/football usati dal client, compresi eventuali proxy, doppi servizi Render e fallback.
2. Test integrazione autenticazione con dispositivo reale, token validi/non validi, cold start, rotazione, utenti precedenti e fallback.
3. Contatori condivisi per installazione autenticata e limite globale realistico con alert di budget; non attivare risorse a pagamento senza consenso.
4. Deploy backend coordinato, inizialmente limiti compatibili, osservazione di 429/401/5xx e rollback disponibile.
5. Solo quando gli iPhone possono inviare la credenziale correttamente, attivare gradualmente `require` su `/analyze` e `/audit`. Per `/football` serve prima aggiornare tutti i chiamanti.
6. Revisione CORS, body size, timeouts e limitazione chiamate OpenAI concorrenti. Bloccare bypass e percorsi alternativi.

**Gate di completamento:** client vecchi gestiti o migrati consapevolmente, test device passati, limiti coerenti su tutte le istanze, nessun percorso costoso anonimo non protetto, spesa monitorata. Non promuovere in produzione prima.

## P0 — Misurazione affidabilità e apprendimento sicuro

### Già nel ramo
- MEI diagnostico con Wilson 95%, Brier e malus sovrastima; finestra 365 giorni, 100 fixture e 14 giornate per sola ricerca.
- Terzo cervello registrato separatamente, con provenienza degli input e versione modello.
- Confronto paired Brier/Log Loss/calibration gap per stessa fixture/mercato su previsioni frozen prepartita, con esiti coerenti; pannello in Intelligenza e apprendimento.

### Ancora necessario
1. Campionamento prospettico **uniforme e non selezionato a posteriori** dei mercati standard per tutti i tre cervelli; non limitarsi al solo mercato preferito di ogni motore. È probabile che lo storico attuale contenga poche terne identiche.
2. Timestamp di snapshot, versione, fonti, coverage per lega/mercato e deduplica fixture; non contare cinque mercati dello stesso match come cinque partite indipendenti.
3. Validazione out-of-sample e walk-forward: accuratezza del mercato scelto, calibrazione, Brier, Log Loss, campioni e intervalli. Separare valutazione delle previsioni da disponibilità delle quote.
4. Misurare delta vs baseline storica e vs versione precedente su identiche partite; gestire leakage, cambi di regime, segmenti multipli e kill-switch.
5. Attivazione della calibrazione live P15A **solo dopo un trial reversibile con miglioramento dimostrato**; mai promozione automatica basata sulla sola accuratezza in-sample.
6. Quarta identità: prima SHADOW con confronto dati completi e attribuzione della confidenza; solo dopo trial controllato.

**Gate:** 100 fixture + 14 giornate per una ricerca preliminare; soglia più alta, finestra indipendente, riduzione robusta di Brier/Log Loss e controllo nel tempo prima di qualsiasi effetto sulle schedine. Nessuna promessa di vincita.

## P0 — Privacy e App Store

### Stato verificato
- `GET /privacy` mostra ancora la data 29 agosto 2026 e una descrizione generica.
- Sono da censire push APNs, token dispositivo/credenziali mobile, log/identificativi, richieste AI OpenAI, football data, job su Render/Neon, durata conservazione, utenti e consenso.
- App Store Connect richiede dichiarazioni corrispondenti ai dati realmente raccolti; non inventare periodi di conservazione o trattamenti non confermati.

### Passi
1. Inventario end-to-end reale dei dati, provider, localizzazioni dei dati, retention/cancellazione e condivisioni.
2. Scrivere informativa adeguata e verificarla prima del rilascio pubblico, includendo contatto e scelte utente.
3. Aggiornare etichette privacy in App Store Connect e note/disclaimer sul gioco responsabile; valutare requisiti 18+ e policy applicabili.
4. Verificare specificamente le basi d'uso delle API esterne non ufficiali.

## P1 — Push iOS e schedine remote

- Il repository include solo `ios/Runner/GoalVdLineKeychain.entitlements`, senza `aps-environment`; non risultano `remote-notification` in `Info.plist`. Verificare prima il profilo di provisioning e la CI, poi impostare capability APNs e background come necessario.
- Test su dispositivo: foreground, background, app terminata, blocco telefono, token APNs, payload, badge, log. Non confondere silent push con notifiche visibili o con garanzia di esecuzione di lavoro in background.
- Confrontare motore remoto e locale sulla STESSA fixture e sugli STESSI parametri: mercati OR, 1X2, handicap, filtri campionati, Diego, quota reale >1,20 e bookmaker; dove manca parità segnalare funzione limitata, non garantire equivalenza.
- Spostare i job pesanti verso Dart puro solo dopo avere una baseline riproducibile ed equivalenza dei risultati; evitare `flutter test` in produzione a lungo termine.

## P1/P2 — Architettura e fonti sportive
- Configurare URL backend e chiavi dal server/flavor, non hardcodare provider nei vari schermate; conservare segreti fuori dal client.
- Verificare affidabilità, copertura serie/leghe e condizioni d'uso delle fonti di dati, compreso eventuale accesso Sofascore non ufficiale; prevedere fallback senza creare partite fantasma.
- Correggere prima i percorsi realmente utilizzati; eliminare stub o codice morto solo dopo verifica delle dipendenze e copertura test.
- Scomporre gradualmente `combinations_ai_screen.dart` e `create_ai_coupon_screen.dart` in servizi/widget più semplici. Valutare gestione stato condiviso solo se offre vantaggi misurabili, evitare una riscrittura completa.
- Flutter rimane la base. Nessuna migrazione Expo/React Native nel ciclo attuale.

## P2 — Distribuzione e manutenzione
- Attualmente 21 workflow GitHub, da consolidare dopo il rilascio stabilizzato, preservando test specifici, permessi minimi, guard di autorizzazione e compatibilità release.
- `codemagic.yaml` forza `--build-name=1.0.0`; correggere se usato, ma il rilascio prioritario passa da GitHub Actions.
- `android/app/build.gradle.kts` contiene ancora applicationId di esempio e firma debug in release: blocco per un futuro store Android, non per la firma iOS.
- `ITSAppUsesNonExemptEncryption` è annidato nella parte `UISceneConfigurations` invece che al primo livello di Info.plist: correggere e verificare il plist risultante in CI.
- Consolidare documentazione tecnica con questa roadmap e uno stato di release/versione; non cancellare workflow o documenti storici senza valutare trigger e riferimenti.

## Ordine operativo dei prossimi interventi

1. **Hardening P0 completo** su API, token e costi, con roll-out conservativo e nessuna spesa fissa nuova.
2. **Registrazione uniforme delle probabilità** di tutti e tre i motori per mercati standard e stessa fixture, in modo da alimentare la diagnostica paired.
3. **Privacy e push iOS**, testando i pacchetti di firma e la trasmissione delle notifiche su device.
4. **Parità schedine remote/locali**, test goldens e limiti di quote/mercati.
5. **Learning trial** e quarta identità SHADOW quando i dati dimostrano miglioramento; pulizia infrastruttura e workflow in una fase distinta.

## Regola release
- Lavorare su branch dedicato, QA automatico (Node, Flutter analyze/test, iOS build) prima di TestFlight.
- Mai considerare un commit di sviluppo come rilascio pubblico; distinguere GitHub, Render, upload TestFlight e processamento Apple.
- Nessuna spesa Render/Neon a pagamento senza consenso esplicito.
