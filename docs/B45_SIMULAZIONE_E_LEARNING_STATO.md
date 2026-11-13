# GoalVdLine — Stato della simulazione delle partite e del cervello AI
**Data:** 13 novembre 2026  
**Branch:** `feature/b45-p20-4-multiday`  
**Tipo di verifica:** lettura del codice GitHub, non misura dei dati reali sul dispositivo.

## Executive summary
La simulazione sportiva esiste: il motore GoalVdLine/Diego simula partite reali future usando dati prepartita, ma è una simulazione statistica di risultati/gol, **non una riproduzione tattica minuto per minuto**. Il simulatore Poisson bivariato e il simulatore contestuale sono usati in larga parte per confronto **SHADOW** e verifica retrospettiva. Non ci sono evidenze di promozione già avvenuta del nuovo simulatore al motore ufficiale.

Il cervello dispone di raccolta di pronostici prepartita, risoluzione dei risultati finali, confronto errori, statistiche per mercato e campionato, calibrazione storica con cautele, gating sperimentale e un possibile percorso opt-in di correzione delle percentuali. Non modifica automaticamente la matematica di tutti i motori o i dati degli incontri ogni volta che un pronostico fallisce. Il rilascio Build 45 resta incompleto.

## 1. Due simulazioni diverse

### A. Motore GoalVdLine Monte Carlo già integrato
- `lib/ai/goalvdline_match_engine.dart`.
- La stima dei gol attesi usa la performance della squadra, quella dell'avversaria, dati recenti e altri fattori di contesto disponibili.
- Simulazione Monte Carlo con seed deterministico; numero di campioni limitato nel codice a 1.000–100.000.
- Calcola 1/X/2, Over, Goal e distribuzione dei risultati esatti.
- `lib/services/diego_ai_service.dart` richiama `GoalVdLineMatchEngine.simulate(input)` in analisi prepartita.
- Questi numeri sono previsioni probabilistiche, non risultati certi e non dati estratti da partite effettivamente giocate.

### B. Simulatore Poisson bivariato e contesto
- `lib/services/smartbet_match_simulation_service.dart`: versione `p21a-bivariate-poisson-v1`; distribuzione dei gol con intensità comune opzionale, dai gol attesi; nessuna quota.
- `lib/services/smartbet_contextual_simulation_service.dart`: usa contesto prepartita strutturato quando validato; **non** trasforma in modifiche numeriche dirette testo libero su assenze o formazioni.
- `lib/services/smartbet_simulation_shadow_capture_service.dart`, `smartbet_contextual_shadow_capture_service.dart`: congelano snapshot precedenti al kickoff per confronto.
- `smartbet_simulation_outcome_audit_service.dart`: paragona previsioni e risultati con metriche Brier (più basso = meglio).
- `smartbet_simulation_learning_validation_service.dart`: esperimenti offline con almeno 60 fixture di training, 40 di validazione, 10 giornate di training e 7 di validazione, più vantaggio minimo misurabile.
- `smartbet_simulation_shadow_policy_service.dart`: pesi promossi solo in SHADOW, **mai direttamente sulle schedine ufficiali**.
- Mancano una simulazione tattica completa dei 90 minuti e la prova che un nuovo modello abbia già superato i gate su dati reali sufficienti.

## 2. Cosa avviene quando un pronostico è sbagliato?
1. La previsione originaria e la sua percentuale sono registrate prima del match, se il flusso di registrazione è eseguito.
2. Dopo la conclusione, il resolver `smartbet_analysis_result_resolver.dart` controlla solo record pending, raggruppa per fixture e aspetta almeno 4 ore dall'orario di kickoff per interrogare i risultati.
3. Se il risultato finale è confermato, aggiorna i record di tutti i mercati pertinenti a quella fixture a corretto/errato e registra la risoluzione; se il risultato manca, non lo inventa.
4. `smartbet_adaptive_learning_service.dart` misura successi e Brier Score per mercato, campionato, **mercato × campionato** e fasce di probabilità; segnali con meno di 50 osservazioni sono insufficienti, da 50 esplorativi, 100 segnale e 200 candidati più forti.
5. `smartbet_historical_calibration_service.dart` ricava, per un mercato, lo scarto fra successi osservati e media delle probabilità stimate. Richiede almeno 50 record validi, conosciuti prima della nuova previsione.
6. La correzione proposta è `clamp((successi/n - media_probabilita) * n/(n+100), -0.10, +0.10)`; l'effetto massimo è 10 punti percentuali, con forte attenuazione su campioni piccoli.
7. L'effettiva calibrazione locale richiede la preferenza opt-in del dispositivo e il gate `smartbet_learning_gate_service.dart`: almeno 100 casi aggiustati, 14 giornate distinte e miglioramenti coerenti in più finestre temporali. Senza questi requisiti il valore **rimane invariato**.
8. La probabilità originale dello storico resta immutabile. Il sistema non modifica i pesi del motore Monte Carlo automaticamente a ogni errore; la nuova simulazione viene prima confrontata in SHADOW.

**Esempio solo illustrativo:** se un mercato era mediamente stimato all'80% ma vince nel 70% di 100 pronostici validi, lo scarto è -10 punti. Con fattore 100/(100+100)=0,5 si propone -5 punti; una nuova previsione all'80% diventerebbe 75% **solo se consenso e gate sono approvati**. Questo non dimostra alcun aumento certo di rendimento.

## 3. Stato del server centrale e delle schedine
- `backend/learning/learning_service.js` riceve previsioni prima del kickoff, le verifica lato server e gestisce risultati finali.
- L'upload mobile richiede consenso e credenziale valida; i vecchi snapshot retrospettivi sono distinti e non diventano automaticamente prove prospettiche.
- Alcune API AutoSchedina nella revisione letta riportano `generationActive: false` e `pushActive: false`; non confondere presenza degli endpoint con attivazione operativa.
- P20.4, schedine multi-giorno, ha superato in precedenza test e una prova reale locale READY (3 schedine con stesse 3 partite, su due date diverse).
- P20.6, regola app-wide **pronostico indipendente dalle quote + sola Sisal + minimo 1.20 + alternative separate**, è in corso sul branch e **non ancora collaudata dopo le ultime modifiche**.
- Non è verificato l'effettivo numero di pronostici risolti sul telefono dell'utente; il repository non contiene il database iPhone e questo archivio non lo esporta.
- Il requisito di utilizzare affidabilità realmente calibrata per **campionato e mercato** nel ranking automatico di tutte le schedine resta da completare/validare, anche se la segmentazione statistica è già implementata.

## 4. Cosa manca prima di affermare che il cervello impara davvero per tutti gli utenti?
1. Verificare sul dispositivo i conteggi veri di pronostici risolti, scartati e non verificabili, separati per mercato e campionato.
2. Verificare che la raccolta consensuale e la risoluzione lato Render/Neon funzionino end-to-end, includendo deduplica, scadenze, privacy e disconnessioni.
3. Accertare per ogni mercato se il gate shadow approva la correzione e quanti punti applica; non assumere che l'opt-in attivi sempre il learning.
4. Collegare i segnali empirici per campionato/mercato a una selezione/ranking futura, prima in SHADOW, con test prospettici e controlli per campioni piccoli.
5. Confrontare sistematicamente modello vecchio vs simulatore nuovo con valutazione temporale fuori campione, solo poi decidere eventuale promozione.
6. Chiudere il contratto forecast-first in **tutte** le schermate e collaudare la disponibilità reale del feed Sisal; nessuna quota di bookmaker diverso deve essere sostituita.

## 5. Scope dello ZIP
Lo script `tool/b45_export_complete_project.sh` crea in `~/Downloads` uno ZIP dell'intera **versione tracciata su GitHub** (sorgenti Flutter e iOS/Android, backend, test e documentazione), non un'app binaria pronta da installare. Non contiene il database personale dell'iPhone, i file temporanei, i segreti locali, l'eventuale storico Neon né il repository Git completo. Un archivio del sorgente, per definizione, non prova lo stato di esecuzione dei job remoti o i dati accumulati sul telefono.
