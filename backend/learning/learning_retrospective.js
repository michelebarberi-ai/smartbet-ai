'use strict';
const MAX_RETROSPECTIVE_BATCH = 100;
const KIND = 'retrospective_unverified_v1';

function validateRetrospective(payload, now = new Date()) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
      !Array.isArray(payload.snapshots) || payload.snapshots.length < 1 ||
      payload.snapshots.length > MAX_RETROSPECTIVE_BATCH) return null;
  const seen = new Set();
  const snapshots = [];
  for (const row of payload.snapshots) {
    if (!row || typeof row !== 'object' || Array.isArray(row) || row.kind !== KIND ||
        !Number.isSafeInteger(row.fixtureId) || row.fixtureId <= 0 ||
        !['smartBet','diego'].includes(row.engine) ||
        typeof row.market !== 'string' || row.market.length < 1 || row.market.length > 64 ||
        row.market.trim() !== row.market ||
        !Number.isFinite(row.probability) || row.probability < 0 || row.probability > 1 ||
        !['pending','correct','wrong'].includes(row.localStatusHint) ||
        typeof row.firstSeenAt !== 'string' || typeof row.kickoffAt !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}T/.test(row.firstSeenAt) ||
        !/^\d{4}-\d{2}-\d{2}T/.test(row.kickoffAt) ||
        !/(?:Z|[+-]\d{2}:\d{2})$/.test(row.firstSeenAt) ||
        !/(?:Z|[+-]\d{2}:\d{2})$/.test(row.kickoffAt)) return null;
    const firstSeenAt = new Date(row.firstSeenAt);
    const kickoffAt = new Date(row.kickoffAt);
    if (!Number.isFinite(firstSeenAt.getTime()) || !Number.isFinite(kickoffAt.getTime()) ||
        firstSeenAt >= kickoffAt || kickoffAt > now || firstSeenAt > now) return null;
    const key = `${row.fixtureId}|${row.engine}|${row.market}`;
    if (seen.has(key)) return null;
    seen.add(key);
    snapshots.push({fixtureId: row.fixtureId, engine: row.engine, market: row.market,
      probability: row.probability, firstSeenAt, kickoffAt, localStatusHint: row.localStatusHint});
  }
  return snapshots;
}
module.exports = {validateRetrospective, MAX_RETROSPECTIVE_BATCH};
