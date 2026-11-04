'use strict';

const crypto = require('node:crypto');

const MAX_BATCH = 20;
const MAX_MARKET = 64;
const MIN_KICKOFF_LEAD_MS = 2 * 60 * 1000;
const MAX_KICKOFF_AHEAD_MS = 60 * 24 * 60 * 60 * 1000;

function normalizeMarket(value) {
  if (typeof value !== 'string') return '';
  return value.trim().toUpperCase().replace(/\s+/g, ' ');
}

function isSupportedMarket(input) {
  const market = normalizeMarket(input);
  if (!market || market.length > MAX_MARKET) return false;
  if (['1', 'X', '2', '1X', 'X2', '12', 'GOAL', 'NO GOAL', 'CASA SEGNA', 'OSPITE SEGNA',
       'CASA 2+ GOL', 'OSPITE 2+ GOL', 'CASA 3+ GOL', 'OSPITE 3+ GOL',
       'CASA ALMENO 2 GOL', 'OSPITE ALMENO 2 GOL',
       'CASA ALMENO 3 GOL', 'OSPITE ALMENO 3 GOL'].includes(market)) return true;

  const parts = market.split(/\s+\+\s+/);
  if (parts.length > 1) {
    return parts.length <= 3 && parts.every((part) => {
      const abbreviated = part.replace(/^O(\d+(?:\.\d+)?)$/, 'OVER $1')
        .replace(/^U(\d+(?:\.\d+)?)$/, 'UNDER $1');
      return isSupportedMarket(abbreviated);
    });
  }

  const ou = /^(OVER|UNDER) (\d+(?:\.\d+)?)$/.exec(market);
  if (ou) {
    const line = Number(ou[2]);
    return line >= 0.5 && line <= 6.5 && Number.isInteger(line * 2) && !Number.isInteger(line);
  }
  const multi = /^MULTIGOL (\d+)-(\d+)$/.exec(market);
  if (multi) {
    const low = Number(multi[1]);
    const high = Number(multi[2]);
    return low >= 0 && high <= 12 && low <= high;
  }
  const euro = /^HCP EURO CASA ([+-]?\d+) ([1X2])$/.exec(market);
  return !!euro && Math.abs(Number(euro[1])) <= 5;
}

function settleMarket(input, home, away) {
  if (!Number.isInteger(home) || !Number.isInteger(away) || home < 0 || away < 0 ||
      !isSupportedMarket(input)) return null;
  const market = normalizeMarket(input);
  const parts = market.split(/\s+\+\s+/);
  if (parts.length > 1) {
    return parts.every((part) => settleMarket(part.replace(/^O(\d+(?:\.\d+)?)$/, 'OVER $1')
      .replace(/^U(\d+(?:\.\d+)?)$/, 'UNDER $1'), home, away));
  }
  switch (market) {
    case '1': return home > away;
    case 'X': return home === away;
    case '2': return away > home;
    case '1X': return home >= away;
    case 'X2': return away >= home;
    case '12': return home !== away;
    case 'GOAL': return home > 0 && away > 0;
    case 'NO GOAL': return home === 0 || away === 0;
    case 'CASA SEGNA': return home >= 1;
    case 'OSPITE SEGNA': return away >= 1;
    case 'CASA 2+ GOL':
    case 'CASA ALMENO 2 GOL': return home >= 2;
    case 'OSPITE 2+ GOL':
    case 'OSPITE ALMENO 2 GOL': return away >= 2;
    case 'CASA 3+ GOL':
    case 'CASA ALMENO 3 GOL': return home >= 3;
    case 'OSPITE 3+ GOL':
    case 'OSPITE ALMENO 3 GOL': return away >= 3;
  }
  const ou = /^(OVER|UNDER) (\d+(?:\.\d+)?)$/.exec(market);
  if (ou) return ou[1] === 'OVER' ? home + away > Number(ou[2]) : home + away < Number(ou[2]);
  const multi = /^MULTIGOL (\d+)-(\d+)$/.exec(market);
  if (multi) return home + away >= Number(multi[1]) && home + away <= Number(multi[2]);
  const euro = /^HCP EURO CASA ([+-]?\d+) ([1X2])$/.exec(market);
  if (euro) {
    const diff = home + Number(euro[1]) - away;
    return euro[2] === '1' ? diff > 0 : euro[2] === '2' ? diff < 0 : diff === 0;
  }
  return null;
}

function fixtureBeforeKickoff(raw, now = new Date()) {
  const fixture = raw && raw.response && raw.response[0] && raw.response[0].fixture;
  if (!fixture || fixture.status?.short !== 'NS') return null;
  const kickoff = new Date(fixture.date);
  if (!Number.isFinite(kickoff.getTime())) return null;
  const remaining = kickoff.getTime() - now.getTime();
  if (remaining < MIN_KICKOFF_LEAD_MS || remaining > MAX_KICKOFF_AHEAD_MS) return null;
  return kickoff;
}

function finishedScore(raw) {
  const entry = raw && raw.response && raw.response[0];
  if (!entry) return null;
  const status = entry.fixture?.status?.short;
  if (!['FT', 'AET', 'PEN'].includes(status)) return null;
  // AET/PEN: markets are always evaluated at the end of regular time.
  const scores = status === 'FT' ? (entry.score?.fulltime || entry.goals) : entry.score?.fulltime;
  const home = scores?.home;
  const away = scores?.away;
  if (!Number.isInteger(home) || !Number.isInteger(away) || home < 0 || away < 0) return null;
  return {home, away};
}

function validateBatch(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;
  if (typeof payload.clientId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(payload.clientId)) return null;
  if (!Array.isArray(payload.predictions) || payload.predictions.length < 1 ||
      payload.predictions.length > MAX_BATCH) return null;
  const predictions = [];
  const seen = new Set();
  for (const p of payload.predictions) {
    if (!p || !Number.isSafeInteger(p.fixtureId) || p.fixtureId <= 0 ||
        !['smartBet', 'diego'].includes(p.engine) || !Number.isFinite(p.probability) ||
        p.probability < 0 || p.probability > 1 || !isSupportedMarket(p.market)) return null;
    const item = {fixtureId: p.fixtureId, engine: p.engine, market: normalizeMarket(p.market), probability: p.probability};
    const key = `${item.fixtureId}|${item.engine}|${item.market}`;
    if (seen.has(key)) return null;
    seen.add(key);
    predictions.push(item);
  }
  return {clientId: payload.clientId.toLowerCase(), predictions};
}

function hashClientId(clientId, salt) {
  return crypto.createHmac('sha256', salt).update(clientId).digest('hex');
}

function validToken(actual, expected) {
  if (!expected || typeof actual !== 'string' || typeof expected !== 'string') return false;
  const a = Buffer.from(actual);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = {
  normalizeMarket, isSupportedMarket, settleMarket, fixtureBeforeKickoff, finishedScore,
  validateBatch, hashClientId, validToken,
};
