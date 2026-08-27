require("dotenv").config();

const express = require("express");
const cors = require("cors");
const OpenAI = require("openai");

const app = express();

app.use(cors());
app.use(express.json({ limit: "2mb" }));

// ============================================================
// OPENAI
// ============================================================

const apiKey = process.env.OPENAI_API_KEY;

if (!apiKey) {
  console.error("ERRORE: OPENAI_API_KEY non trovata.");
  process.exit(1);
}

const client = new OpenAI({
  apiKey,
});

const PORT = process.env.PORT || 3000;

// ============================================================
// PRE-MATCH FILTER
// ============================================================

function getMatchStatus(matchDate) {
  if (!matchDate) {
    return "UNKNOWN";
  }

  const date = new Date(matchDate);

  if (Number.isNaN(date.getTime())) {
    return "UNKNOWN";
  }

  const now = new Date();

  if (date.getTime() > now.getTime()) {
    return "UPCOMING";
  }

  return "FINISHED_OR_LIVE";
}

// ============================================================
// REGOLE PRE-MATCH
// ============================================================

function buildPreMatchRules(matchDate) {
  if (!matchDate) {
    return `
============================================================
PROTEZIONE PRE-MATCH
============================================================

La data della partita non è disponibile.

Non utilizzare informazioni che possano rivelare
direttamente o indirettamente il risultato della partita.

============================================================
`;
  }

  return `
============================================================
PROTEZIONE PRE-MATCH OBBLIGATORIA
============================================================

DATA/ORA PARTITA:
${matchDate}

Devi effettuare una vera analisi PRE-PARTITA.

Utilizza esclusivamente informazioni che sarebbero
state disponibili PRIMA dell'inizio della partita.

NON UTILIZZARE MAI:

- risultato finale;
- risultato parziale;
- marcatori;
- assist;
- tabellino;
- cronaca della partita;
- statistiche prodotte durante o dopo la partita;
- articoli post-partita;
- interviste post-partita;
- commenti successivi alla gara;
- qualsiasi informazione che riveli l'esito.

Se la ricerca web mostra il risultato della partita,
IGNORALO COMPLETAMENTE.

Se trovi una fonte pubblicata dopo il calcio d'inizio,
NON utilizzarla per la previsione.

Devi ragionare come se ti trovassi immediatamente
prima dell'inizio della partita.

============================================================
`;
}

// ============================================================
// HEALTH CHECK
// ============================================================

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "SmartBet AI Backend",
    dossierMode: true,
    preMatchFilter: true,
    currentLeagueProtection: true,
    valueBetMode: "dart-mathematical",
  });
});

// ============================================================
// API-FOOTBALL PROXY + CACHE CENTRALIZZATA
// ============================================================

const footballApiKey = process.env.FOOTBALL_API_KEY;
const footballApiBaseUrl = "https://v3.football.api-sports.io";

// Cache condivisa da tutti gli utenti che raggiungono
// questa istanza del backend.
const footballCache = new Map();

// Evita che 20 richieste simultanee per la stessa risorsa
// provochino 20 chiamate ad API-Football.
const footballInFlight = new Map();

const FIXTURES_TTL_MS = 15 * 60 * 1000;
const ODDS_TTL_MS = 5 * 60 * 1000;

function getFootballCache(key) {
  const cached = footballCache.get(key);

  if (!cached) {
    return null;
  }

  if (Date.now() >= cached.expiresAt) {
    footballCache.delete(key);
    return null;
  }

  return cached.data;
}

function setFootballCache(key, data, ttlMs) {
  footballCache.set(key, {
    data,
    expiresAt: Date.now() + ttlMs,
  });
}

async function requestApiFootball({
  path,
  query,
  ttlMs,
}) {
  if (!footballApiKey) {
    const error = new Error(
      "FOOTBALL_API_KEY non configurata sul backend.",
    );
    error.statusCode = 503;
    throw error;
  }

  const params = new URLSearchParams();

  for (const [key, value] of Object.entries(query)) {
    if (
      value !== undefined &&
      value !== null &&
      String(value).trim() !== ""
    ) {
      params.set(key, String(value));
    }
  }

  const cacheKey = `${path}?${params.toString()}`;

  const cached = getFootballCache(cacheKey);

  if (cached !== null) {
    console.log(
      `[API-FOOTBALL CACHE HIT] ${cacheKey}`,
    );

    return {
      data: cached,
      cache: "HIT",
    };
  }

  const existingRequest =
    footballInFlight.get(cacheKey);

  if (existingRequest) {
    console.log(
      `[API-FOOTBALL SINGLE-FLIGHT] ${cacheKey}`,
    );

    const data = await existingRequest;

    return {
      data,
      cache: "SHARED",
    };
  }

  const requestPromise = (async () => {
    const url =
      `${footballApiBaseUrl}${path}` +
      `?${params.toString()}`;

    console.log(
      `[API-FOOTBALL REQUEST] ${cacheKey}`,
    );

    const response = await fetch(url, {
      headers: {
        "x-apisports-key": footballApiKey,
      },
    });

    const text = await response.text();

    let data;

    try {
      data = JSON.parse(text);
    } catch (_) {
      const error = new Error(
        `Risposta API-Football non valida (${response.status}).`,
      );
      error.statusCode = 502;
      throw error;
    }

    if (!response.ok) {
      const error = new Error(
        `API-Football HTTP ${response.status}`,
      );
      error.statusCode = 502;
      error.apiResponse = data;
      throw error;
    }

    if (
      data &&
      data.errors &&
      typeof data.errors === "object" &&
      Object.keys(data.errors).length > 0
    ) {
      const error = new Error(
        "API-Football ha restituito un errore.",
      );
      error.statusCode = 502;
      error.apiResponse = data;
      throw error;
    }

    setFootballCache(
      cacheKey,
      data,
      ttlMs,
    );

    return data;
  })();

  footballInFlight.set(
    cacheKey,
    requestPromise,
  );

  try {
    const data = await requestPromise;

    return {
      data,
      cache: "MISS",
    };
  } finally {
    footballInFlight.delete(cacheKey);
  }
}

// ------------------------------------------------------------
// FIXTURES
// ------------------------------------------------------------

app.get("/football/fixtures", async (req, res) => {
  try {
    const date =
      String(req.query.date || "").trim();

    const timezone =
      String(
        req.query.timezone || "Europe/Rome",
      ).trim();

    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(date)
    ) {
      return res.status(400).json({
        success: false,
        error:
          "Parametro date obbligatorio nel formato YYYY-MM-DD.",
      });
    }

    const result =
      await requestApiFootball({
        path: "/fixtures",
        query: {
          date,
          timezone,
        },
        ttlMs: FIXTURES_TTL_MS,
      });

    res.set(
      "X-SmartBet-Cache",
      result.cache,
    );

    return res.json(result.data);
  } catch (error) {
    console.error(
      "SMARTBET FOOTBALL FIXTURES ERROR:",
      error,
    );

    return res
      .status(error.statusCode || 500)
      .json({
        success: false,
        error:
          error.message ||
          "Errore caricamento fixtures.",
        apiResponse:
          error.apiResponse || undefined,
      });
  }
});

// ------------------------------------------------------------
// ODDS
// ------------------------------------------------------------

app.get("/football/odds", async (req, res) => {
  try {
    const fixture =
      Number(req.query.fixture);

    if (
      !Number.isInteger(fixture) ||
      fixture <= 0
    ) {
      return res.status(400).json({
        success: false,
        error:
          "Parametro fixture non valido.",
      });
    }

    const result =
      await requestApiFootball({
        path: "/odds",
        query: {
          fixture,
        },
        ttlMs: ODDS_TTL_MS,
      });

    res.set(
      "X-SmartBet-Cache",
      result.cache,
    );

    return res.json(result.data);
  } catch (error) {
    console.error(
      "SMARTBET FOOTBALL ODDS ERROR:",
      error,
    );

    return res
      .status(error.statusCode || 500)
      .json({
        success: false,
        error:
          error.message ||
          "Errore caricamento quote.",
        apiResponse:
          error.apiResponse || undefined,
      });
  }
});

// ============================================================
// ANALISI AI
// ============================================================

app.post("/analyze", async (req, res) => {
  try {
    const {
      homeTeam,
      awayTeam,
      matchDate,
      dossier,
      meta,
      statistics,
    } = req.body;

    // ==========================================================
    // CONTROLLO BASE
    // ==========================================================

    if (!homeTeam || !awayTeam) {
      return res.status(400).json({
        success: false,
        error: "homeTeam e awayTeam sono obbligatori",
      });
    }

    // ==========================================================
    // DOSSIER
    // ==========================================================

    const smartBetData =
      dossier ||
      statistics ||
      {};

    const usingDossier =
      dossier &&
      typeof dossier === "object";

    // ==========================================================
    // MATCH STATUS
    // ==========================================================

    const matchStatus =
      getMatchStatus(matchDate);

    console.log("");
    console.log("========================================");
    console.log("SMARTBET AI - NUOVA ANALISI");
    console.log("========================================");

    console.log(
      `Partita: ${homeTeam} - ${awayTeam}`
    );

    console.log(
      `Data: ${matchDate || "non disponibile"}`
    );

    console.log(
      `Match status: ${matchStatus}`
    );

    console.log(
      `Dossier mode: ${usingDossier}`
    );

    // ==========================================================
    // DEBUG DOSSIER
    // ==========================================================

    if (usingDossier) {
      console.log(
        `Dossier confidence: ${
          dossier?.dataQuality?.confidence ??
          "N/D"
        }%`
      );

      console.log(
        `Pre-match only: ${
          dossier?.dataQuality?.preMatchOnly ??
          "N/D"
        }`
      );

      console.log(
        `Forma casa: ${
          dossier?.homeTeam?.form?.count ??
          0
        }`
      );

      console.log(
        `Forma ospite: ${
          dossier?.awayTeam?.form?.count ??
          0
        }`
      );

      console.log(
        `H2H: ${
          dossier?.context?.headToHead?.length ??
          0
        }`
      );

      console.log(
        `Campionato attuale casa: ${
          dossier
            ?.homeTeam
            ?.currentCompetition
            ?.leagueName ??
          "N/D"
        }`
      );

      console.log(
        `Fonte statistiche casa: ${
          dossier
            ?.homeTeam
            ?.statisticsSource
            ?.leagueName ??
          "N/D"
        }`
      );

      console.log(
        `Campionato attuale ospite: ${
          dossier
            ?.awayTeam
            ?.currentCompetition
            ?.leagueName ??
          "N/D"
        }`
      );

      console.log(
        `Fonte statistiche ospite: ${
          dossier
            ?.awayTeam
            ?.statisticsSource
            ?.leagueName ??
          "N/D"
        }`
      );
    }

    console.log("========================================");

    // ==========================================================
    // BLOCCO PARTITE INIZIATE / CONCLUSE
    // ==========================================================

    if (matchStatus === "FINISHED_OR_LIVE") {
      return res.status(400).json({
        success: false,
        error:
          "Analisi predittiva bloccata: la partita risulta già iniziata o conclusa.",
        matchStatus,
        preMatchProtected: true,
      });
    }

    // ==========================================================
    // DESCRIZIONE PARTITA
    // ==========================================================

    const matchDescription = `
============================================================
PARTITA
============================================================

Casa:
${homeTeam}

Ospite:
${awayTeam}

Data:
${matchDate || "Non disponibile"}

META PARTITA:
${JSON.stringify(meta || {}, null, 2)}

============================================================
MATCH DOSSIER SMARTBET
============================================================

${JSON.stringify(smartBetData, null, 2)}

============================================================
`;

    // ==========================================================
    // OPENAI
    // ==========================================================

    const response =
      await client.responses.create({
        model: "gpt-5.1",

        tools: [
          {
            type: "web_search",
            search_context_size: "medium",
          },
        ],

        input: [
          {
            role: "system",

            content: `
Sei SmartBet AI.

Sei un analista professionale specializzato
nell'analisi PRE-PARTITA delle partite di calcio.

${buildPreMatchRules(matchDate)}

============================================================
GERARCHIA DELLE INFORMAZIONI
============================================================

Utilizza le informazioni secondo questa gerarchia
OBBLIGATORIA:

1. Fixture confermata dal Match Dossier SmartBet
2. Competizione della partita
3. Campionato ATTUALE delle squadre
4. Statistiche quantitative SmartBet / API-Football + controllo football-data.org
5. Forma recente
6. Rendimento casa/trasferta
7. Head-to-head
8. Ricerca web per contesto e notizie pre-match
9. Contesto generale

I seguenti dati SmartBet sono AUTORITATIVI:

- squadra casa;
- squadra ospite;
- fixture ID;
- team ID;
- data;
- competizione;
- currentCompetition.

Il web NON può sostituire questi dati.

============================================================

CONTROLLO MULTI-SOURCE SMARTBET

============================================================

SmartBet può utilizzare più fonti indipendenti.

FONTE STRUTTURATA PRINCIPALE:
API-Football / statistiche SmartBet.

FONTE STRUTTURATA SECONDARIA:
football-data.org, quando disponibile.

Nel Match Dossier i dati della fonte secondaria possono
comparire nel campo marketInformation.

Le informazioni che citano:

- football-data.org;
- Fonte secondaria;
- Classifica casa fonte secondaria;
- Classifica ospite fonte secondaria;

sono DATI STATISTICI DI CONTROLLO.
NON sono quote bookmaker.

Prima di produrre le probabilità 1/X/2 confronta
le informazioni delle fonti disponibili.

SE LE FONTI CONCORDANO:

- considera il quadro statistico più robusto;
- mantieni una confidence coerente con la qualità dei dati;
- non aumentare automaticamente la confidence soltanto
  perché esiste una seconda fonte.

SE LE FONTI SONO IN CONFLITTO:

- verifica stagione e competizione;
- per fixture, squadre, data e competizione mantieni
  autoritativo il Match Dossier SmartBet;
- per le statistiche privilegia il dato più recente,
  pertinente e correttamente contestualizzato;
- segnala l'incertezza;
- riduci la confidence se il conflitto è significativo;
- non inventare una riconciliazione.

Se football-data.org non è disponibile:

- non considerarlo un errore;
- non penalizzare automaticamente la partita;
- continua con API-Football, dossier e ricerca web.

============================================================

SEPARAZIONE PROBABILITA / QUOTE

============================================================

Le quote dei bookmaker NON devono determinare
le probabilità 1/X/2.

Calcola PRIMA le probabilità utilizzando:

DATI STATISTICI
+
FORMA
+
CONTESTO
+
CONTROLLO MULTI-SOURCE
+
NOTIZIE PRE-MATCH
+
INCERTEZZA

Durante il calcolo delle probabilità IGNORA:

- quote bookmaker;
- probabilità implicite delle quote;
- consenso del mercato;
- tipster;
- pronostici dei siti di scommesse;
- movimenti delle quote.

Solo DOPO avere determinato le probabilità 1/X/2,
le quote possono essere utilizzate per valutare
l'eventuale Value Betting.

NON modificare retroattivamente le probabilità
per avvicinarle alle quote di mercato.

============================================================
CURRENT COMPETITION VS STATISTICS SOURCE
============================================================

currentCompetition indica il campionato ATTUALE
della squadra.

statisticsSource indica ESCLUSIVAMENTE il campionato
e la stagione da cui provengono le statistiche.

Esempio:

currentCompetition:
Serie B 2026

statisticsSource:
Serie C - Girone B 2025

INTERPRETAZIONE CORRETTA:

La squadra gioca ATTUALMENTE in Serie B.

Le statistiche utilizzate provengono dalla precedente
stagione disputata in Serie C.

NON descrivere la squadra come squadra attuale
di Serie C.

============================================================
REGOLA RIGIDA SULLE PROMOZIONI
============================================================

Per il calcio italiano:

Serie A = categoria 1
Serie B = categoria 2
Serie C = categoria 3

Il passaggio:

Serie C -> Serie B

è UNA promozione di categoria.

È vietato descriverlo come:

- salto di due categorie;
- promozione di due categorie;
- salto di due livelli;
- salita di due livelli.

La formulazione corretta è:

"promossa dalla Serie C alla Serie B"

oppure:

"neopromossa in Serie B dalla Serie C".

Serie B -> Serie A
è UNA promozione.

Serie C -> Serie A
rappresenterebbe invece una differenza di DUE categorie.

============================================================
CONFRONTO TRA LE SQUADRE
============================================================

ATTENZIONE:

Se:

Cagliari currentCompetition = Serie A

Arezzo currentCompetition = Serie B

il confronto ATTUALE è:

SERIE A vs SERIE B.

NON:

SERIE A vs SERIE C.

È consentito dire che le statistiche storiche
dell'Arezzo provengono dalla Serie C.

È consentito dire che quei numeri sono stati ottenuti
contro avversari di livello inferiore.

NON è consentito trasformare la Serie C storica
nella categoria attuale dell'Arezzo.

============================================================
DIFFERENZA TRA CATEGORIA ATTUALE E CAMPIONE STORICO
============================================================

Puoi spiegare:

"Cagliari è attualmente in Serie A, mentre Arezzo
è attualmente in Serie B. Le statistiche storiche
dell'Arezzo derivano dalla precedente stagione
in Serie C."

NON scrivere:

"il salto di due livelli dell'Arezzo"

perché l'Arezzo è passato dalla Serie C alla Serie B,
quindi ha effettuato UNA promozione.

Se confronti:

Serie A attuale del Cagliari

con

Serie C storica del campione statistico Arezzo

devi esplicitare che stai confrontando livelli
di campioni statistici differenti e NON categorie
attuali delle due squadre.

============================================================
DATI STORICI
============================================================

Quando statisticsSource è precedente rispetto
alla stagione corrente:

- usa comunque i dati;
- riduci il loro peso;
- considera il cambio di categoria;
- considera cambi rosa;
- considera cambi allenatore;
- considera il diverso livello degli avversari;
- riduci la confidence se necessario.

============================================================
COMPETIZIONE DELLA PARTITA
============================================================

La competizione della fixture e il campionato
della squadra sono due concetti differenti.

Esempio:

fixture:
Coppa Italia

home currentCompetition:
Serie A

away currentCompetition:
Serie B

significa:

partita di Coppa Italia tra una squadra
di Serie A e una squadra di Serie B.

============================================================
RICERCA WEB
============================================================

Usa la ricerca web per:

- infortuni;
- squalifiche;
- probabili formazioni;
- allenatori;
- mercato;
- trasferimenti;
- motivazioni;
- calendario;
- situazione societaria;
- notizie pre-partita.

Privilegia:

1. club ufficiali;
2. lega/federazione;
3. competizione ufficiale;
4. fonti giornalistiche affidabili.

Il web NON può sovrascrivere:

- fixture;
- squadre;
- data;
- competizione;
- currentCompetition.

============================================================
ANTI-HALLUCINATION
============================================================

NON inventare informazioni.

Se un dato non è verificabile:

scrivi "Non disponibile".

Se fonti web entrano in conflitto:

- privilegia quella più autorevole;
- segnala l'incertezza;
- riduci la confidence.

Se una fonte web entra in conflitto con
il Match Dossier SmartBet:

MANTIENI IL DATO SMARTBET.

============================================================
PROBABILITÀ
============================================================

Devi restituire:

- probabilità 1;
- probabilità X;
- probabilità 2.

Le tre probabilità devono sommare
ESATTAMENTE a 100.

prediction deve corrispondere
alla probabilità più alta.

NON utilizzare percentuali differenti
nel testo rispetto ai campi numerici.

============================================================
CONFIDENCE
============================================================

La confidence rappresenta la qualità
dell'analisi e NON la probabilità di vittoria.

Riducila quando:

- statistiche vecchie;
- assenze sconosciute;
- lineup sconosciute;
- squadra neopromossa;
- cambio rosa;
- cambio allenatore;
- inizio stagione;
- contesto molto volatile;
- dati contraddittori.

Considera anche:

dataQuality.confidence

presente nel Match Dossier.

============================================================
VALUE BET
============================================================

NON devi calcolare la Value Bet.

Il motore matematico Dart calcola la Value Bet usando:

- quote reali;
- probabilità implicite;
- overround;
- probabilità fair;
- probabilità AI;
- edge;
- expected value.

NON inventare quote.

NON utilizzare quote trovate sul web
per dichiarare value.

Per compatibilità JSON restituisci SEMPRE:

valueBet = "NO"

Il valore verrà sostituito dal motore Dart.

============================================================
STILE
============================================================

summary:
massimo 4 frasi.

statisticalAnalysis:
massimo 5 punti.

newsAnalysis:
massimo 5 punti.

positiveFactors:
massimo 5.

negativeFactors:
massimo 5.

keyAbsences:
massimo 5.

finalVerdict:
massimo 4 frasi.

============================================================
OBIETTIVO
============================================================

Produci una valutazione probabilistica basata su:

DATI
+
FORMA
+
CONTESTO
+
WEB
+
INCERTEZZA

Non devi cercare di "indovinare" il risultato.

============================================================
`,
          },

          {
            role: "user",

            content: `
Analizza la partita seguente.

${matchDescription}

Utilizza prima il Match Dossier SmartBet.

Ricorda:

currentCompetition = categoria attuale.

statisticsSource = fonte delle statistiche storiche.

Non confondere le due informazioni.

Se una squadra passa da Serie C a Serie B,
si tratta di UNA promozione di categoria.

Non usare mai l'espressione
"salto di due livelli"
per descrivere Serie C -> Serie B.

Usa il web soltanto per integrare il dossier.

Rispetta rigorosamente la protezione pre-match.

NON calcolare la Value Bet.

Restituisci:

valueBet = "NO"

Produci infine la valutazione probabilistica.
`,
          },
        ],

        // ======================================================
        // STRUCTURED OUTPUT
        // ======================================================

        text: {
          format: {
            type: "json_schema",

            name:
              "smartbet_match_analysis",

            strict: true,

            schema: {
              type: "object",

              properties: {
                prediction: {
                  type: "string",
                  enum: [
                    "1",
                    "X",
                    "2",
                  ],
                },

                homeProbability: {
                  type: "integer",
                  minimum: 0,
                  maximum: 100,
                },

                drawProbability: {
                  type: "integer",
                  minimum: 0,
                  maximum: 100,
                },

                awayProbability: {
                  type: "integer",
                  minimum: 0,
                  maximum: 100,
                },

                confidence: {
                  type: "integer",
                  minimum: 0,
                  maximum: 100,
                },

                risk: {
                  type: "string",
                },

                summary: {
                  type: "string",
                },

                statisticalAnalysis: {
                  type: "string",
                },

                newsAnalysis: {
                  type: "string",
                },

                positiveFactors: {
                  type: "array",
                  maxItems: 5,
                  items: {
                    type: "string",
                  },
                },

                negativeFactors: {
                  type: "array",
                  maxItems: 5,
                  items: {
                    type: "string",
                  },
                },

                keyAbsences: {
                  type: "array",
                  maxItems: 5,
                  items: {
                    type: "string",
                  },
                },

                valueBet: {
                  type: "string",
                },

                finalVerdict: {
                  type: "string",
                },
              },

              required: [
                "prediction",
                "homeProbability",
                "drawProbability",
                "awayProbability",
                "confidence",
                "risk",
                "summary",
                "statisticalAnalysis",
                "newsAnalysis",
                "positiveFactors",
                "negativeFactors",
                "keyAbsences",
                "valueBet",
                "finalVerdict",
              ],

              additionalProperties:
                false,
            },
          },
        },

        max_output_tokens:
          5000,
      });

    // ==========================================================
    // OUTPUT AI
    // ==========================================================

    const rawText =
      response.output_text;

    console.log("");

    console.log(
      "RISPOSTA AI RICEVUTA"
    );

    console.log(
      `Lunghezza: ${rawText.length}`
    );

    let analysis;

    try {
      analysis =
        JSON.parse(rawText);
    } catch (error) {
      console.error("");
      console.error(
        "========================================"
      );
      console.error(
        "ERRORE JSON AI"
      );
      console.error(
        "========================================"
      );

      console.error(rawText);

      return res.status(500).json({
        success: false,
        error:
          "Risposta AI non valida",
        raw: rawText,
      });
    }

    // ==========================================================
    // CONTROLLO PROBABILITÀ
    // ==========================================================

    const probabilityTotal =
      analysis.homeProbability +
      analysis.drawProbability +
      analysis.awayProbability;

    if (probabilityTotal !== 100) {
      console.warn(
        `SMARTBET WARNING: probabilità = ${probabilityTotal}%`
      );

      return res.status(500).json({
        success: false,
        error:
          "Le probabilità AI non sommano a 100.",
        analysis,
      });
    }

    // ==========================================================
    // CONTROLLO PRONOSTICO
    // ==========================================================

    const probabilities = {
      "1":
        analysis.homeProbability,

      "X":
        analysis.drawProbability,

      "2":
        analysis.awayProbability,
    };

    const expectedPrediction =
      Object.entries(
        probabilities
      )
        .sort(
          (a, b) =>
            b[1] - a[1]
        )[0][0];

    if (
      analysis.prediction !==
      expectedPrediction
    ) {
      console.warn(
        "SMARTBET WARNING: pronostico AI incoerente."
      );

      analysis.prediction =
        expectedPrediction;
    }

    // ==========================================================
    // VALUE BET
    // ==========================================================

    // L'AI non decide la Value Bet.
    // Verrà sostituita dal motore Dart.

    analysis.valueBet = "NO";

    // ==========================================================
    // LOG
    // ==========================================================

    console.log("");
    console.log(
      "========================================"
    );
    console.log(
      "SMARTBET AI - RISULTATO"
    );
    console.log(
      "========================================"
    );

    console.log(
      `1: ${analysis.homeProbability}%`
    );

    console.log(
      `X: ${analysis.drawProbability}%`
    );

    console.log(
      `2: ${analysis.awayProbability}%`
    );

    console.log(
      `Pronostico: ${analysis.prediction}`
    );

    console.log(
      `Confidence: ${analysis.confidence}%`
    );

    console.log(
      `Risk: ${analysis.risk}`
    );

    console.log(
      "Value Bet AI: DELEGATA AL MOTORE DART"
    );

    console.log(
      "========================================"
    );

    // ==========================================================
    // RISPOSTA FLUTTER
    // ==========================================================

    return res.json({
      success: true,

      analysis,

      meta: {
        matchStatus,

        preMatchProtected:
          true,

        dossierMode:
          usingDossier,

        dossierConfidence:
          dossier
            ?.dataQuality
            ?.confidence ??
          null,

        matchDate:
          matchDate ||
          null,

        currentLeagueProtection:
          true,

        categoryPromotionProtection:
          true,

        valueBetMode:
          "dart-mathematical",
      },
    });
  } catch (error) {
    console.error("");
    console.error(
      "========================================"
    );
    console.error(
      "SMARTBET AI ERROR"
    );
    console.error(
      "========================================"
    );

    console.error(error);

    return res.status(500).json({
      success: false,

      error:
        error.message ||
        "Errore AI",
    });
  }
});

// ============================================================
// SERVER
// ============================================================

app.listen(PORT, () => {
  console.log("");

  console.log(
    "========================================"
  );

  console.log(
    "SMARTBET AI BACKEND"
  );

  console.log(
    "========================================"
  );

  console.log(
    `Server: http://localhost:${PORT}`
  );

  console.log(
    "Status: ONLINE"
  );

  console.log(
    "Match Dossier: ENABLED"
  );

  console.log(
    "Pre-Match Filter: ENABLED"
  );

  console.log(
    "Web Search: ENABLED"
  );

  console.log(
    "Current League Protection: ENABLED"
  );

  console.log(
    "Promotion Level Protection: ENABLED"
  );

  console.log(
    "Value Bet Engine: DART"
  );

  console.log(
    "========================================"
  );

  console.log("");
});