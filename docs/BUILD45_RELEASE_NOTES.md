# GoalVdLine AI — Build 45 | Release notes interne

Versione preparata: **1.2.5+45**. La versione non è ancora su TestFlight.

## Funzioni client previste

- Schedina AI e analisi su richiesta con mercati filtrati per probabilità/qualità.
- Portafoglio di varianti coordinate sulle stesse partite, nei limiti delle selezioni effettivamente disponibili.
- Previsione sportiva da mantenere distinta dalla selezione quotata; niente ripiego su pronostici deboli 7–13% solo per raggiungere la quota minima.
- Generatore tre varianti allineato alla quota Sisal minima **1.20** (prima una soglia interna residua 1.25 scartava selezioni 1.20–1.24); test regressione aggiunti, verifica su Mac ancora da eseguire.
- Riepilogo in Home delle partite future del giorno candidabili all'analisi (non numero di pronostici affidabili già prodotti).
- Notifica locale iOS opzionale dopo generazione positiva richiesta dall'utente, con salvataggio e apertura dell'ultimo riepilogo sul dispositivo. Permesso richiesto nelle Impostazioni.

## Limiti espliciti

- Niente generazione automatica quotidiana su server o APNs per AutoSchedina: codice conservato, feature rimandata per evitare nuovi costi fissi.
- Il numero nella Home è calcolato all'apertura o al refresh, non inviato automaticamente alle 08:00 con app chiusa.
- Una notifica locale non garantisce che un'analisi prosegua dopo chiusura forzata dell'app.
- La schermata aperta dalla notifica mostra un riepilogo testuale dell'ultima schedina locale, non l'editor originale. Quote e disponibilità possono cambiare.
- Nessuna quota Sisal va inventata quando mancano dati reali; le previsioni non diventano vincite garantite.

## Evidenze e release gate ancora aperti

- Flutter: 685 test passati e 3 skipped su revisione 0449c23, exit 0.
- Tap notifica: 5 test mirati passati e compilazione iOS senza firma riuscita su revisione 5c969a7, exit 0.
- Prima dell'unico upload TestFlight: regressioni quote Sisal e probabilità deboli, firma e pipeline GitHub. Dopo l'upload **della stessa Build 45 firmata**: collaudo reale iPhone di consenso, notifiche, tap e snapshot; nessuna seconda build di prova è prevista.
- PR #1 di staging ancora draft: non fare merge automatico verso staging Render/Neon.

## Procedura di rilascio

- Sorgente di preparazione: feature/b45-p20-4-multiday.
- Workflow GitHub predisposto per il futuro branch release/b45-testflight con numero build 45; **non creare né fare push di quel branch prima della chiusura dei gate**.
- Nessun upload TestFlight, nuovo servizio Render o modifica Neon in questa fase.

## Autorizzazione alla pubblicazione

- **13 novembre 2026:** pubblicazione dell'unica Build 45 su TestFlight autorizzata dall'utente in chat.
- Versione e numero build: **1.2.5 (45)**; sorgente release branch `release/b45-testflight`.
- La pipeline GitHub Actions `SmartBet iOS TestFlight` è autorizzata a firmare e caricare la build su App Store Connect; lo stato effettivo va verificato nei job.
- La PR di staging resta in bozza e AutoSchedina remota, worker Render e sincronizzazioni aggiuntive non devono essere attivati.

## Apple pre-release train — correzione tecnica

- Il tentativo GitHub #51 ha superato Flutter analyze, firma e archive; Apple ha rifiutato `CFBundleShortVersionString = 1.2.4` per train chiuso (`90186`, `90062`).
- Per il tentativo di rilascio seguente la versione pubblicabile è **1.2.5 (45)**: cambia solo il numero versione marketing; il numero build rimane **45**, e il codice applicativo rimane invariato.
- Non dichiarare TestFlight caricato finché GitHub Actions non conferma `Upload SmartBet to TestFlight` riuscito.
