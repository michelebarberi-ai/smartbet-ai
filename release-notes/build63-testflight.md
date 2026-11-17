# GoalVdLine Build 63 — TestFlight release authorization

Versione: 1.2.5+63
QA source: c374f889f0319ecd92eff4154d826e118158d9ab
QA workflow: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43992265837
Stato QA: superati analisi statica, test Flutter completi, smoke tests B63 e controllo sintassi backend.

La pipeline iOS esegue nuovamente analisi statica e suite completa prima di firmare o caricare TestFlight.

Ambito: calendario sportivo globale, Palinsesto Italia nel filtro quote finale, tre cervelli diagnostici, recupero SmartCore locale e nuove schermate Schedina/Combinazioni.

Limitazioni note: il nuovo endpoint backend per il catalogo leghe non è ancora distribuito su Render; l'analisi SmartBet remota richiede diagnostica in produzione. La sola presenza di un marchio nel feed quote non certifica disponibilità nella versione italiana del bookmaker.
Nessuna migrazione Neon o modifica al piano Render.
