'use strict';

// B72: truthful, read-only daily fixture digest. Never runs prediction engines,
// builds a coupon, fetches bookmaker odds, or claims betting availability.
const {romeDayKey} = require('./rome_clock');

const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;
const LIVE_OR_FINISHED = new Set([
  '1H', 'HT', '2H', 'ET', 'BT', 'P', 'FT', 'AET', 'PEN', 'LIVE',
  'PST', 'CANC', 'ABD', 'AWD', 'WO', 'SUSP', 'INT',
]);

function normalizeFixtureDigest(providerData, {
  dayKey, now = new Date(), timeZone = 'Europe/Rome',
} = {}) {
  if (!DAY_KEY.test(dayKey || '') ||
      !(now instanceof Date) || !Number.isFinite(now.getTime()) ||
      !Array.isArray(providerData?.response)) {
    throw new TypeError('Invalid or unavailable fixture feed');
  }
  const ids = new Set();
  const leagues = new Map();
  let count = 0;
  for (const entry of providerData.response) {
    const fixture = entry?.fixture;
    const league = entry?.league;
    const fixtureId = Number(fixture?.id);
    const leagueId = Number(league?.id);
    const date = typeof fixture?.date === 'string'
      ? new Date(fixture.date) : new Date(NaN);
    const short = String(fixture?.status?.short || '').toUpperCase();
    const leagueName = String(league?.name || '').trim();
    const country = String(league?.country || '').trim() || 'Mondo';
    if (!Number.isSafeInteger(fixtureId) || fixtureId <= 0 ||
        !Number.isSafeInteger(leagueId) || leagueId <= 0 ||
        !Number.isFinite(date.getTime()) || date <= now ||
        romeDayKey(date) !== dayKey ||
        !['NS','TBD'].includes(short) || !leagueName ||
        LIVE_OR_FINISHED.has(short) || ids.has(fixtureId)) continue;
    ids.add(fixtureId);
    count++;
    const key = String(leagueId);
    const current = leagues.get(key);
    if (current) current.matches++;
    else leagues.set(key, {leagueId, name: leagueName, country, matches: 1});
  }
  const competitions = Array.from(leagues.values()).sort((a,b) =>
    b.matches - a.matches ||
    a.country.localeCompare(b.country, 'it') ||
    a.name.localeCompare(b.name, 'it') ||
    a.leagueId - b.leagueId);
  return {
    dayKey,
    dateZone: timeZone,
    fixtureCount: count,
    leagueCount: competitions.length,
    competitions,
    source: 'API-FOOTBALL',
    meaning: 'calendar_only_not_predictions_or_verified_bets',
  };
}

function digestNotification(digest, {maxLeagues=4} = {}) {
  if (!digest || !DAY_KEY.test(digest.dayKey || '') ||
      !Number.isSafeInteger(digest.fixtureCount) || digest.fixtureCount < 0 ||
      !Array.isArray(digest.competitions) ||
      !Number.isInteger(maxLeagues) || maxLeagues < 1 || maxLeagues > 8) {
    throw new TypeError('Invalid daily digest');
  }
  const names = digest.competitions.slice(0, maxLeagues).map(x => x.name);
  const additional = Math.max(0, digest.leagueCount - names.length);
  const summary = digest.fixtureCount === 0
    ? 'Nessuna partita futura nel calendario di oggi.'
    : `${digest.fixtureCount} partite in ${digest.leagueCount} campionati. ` +
      (names.length ? names.join(', ') : '') +
      (additional ? ` e altri ${additional}.` : '.');
  // Data from fixture providers must not overflow APNs or contain controls.
  const clean = summary.replace(/[\x00-\x1f\x7f]/g,' ').slice(0, 220);
  return {
    title: 'GoalVdLine · Palinsesto di oggi',
    body: clean,
    dayKey: digest.dayKey,
    kind: 'daily_fixture_digest',
  };
}

function digestApnsPayload(digest) {
  const notice = digestNotification(digest);
  return JSON.stringify({
    aps: {alert: {title: notice.title, body: notice.body}, sound: 'default'},
    kind: notice.kind, dayKey: notice.dayKey,
  });
}

module.exports = {normalizeFixtureDigest, digestNotification, digestApnsPayload};
