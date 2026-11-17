# GoalVdLine Build 65 — Autorizzazione TestFlight

La Build 65 mantiene il motore sportivo della Build 64 e corregge due problemi emersi dai test su iPhone:

- ricerca delle quote su feed internazionale/multi-bookmaker come opzione predefinita; il filtro "Palinsesto Italia" resta disponibile manualmente;
- messaggi più precisi per le previsioni AI non confermate come mercati quotati e per le verifiche incomplete;
- nessuna quota inventata e soglia strettamente superiore a 1,20 invariata.

## Quality gates

- GitHub Action B65: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44106583406 — success.
- Backend syntax e regression: success.
- Flutter analyze: success.
- Flutter full regression: success.
- Market/bookmaker targeted tests: success.
- La pipeline TestFlight riesegue backend, analyzer e test Flutter prima della firma e dell'upload.
- Nessun servizio Render/Neon a pagamento attivato.

## Pubblicazione

Autorizzazione una tantum tramite commit con messaggio esatto.
