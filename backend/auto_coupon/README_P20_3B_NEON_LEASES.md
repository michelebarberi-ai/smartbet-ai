# GoalVdLine Build 45 — P20.3B: Neon lease e recupero dei job

**Ambito**: questa patch rafforza la tabella `sb_auto_coupon_daily_runs_v1` già
presente. Non modifica i pronostici, le quote, i modelli Flutter, le preferenze
3–15 eventi, le tre varianti o le notifiche APNs.

## Comportamento

- Ogni `(subject_hash, local_day)` ha **una sola riga** in Neon (vincolo di
  chiave primaria preesistente).
- `claimAutoCouponRun` può prendere un giorno nuovo, un `retry` arrivato a
  scadenza o un `processing` con lease scaduta. Non modifica `ready`.
- Ogni tentativo riceve una UUID (`lease_token`) nuova e mantiene il numero
  progressivo di tentativi (`attempts`, massimo cinque).
- Durante il calcolo del motore Flutter, il coordinatore rinnova la lease ogni
  60 secondi. La lease in Neon dura tre minuti. Gli orari della lease usano
  l'orologio del database (`clock_timestamp()`).
- Un tentativo scaduto o sostituito non può più eseguire il salvataggio finale,
  neppure se il motore Flutter restituisce una schedina valida dopo il timeout.
- Con consenso `requested=false` o preferenze cancellate, il rinnovo e il
  salvataggio vengono rifiutati dal database.
- Un tentativo `processing` scaduto dopo il quinto tentativo viene marcato
  `unavailable` alla successiva scansione batch.
- I record già `ready` e le notifiche non vengono cancellati dalle migrazioni.

## Migrazione database

`backend/learning/learning_schema.sql` aggiunge in modo idempotente:

- `lease_token UUID`
- `lease_expires_at TIMESTAMPTZ`
- indice parziale sui processi `processing`

Il repository esegue questo schema durante `initialize()`. La connessione
utilizzata in Render deve avere i permessi DDL necessari. **Non eseguire SQL
manualmente senza verificare la configurazione Neon e senza backup.** Le righe
`processing` precedenti alla migrazione (con lease nulla) diventano reclamabili
dopo 15 minuti dal loro `updated_at`; le righe `ready` restano immutate.

## Cosa NON fa ancora questa patch

- Non abilita la generazione automatica né il worker, che restano vincolati ai
  feature flag e all'autenticazione esistenti.
- Non crea un cron/scheduler esterno, né distribuisce il runner Flutter su Render.
- Non rende asincrona la route `worker/run`: essa attende ancora il motore e
  può incontrare timeout HTTP su chiamate molto lunghe. La fase successiva deve
  spezzare il lavoro in avvio/poll/commit con ticket persistito in Neon o usare
  un worker dedicato con un trigger idoneo.
- Non riattacca il processo Flutter interrotto: alla scadenza della lease, un
  nuovo tentativo può ricominciare la generazione con il motore originale.
- Il vincolo garantisce **un solo risultato `ready` pubblicato per
  dispositivo/giorno**, non l'assenza assoluta di chiamate duplicate al motore
  durante crash o lunghi blocchi di rete.

## Collaudo

Eseguire prima i test mirati e poi quelli backend completi nel repository reale:

```bash
node --test backend/test/auto_coupon_neon_lease.test.js \
  backend/test/auto_coupon_generation_coordinator.test.js \
  backend/test/auto_coupon_three_variants.test.js \
  backend/test/auto_coupon_worker_route.test.js

node --test backend/test/auto_coupon_*.test.js \
  backend/test/learning_mobile_auth.test.js \
  backend/test/learning_retrospective.test.js \
  backend/test/learning_routes.test.js

git diff --check
```

I test SQL della patch usano un `pool.query()` fittizio e verificano i vincoli
SQL e il comportamento dei coordinator mock; **non sono un test di connessione
live o una migrazione realmente eseguita su Neon**. Prima di attivare i feature
flag servono una migrazione su staging Neon, un test di concorrenza con due
processi indipendenti e una prova di recupero dopo crash reale.
