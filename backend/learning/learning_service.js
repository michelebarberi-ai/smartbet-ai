'use strict';

const crypto = require('node:crypto');

const {
  validateBatch, hashClientId, fixtureBeforeKickoff, finishedScore, settleMarket,
} = require('./learning_core');

class LearningService {
  constructor({repository, fetchFixture, subjectSalt, now = () => new Date()}) {
    this.repository = repository;
    this.fetchFixture = fetchFixture;
    this.subjectSalt = subjectSalt;
    this.now = now;
  }

  async ingest(payload) {
    const validated = validateBatch(payload);
    if (!validated) return {status: 400, body: {success: false, error: 'Dati non validi.'}};
    const fixtureIds = [...new Set(validated.predictions.map(p => p.fixtureId))];
    if (fixtureIds.length > 5) {
      return {status: 400, body: {success: false, error: 'Massimo 5 partite per invio.'}};
    }
    const now = this.now();
    const kickoffs = new Map();
    // Server-side verification: never trust the client for match status or kickoff.
    for (const fixtureId of fixtureIds) {
      const raw = await this.fetchFixture(fixtureId);
      if (Number(raw?.response?.[0]?.fixture?.id) !== fixtureId) {
        return {status: 422, body: {success: false, error: 'Partita non verificabile.'}};
      }
      const kickoff = fixtureBeforeKickoff(raw, now);
      if (!kickoff) {
        return {status: 422, body: {success: false, error: 'Previsioni accettate solo prima del calcio di inizio.'}};
      }
      kickoffs.set(fixtureId, kickoff);
    }
    await this.repository.initialize();
    const subjectHash = hashClientId(validated.clientId, this.subjectSalt);
    let inserted = 0;
    for (const prediction of validated.predictions) {
      const ok = await this.repository.insertPrediction({
        subjectHash, ...prediction,
        kickoff: kickoffs.get(prediction.fixtureId),
      });
      if (ok) inserted++;
    }
    return {status: 200, body: {success: true, accepted: inserted, duplicates: validated.predictions.length - inserted}};
  }

  // P23B2A: admin creates opaque, scoped device credentials; the admin key
  // must never be distributed to any mobile app.
  async provisionMobileClient() {
    await this.repository.initialize();
    const clientId = crypto.randomUUID();
    const token = crypto.randomBytes(32).toString('base64url');
    const expiresAt = new Date(this.now().getTime() + 30 * 24 * 60 * 60 * 1000);
    await this.repository.insertClientCredential({
      clientId, tokenHash: mobileTokenHash(token), expiresAt,
    });
    return {success: true, clientId, token, expiresAt: expiresAt.toISOString(),
      scope: 'learning:predictions', expiresInDays: 30};
  }

  async authenticateMobileToken(token) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token || '')) return null;
    await this.repository.initialize();
    return this.repository.findValidClient(mobileTokenHash(token), this.now());
  }

  async revokeMobileClient(clientId) {
    if (typeof clientId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clientId)) {
      return {status: 400, body: {success: false, error: 'Client non valido.'}};
    }
    await this.repository.initialize();
    const revoked = await this.repository.revokeClient(clientId);
    return {status: 200, body: {success: true, revoked}};
  }

  async eraseMobileClient(clientId) {
    await this.repository.initialize();
    const deleted = await this.repository.eraseClient({
      clientId, subjectHash: hashClientId(clientId, this.subjectSalt),
    });
    return {success: true, deleted};
  }

  async resolve(maxFixtures = 20) {
    await this.repository.initialize();
    const ids = await this.repository.pendingFixtureIds(Math.min(Math.max(maxFixtures, 1), 20), this.now());
    let resolvedFixtures = 0;
    let updatedRecords = 0;
    let skipped = 0;
    let errors = 0;
    for (const fixtureId of ids) {
      try {
        const raw = await this.fetchFixture(fixtureId);
        if (Number(raw?.response?.[0]?.fixture?.id) !== fixtureId) {
          skipped++;
          continue;
        }
        const score = finishedScore(raw);
        if (!score) { skipped++; continue; }
        const updated = await this.repository.resolveFixture(fixtureId, score.home, score.away, settleMarket);
        if (updated > 0) resolvedFixtures++;
        updatedRecords += updated;
      } catch (_) {
        errors++;
      } finally {
        // A skipped, cancelled, or temporarily unavailable fixture must not
        // monopolize the oldest pending batch forever.
        try {
          await this.repository.markChecked(fixtureId, this.now());
        } catch (_) {
          errors++;
        }
      }
    }
    const deletedOldRecords = await this.repository.prune();
    return {success: true, attemptedFixtures: ids.length, resolvedFixtures, updatedRecords, skipped, errors, deletedOldRecords};
  }

  async summary() {
    await this.repository.initialize();
    return {success: true, mode: 'research_only', appliesToLivePredictions: false,
      markets: await this.repository.summary()};
  }
}

function mobileTokenHash(token) {
  return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}

module.exports = {LearningService, mobileTokenHash};
