# GoalVdLine B56 — QuoteLab (terza lente statistica)

## Decisione architetturale

**SmartBet AI** stima lo sport senza quote. **Diego AI** fornisce un secondo giudizio sportivo indipendente. **QuoteLab** legge soltanto quote storiche e risultati reali per identificare dove il mercato abbia sottostimato o sovrastimato frequenze osservate. Le tre componenti restano separate e il verificatore di giocabilità consulta le quote **solo dopo** il pronostico sportivo. QuoteLab NON sceglie selezioni ufficiali.

## Stato dati verificato

- `SmartBetAnalysisHistoryStore` salva, per previsione registrata, `quotedOdd`, `firstSeenAt`, `matchDate`, `resolvedAt`, mercato, campionato ed esito. **Non salva il bookmaker né tutte le altre quote offerte.** Lo storico soffre quindi di *selection bias*: include solo mercati effettivamente analizzati/salvati.
- Il progetto Neon `goalvdline-learning` al controllo read-only del 16/11/2026 conteneva 7 previsioni (6 fixture, 0 risolte) nella tabella `sb_learning_predictions_v1`; non c'è una tabella storica delle quote. Questi dati sono insufficienti per affermare un tasso di successo affidabile.
- Il codice P21W ha già un pannello read-only “Affidabilità per campionato e mercato”; la sua validazione SHADOW **non è una promozione automatica del motore**.
- Il modulo B56 analizza solo le quote **già salvate prima dell'inizio**, verifica i risultati con il market-settlement, rimuove duplicati/conflitti, esclude quote/mercati mancanti e calcola gruppi mercato/campionato/fascia quota.

## Indicatori QuoteLab B56

- **Hit rate osservato** = successi / pronostici quotati verificati.
- **Probabilità implicita lorda** = 1/quota (non corretta del margine).
- **Intervallo di confidenza Wilson 95%** attorno all'hit rate.
- **ROI storico ipotetico** = somma dei risultati su 1 unità per evento / numero eventi, *solo sul campione selezionato*.
- Sotto 30 eventi: insufficienti; oltre 30: esplorativi; almeno 100 e 14 giornate: candidata a validazione separata (mai automaticamente affidabile o giocabile).

## Per uno storico realmente rappresentativo

Serve una nuova tabella (NON CREATA in Neon, perché serve approvazione della migrazione e fonte dati autorizzata) che conservi eventi di mercato, non soltanto pronostici:

- `fixture_id`, `league_id`, `kickoff_at`, `home_team_id`, `away_team_id`;
- `bookmaker_id`, `market_type`, `outcome`, `line` (ove previsto), `decimal_odd`;
- `quoted_at`, `source`, `captured_at`, `is_opening`, `is_closing`, `quote_status`;
- risultati finali realmente verificati, momento di risoluzione, normalizzazione e fonte;
- versione schema, consenso e policy di ritenzione; niente credenziali/client IDs nel dataset analitico.

**Campionamento**: salva serie temporali con cadence controllata e budget richieste, preferendo un feed storico lecito anziché chiamare ogni quota per ogni partita. Evitare duplicati con chiave (fixture, bookmaker, mercato, esito, linea, quoted_at). Non unire quote di apertura e chiusura senza distinguere il tempo.

## Ipotesi “falsa favorita nelle multiple”

Calcolare in modo PRE-REGISTRATO, separando i campionati, le fasce quote, il mercato e il periodo:
1. frequenza osservata di sconfitta delle favorite con quote basse, confrontata con probabilità bookmaker *de-vig* e con modelli sportivi prepartita;
2. probabilità di almeno un errore nelle multiple da 3, 5, 10 e 15 eventi, con partite/campionati distinti e stimando dipendenza fra eventi;
3. stabilità del fenomeno in più stagioni, più bookmaker e nel tempo (apertura vs chiusura);
4. analisi fuori campione temporale e intervalli di confidenza; tenere separato il training dal periodo valutato e non selezionare a posteriori solo le multiple perdenti.

Anomalie ripetute NON dimostrano intenzionalità di manipolazione: possono avere spiegazioni alternative (margine, errori di stima, scelta delle partite, varianza, favorite–longshot bias).

## Licenza sorgenti

`football-data.co.uk` offre dati storici di partite e quote ma **specifica che i dati sono per uso privato, non per prodotti commerciali o training AI/bot**. Non ingestire automaticamente quel dataset nell'app senza una licenza adeguata. Verificare copertura e termini di qualsiasi altro provider. 

## Regola di sicurezza e prodotto

Nessun sistema deve rendere una selezione “96% certa” sulla base di un campione ridotto. L'eventuale futuro `QuoteLab calibrated outcome` richiede almeno un holdout cronologico con Brier e calibrazione migliori di un baseline semplice, e deve essere visualizzato come **terzo punto di vista**, mai come manipolazione nascosta delle probabilità di SmartBet o Diego. In assenza di segnali robusti: **dati insufficienti / sconsigliata**, non un pronostico inventato.
