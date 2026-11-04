'use strict';

const fs = require('node:fs');
const path = require('node:path');

class LearningRepository {
  constructor(pool) {
    this.pool = pool;
    this.ready = null;
  }

  async initialize() {
    if (!this.ready) {
      const sql = fs.readFileSync(path.join(__dirname, 'learning_schema.sql'), 'utf8');
      this.ready = this.pool.query(sql).catch((err) => { this.ready = null; throw err; });
    }
    await this.ready;
  }

  async insertPrediction({subjectHash, fixtureId, engine, market, probability, kickoff}) {
    const result = await this.pool.query(
      `INSERT INTO sb_learning_predictions_v1
       (subject_hash, fixture_id, engine, market, original_probability, kickoff_at)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (subject_hash, fixture_id, engine, market) DO NOTHING
       RETURNING id`,
      [subjectHash, fixtureId, engine, market, probability, kickoff]
    );
    return result.rowCount === 1;
  }

  async insertClientCredential({clientId, tokenHash, expiresAt}) {
    await this.pool.query(
      `INSERT INTO sb_learning_clients_v1 (client_id, token_hash, expires_at)
       VALUES ($1,$2,$3)`, [clientId, tokenHash, expiresAt]
    );
  }

  async findValidClient(tokenHash, now) {
    const result = await this.pool.query(
      `SELECT client_id FROM sb_learning_clients_v1
       WHERE token_hash=$1 AND expires_at>$2 AND revoked_at IS NULL
       LIMIT 1`, [tokenHash, now]
    );
    return result.rows.length ? result.rows[0].client_id : null;
  }

  async revokeClient(clientId) {
    const result = await this.pool.query(
      `UPDATE sb_learning_clients_v1 SET revoked_at=now()
       WHERE client_id=$1 AND revoked_at IS NULL`, [clientId]
    );
    return result.rowCount > 0;
  }

  // Authenticated deletion: predictions and device credential are revoked
  // atomically. Original app history is unaffected.
  async eraseClient({clientId, subjectHash}) {
    const connection = await this.pool.connect();
    try {
      await connection.query('BEGIN');
      const deleted = await connection.query(
        `DELETE FROM sb_learning_predictions_v1 WHERE subject_hash=$1`,
        [subjectHash]
      );
      await connection.query(
        `UPDATE sb_learning_clients_v1 SET revoked_at=now()
         WHERE client_id=$1 AND revoked_at IS NULL`, [clientId]
      );
      await connection.query('COMMIT');
      return deleted.rowCount;
    } catch (error) {
      await connection.query('ROLLBACK');
      throw error;
    } finally {
      connection.release();
    }
  }

  async pendingFixtureIds(limit, now) {
    const result = await this.pool.query(
      `SELECT fixture_id FROM sb_learning_predictions_v1
       WHERE status='pending' AND kickoff_at <= $1::timestamptz - INTERVAL '4 hours'
         AND (last_checked_at IS NULL OR last_checked_at <= $1::timestamptz - INTERVAL '30 minutes')
       GROUP BY fixture_id
       ORDER BY MIN(last_checked_at) NULLS FIRST, MIN(kickoff_at), fixture_id LIMIT $2`,
      [now, limit]
    );
    return result.rows.map(row => Number(row.fixture_id));
  }

  async markChecked(fixtureId, checkedAt) {
    await this.pool.query(
      `UPDATE sb_learning_predictions_v1 SET last_checked_at=$2
       WHERE fixture_id=$1 AND status='pending'`,
      [fixtureId, checkedAt]
    );
  }

  async resolveFixture(fixtureId, home, away, settle) {
    // Transaction: prevent partial outcomes when one market cannot be settled.
    const connection = await this.pool.connect();
    try {
      await connection.query('BEGIN');
      const current = await connection.query(
        `SELECT id, market FROM sb_learning_predictions_v1 WHERE fixture_id=$1 AND status='pending' FOR UPDATE`,
        [fixtureId]
      );
      let updated = 0;
      for (const row of current.rows) {
        const settled = settle(row.market, home, away);
        if (settled === null) continue;
        const result = await connection.query(
          `UPDATE sb_learning_predictions_v1 SET status=$2, actual_home_goals=$3,
           actual_away_goals=$4, resolved_at=now() WHERE id=$1 AND status='pending'`,
          [row.id, settled ? 'correct' : 'wrong', home, away]
        );
        updated += result.rowCount;
      }
      await connection.query('COMMIT');
      return updated;
    } catch (error) {
      await connection.query('ROLLBACK');
      throw error;
    } finally {
      connection.release();
    }
  }

  async summary() {
    // Deduplicate users within each fixture; an active user cannot dominate a market.
    const result = await this.pool.query(
      `WITH fixture_level AS (
         SELECT engine, market, fixture_id, AVG(original_probability) AS prediction,
                AVG(CASE WHEN status='correct' THEN 1.0 ELSE 0.0 END) AS outcome
         FROM sb_learning_predictions_v1
         WHERE status IN ('correct','wrong')
         GROUP BY engine, market, fixture_id
       )
       SELECT engine, market, COUNT(*)::INTEGER AS distinct_fixtures,
              AVG(prediction)::DOUBLE PRECISION AS average_prediction,
              AVG(outcome)::DOUBLE PRECISION AS realized_frequency
       FROM fixture_level GROUP BY engine, market
       HAVING COUNT(*) >= 10
       ORDER BY distinct_fixtures DESC, engine, market LIMIT 100`
    );
    return result.rows.map((r) => ({
      engine: r.engine, market: r.market,
      distinctFixtures: Number(r.distinct_fixtures),
      averagePrediction: Number(r.average_prediction),
      realizedFrequency: Number(r.realized_frequency),
      // Exploratory only. Never an eligibility decision for live calibration.
      researchOnly: true,
    }));
  }

  async prune() {
    const result = await this.pool.query(
      `DELETE FROM sb_learning_predictions_v1 WHERE received_at < now() - INTERVAL '365 days'`
    );
    return result.rowCount;
  }
}

module.exports = {LearningRepository};
