'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');

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

  async insertRetrospectiveBatch({subjectHash, snapshots}) {
    const params = [];
    const placeholders = [];
    for (const row of snapshots) {
      const start = params.length;
      params.push(subjectHash, row.fixtureId, row.engine, row.market,
        row.probability, row.firstSeenAt, row.kickoffAt, row.localStatusHint);
      placeholders.push(`(${Array.from({length: 8}, (_, n) => `$${start + n + 1}`).join(',')})`);
    }
    const result = await this.pool.query(
      `INSERT INTO sb_learning_retrospective_v1
       (subject_hash, fixture_id, engine, market, original_probability,
        claimed_first_seen_at, claimed_kickoff_at, local_status_hint)
       VALUES ${placeholders.join(',')}
       ON CONFLICT (subject_hash, fixture_id, engine, market) DO NOTHING
       RETURNING id`, params
    );
    return result.rowCount;
  }

  // B47: authenticated, idempotent on-demand requests. Never use the daily
  // preference subscription as an implicit job request.
  async enqueueOnDemandCoupon({subjectHash, requestId, dayKey, preferences}) {
    const jobId = randomUUID();
    await this.pool.query(
      `INSERT INTO sb_on_demand_coupon_jobs_v1
       (job_id,subject_hash,request_id,local_day,preferences)
       VALUES ($1::uuid,$2,$3::uuid,$4::date,$5::jsonb)
       ON CONFLICT (subject_hash,request_id) DO NOTHING`,
      [jobId,subjectHash,requestId,dayKey,JSON.stringify(preferences)]
    );
    const result = await this.pool.query(
      `SELECT job_id AS "jobId", status, local_day::text AS "dayKey", preferences
       FROM sb_on_demand_coupon_jobs_v1
       WHERE subject_hash=$1 AND request_id=$2::uuid`,
      [subjectHash,requestId]
    );
    const saved = result.rows[0];
    if (!saved || !isDeepStrictEqual(saved.preferences, preferences) ||
        saved.dayKey !== dayKey) {
      return {conflict:true};
    }
    return {jobId:saved.jobId,status:saved.status,dayKey:saved.dayKey};
  }

  async readOnDemandCoupon({subjectHash,jobId}) {
    const result = await this.pool.query(
      `SELECT job_id AS "jobId", local_day::text AS "dayKey", status,
         coupon_json AS coupon, completed_at AS "completedAt"
       FROM sb_on_demand_coupon_jobs_v1
       WHERE subject_hash=$1 AND job_id=$2::uuid`,
      [subjectHash,jobId]
    );
    return result.rows[0] || null;
  }

  // Atomic PostgreSQL lease, fenced by token and attempt. Reclaim a job
  // after a Render restart without allowing an old process to mark READY.
  async claimOnDemandCoupon() {
    await this.pool.query(
      `UPDATE sb_on_demand_coupon_jobs_v1 SET status='failed',
         lease_token=NULL, lease_expires_at=NULL, updated_at=clock_timestamp()
       WHERE status='running' AND attempts>=3
         AND lease_expires_at<=clock_timestamp()`
    );
    const leaseToken = randomUUID();
    const result = await this.pool.query(
      `WITH candidate AS (
         SELECT job_id FROM sb_on_demand_coupon_jobs_v1
         WHERE attempts<3 AND local_day=(clock_timestamp() AT TIME ZONE 'Europe/Rome')::date
           AND ((status='queued' AND
                   (next_retry_at IS NULL OR next_retry_at<=clock_timestamp()))
                OR (status='running' AND lease_expires_at<=clock_timestamp()))
         ORDER BY created_at
         FOR UPDATE SKIP LOCKED LIMIT 1
       )
       UPDATE sb_on_demand_coupon_jobs_v1 AS jobs SET
         status='running', attempts=jobs.attempts+1,
         lease_token=$1::uuid,
         lease_expires_at=clock_timestamp()+INTERVAL '3 minutes',
         next_retry_at=NULL, updated_at=clock_timestamp()
       FROM candidate WHERE jobs.job_id=candidate.job_id
       RETURNING jobs.job_id AS "jobId", jobs.subject_hash AS "subjectHash",
         jobs.local_day::text AS "dayKey", jobs.preferences, jobs.attempts,
         jobs.lease_token AS "leaseToken"`,
      [leaseToken]
    );
    return result.rows[0] || null;
  }

  async renewOnDemandCouponLease({jobId,attempts,leaseToken}) {
    const result = await this.pool.query(
      `UPDATE sb_on_demand_coupon_jobs_v1 SET
          lease_expires_at=clock_timestamp()+INTERVAL '3 minutes',
          updated_at=clock_timestamp()
       WHERE job_id=$1::uuid AND attempts=$2 AND lease_token=$3::uuid
         AND status='running' AND lease_expires_at>clock_timestamp()`,
      [jobId,attempts,leaseToken]
    );
    return result.rowCount===1;
  }

  async finishOnDemandCoupon({jobId,attempts,leaseToken,outcome,coupon=null}) {
    const ready = outcome==='ready';
    const noCoupon = outcome==='no_coupon';
    const result = await this.pool.query(
      `UPDATE sb_on_demand_coupon_jobs_v1 SET
        status=CASE WHEN $4::boolean THEN 'ready'
                    WHEN $5::boolean THEN 'no_coupon'
                    WHEN attempts<3 THEN 'queued' ELSE 'failed' END,
        coupon_json=CASE WHEN $4::boolean THEN $6::jsonb ELSE NULL END,
        completed_at=CASE WHEN $4::boolean OR $5::boolean OR attempts>=3
                    THEN clock_timestamp() ELSE NULL END,
        next_retry_at=CASE WHEN NOT ($4::boolean OR $5::boolean) AND attempts<3
                    THEN clock_timestamp()+INTERVAL '3 minutes' ELSE NULL END,
        lease_token=NULL, lease_expires_at=NULL, updated_at=clock_timestamp()
       WHERE job_id=$1::uuid AND attempts=$2 AND lease_token=$3::uuid
         AND status='running' AND lease_expires_at>clock_timestamp()`,
      [jobId,attempts,leaseToken,ready,noCoupon,
        ready ? JSON.stringify(coupon) : null]
    );
    return result.rowCount===1;
  }

  // Only user-selected preferences. This does not register a runnable job.
  async upsertAutoCouponPreferences({subjectHash, preferences}) {
    await this.pool.query(
      `INSERT INTO sb_auto_coupon_preferences_v1 (subject_hash, preferences)
       VALUES ($1,$2::jsonb)
       ON CONFLICT (subject_hash) DO UPDATE
       SET preferences=EXCLUDED.preferences, updated_at=now()`,
      [subjectHash, JSON.stringify(preferences)]
    );
  }

  async readAutoCouponPreferences(subjectHash) {
    const result = await this.pool.query(
      `SELECT preferences FROM sb_auto_coupon_preferences_v1 WHERE subject_hash=$1`,
      [subjectHash]
    );
    return result.rows.length ? result.rows[0].preferences : null;
  }

  // B45 P8: durable, idempotent daily coupon generation records. No worker
  // runs automatically; repository is called only by an explicit coordinator.
  async listAutoCouponSubscribers(limit, afterSubjectHash = null) {
    const result = await this.pool.query(
      `SELECT subject_hash AS "subjectHash", preferences
       FROM sb_auto_coupon_preferences_v1
       WHERE preferences->>'requested'='true' AND ($2::char(64) IS NULL OR subject_hash > $2)
       ORDER BY subject_hash LIMIT $1`, [limit, afterSubjectHash]
    );
    return result.rows;
  }

  // P20.3B: Neon is the authority for a daily job. A fresh UUID fences each
  // attempt: a timed-out worker can never finalize a newer attempt. Database
  // time (not Render container time) is used for every lease comparison.
  async claimAutoCouponRun({subjectHash, dayKey}) {
    const leaseToken = randomUUID();
    const result = await this.pool.query(
      `INSERT INTO sb_auto_coupon_daily_runs_v1
       (subject_hash, local_day, status, attempts, updated_at,
        lease_token, lease_expires_at)
       VALUES ($1,$2,'processing',1,clock_timestamp(),$3::uuid,
               clock_timestamp() + INTERVAL '3 minutes')
       ON CONFLICT (subject_hash,local_day) DO UPDATE SET
         status='processing',
         attempts=sb_auto_coupon_daily_runs_v1.attempts+1,
         updated_at=clock_timestamp(),
         lease_token=EXCLUDED.lease_token,
         lease_expires_at=clock_timestamp() + INTERVAL '3 minutes',
         next_retry_at=NULL, failure_reason=NULL
       WHERE sb_auto_coupon_daily_runs_v1.attempts < 5 AND (
         (sb_auto_coupon_daily_runs_v1.status='retry'
           AND sb_auto_coupon_daily_runs_v1.next_retry_at <= clock_timestamp())
         OR (sb_auto_coupon_daily_runs_v1.status='processing' AND (
           sb_auto_coupon_daily_runs_v1.lease_expires_at <= clock_timestamp()
           OR (sb_auto_coupon_daily_runs_v1.lease_expires_at IS NULL
             AND sb_auto_coupon_daily_runs_v1.updated_at <=
                 clock_timestamp() - INTERVAL '15 minutes')))
       )
       RETURNING attempts, lease_token AS "leaseToken"`,
      [subjectHash, dayKey, leaseToken]
    );
    return result.rowCount === 1
      ? {attempts: Number(result.rows[0].attempts), leaseToken: result.rows[0].leaseToken}
      : null;
  }

  // Keep a long-running official Flutter generation alive, without allowing a
  // lost/replaced lease to be renewed by the old worker. Do not persist payloads.
  async renewAutoCouponLease({subjectHash, dayKey, attempts, leaseToken}) {
    const result = await this.pool.query(
      `UPDATE sb_auto_coupon_daily_runs_v1 SET
         updated_at=clock_timestamp(),
         lease_expires_at=clock_timestamp() + INTERVAL '3 minutes'
       WHERE subject_hash=$1 AND local_day=$2 AND status='processing'
         AND attempts=$3 AND lease_token=$4::uuid
         AND lease_expires_at > clock_timestamp()
         AND EXISTS (SELECT 1 FROM sb_auto_coupon_preferences_v1 p
           WHERE p.subject_hash=$1 AND p.preferences->>'requested'='true')`,
      [subjectHash, dayKey, attempts, leaseToken]
    );
    return result.rowCount === 1;
  }

  async finishAutoCouponRun({subjectHash, dayKey, attempts, leaseToken, outcome,
    reason = null, coupon = null, now, retryMinutes = 60}) {
    const isReady = outcome === 'ready';
    const result = await this.pool.query(
      `UPDATE sb_auto_coupon_daily_runs_v1 SET
         status=CASE WHEN $4::boolean THEN 'ready'
                     WHEN attempts >= 5 THEN 'unavailable' ELSE 'retry' END,
         coupon_json=CASE WHEN $4::boolean THEN $5::jsonb ELSE NULL END,
         generated_at=CASE WHEN $4::boolean THEN $6::timestamptz ELSE NULL END,
         next_retry_at=CASE WHEN NOT $4::boolean AND attempts < 5
            THEN $6::timestamptz + ($8::integer * INTERVAL '1 minute') ELSE NULL END,
         failure_reason=CASE WHEN $4::boolean THEN NULL ELSE $7 END,
         updated_at=clock_timestamp(), lease_token=NULL, lease_expires_at=NULL
       WHERE subject_hash=$1 AND local_day=$2 AND status='processing'
         AND attempts=$3 AND lease_token=$9::uuid
         AND lease_expires_at > clock_timestamp()
         AND EXISTS (SELECT 1 FROM sb_auto_coupon_preferences_v1 p
           WHERE p.subject_hash=$1 AND p.preferences->>'requested'='true')`,
      [subjectHash, dayKey, attempts, isReady,
        isReady ? JSON.stringify(coupon) : null, now, reason, retryMinutes, leaseToken]
    );
    return result.rowCount === 1;
  }

  // After the fifth expired attempt there is no claimant left to mark the
  // record terminal. A scheduled worker marks it unavailable on its next pass.
  async finalizeExpiredAutoCouponRuns() {
    const result = await this.pool.query(
      `UPDATE sb_auto_coupon_daily_runs_v1 SET status='unavailable',
         failure_reason='provider_unavailable',
         lease_token=NULL, lease_expires_at=NULL, updated_at=clock_timestamp()
       WHERE status='processing' AND attempts >= 5 AND (
         lease_expires_at <= clock_timestamp() OR
         (lease_expires_at IS NULL AND
          updated_at <= clock_timestamp() - INTERVAL '15 minutes'))`
    );
    return result.rowCount;
  }

  async readAutoCouponDay({subjectHash, dayKey}) {
    const result = await this.pool.query(
      `SELECT status, coupon_json AS coupon, generated_at AS "generatedAt"
       FROM sb_auto_coupon_daily_runs_v1
       WHERE subject_hash=$1 AND local_day=$2`, [subjectHash, dayKey]
    );
    return result.rows[0] || null;
  }

  async deleteAutoCouponPreferences(subjectHash) {
    await this.pool.query('DELETE FROM sb_auto_coupon_preferences_v1 WHERE subject_hash=$1',
      [subjectHash]);
    await this.pool.query('DELETE FROM sb_auto_coupon_daily_runs_v1 WHERE subject_hash=$1',
      [subjectHash]);
    await this.pool.query('DELETE FROM sb_auto_coupon_push_deliveries_v1 WHERE subject_hash=$1',
      [subjectHash]);
    await this.deleteAutoCouponPushDevice(subjectHash);
  }

  // Device tokens are AES-256-GCM encrypted by the service before persistence.
  async upsertAutoCouponPushDevice({subjectHash, environment, ciphertext, nonce, authTag}) {
    await this.pool.query(
      `INSERT INTO sb_auto_coupon_push_devices_v1
       (subject_hash, apns_environment, token_ciphertext, token_nonce, token_auth_tag)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (subject_hash) DO UPDATE
       SET apns_environment=EXCLUDED.apns_environment,
           token_ciphertext=EXCLUDED.token_ciphertext,
           token_nonce=EXCLUDED.token_nonce,
           token_auth_tag=EXCLUDED.token_auth_tag,
           updated_at=now()`,
      [subjectHash, environment, ciphertext, nonce, authTag]
    );
  }

  async deleteAutoCouponPushDevice(subjectHash) {
    await this.pool.query(
      'DELETE FROM sb_auto_coupon_push_devices_v1 WHERE subject_hash=$1',
      [subjectHash]
    );
  }

  // B45 P13: APNs dispatch queue. Claiming is atomic across concurrent workers.
  async listPendingAutoCouponPushes({dayKey, now, limit, afterSubjectHash}) {
    const result = await this.pool.query(
      `SELECT runs.subject_hash AS "subjectHash"
       FROM sb_auto_coupon_daily_runs_v1 runs
       JOIN sb_auto_coupon_preferences_v1 prefs
         ON prefs.subject_hash = runs.subject_hash
       JOIN sb_auto_coupon_push_devices_v1 devices
         ON devices.subject_hash = runs.subject_hash
       LEFT JOIN sb_auto_coupon_push_deliveries_v1 sent
         ON sent.subject_hash = runs.subject_hash AND sent.local_day = runs.local_day
       WHERE runs.local_day=$1 AND runs.status='ready'
         AND prefs.preferences->>'requested'='true'
         AND ($4::char(64) IS NULL OR runs.subject_hash > $4)
         AND (sent.subject_hash IS NULL OR
              (sent.status='retry' AND sent.next_retry_at <= $2 AND sent.attempts < 5) OR
              (sent.status='processing' AND sent.updated_at <= $2 - INTERVAL '15 minutes'
               AND sent.attempts < 5))
       ORDER BY runs.subject_hash LIMIT $3`,
      [dayKey, now, limit, afterSubjectHash]
    );
    return result.rows;
  }

  async claimAutoCouponPush({subjectHash, dayKey, now}) {
    const result = await this.pool.query(
      `INSERT INTO sb_auto_coupon_push_deliveries_v1
       (subject_hash,local_day,status,attempts,updated_at)
       VALUES ($1,$2,'processing',1,$3)
       ON CONFLICT (subject_hash,local_day) DO UPDATE SET
         status='processing', attempts=sb_auto_coupon_push_deliveries_v1.attempts+1,
         updated_at=$3, next_retry_at=NULL, failure_reason=NULL
       WHERE sb_auto_coupon_push_deliveries_v1.attempts < 5 AND (
         (sb_auto_coupon_push_deliveries_v1.status='retry'
          AND sb_auto_coupon_push_deliveries_v1.next_retry_at <= $3) OR
         (sb_auto_coupon_push_deliveries_v1.status='processing'
          AND sb_auto_coupon_push_deliveries_v1.updated_at <= $3 - INTERVAL '15 minutes')
       ) RETURNING attempts`, [subjectHash, dayKey, now]
    );
    return result.rowCount === 1 ? {attempts: result.rows[0].attempts} : null;
  }

  async readAutoCouponPushDevice(subjectHash) {
    const result = await this.pool.query(
      `SELECT apns_environment AS environment, token_ciphertext AS ciphertext,
              token_nonce AS nonce, token_auth_tag AS "authTag"
       FROM sb_auto_coupon_push_devices_v1 WHERE subject_hash=$1`, [subjectHash]
    );
    return result.rows[0] || null;
  }

  async deleteAutoCouponPushDeviceIfMatch({subjectHash, ciphertext}) {
    await this.pool.query(
      `DELETE FROM sb_auto_coupon_push_devices_v1
       WHERE subject_hash=$1 AND token_ciphertext=$2`, [subjectHash, ciphertext]
    );
  }

  async finishAutoCouponPush({subjectHash, dayKey, attempts, outcome, reason, now}) {
    const result = await this.pool.query(
      `UPDATE sb_auto_coupon_push_deliveries_v1 SET
         status=CASE WHEN $4='sent' THEN 'sent'
                     WHEN $4='unregistered' THEN 'unregistered'
                     WHEN $4='unavailable' OR attempts >= 5 THEN 'unavailable'
                     ELSE 'retry' END,
         failure_reason=$5,
         next_retry_at=CASE WHEN $4='retry' AND attempts < 5
           THEN $6::timestamptz + INTERVAL '15 minutes' ELSE NULL END,
         updated_at=$6
       WHERE subject_hash=$1 AND local_day=$2 AND status='processing'
         AND attempts=$3`,
      [subjectHash, dayKey, attempts, outcome, reason, now]
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
      const removedHistorical = await connection.query(
        `DELETE FROM sb_learning_retrospective_v1 WHERE subject_hash=$1`,
        [subjectHash]
      );
      await connection.query(
        `DELETE FROM sb_auto_coupon_preferences_v1 WHERE subject_hash=$1`,
        [subjectHash]
      );
      await connection.query(
        `DELETE FROM sb_auto_coupon_daily_runs_v1 WHERE subject_hash=$1`,
        [subjectHash]
      );
      await connection.query(
        'DELETE FROM sb_auto_coupon_push_deliveries_v1 WHERE subject_hash=$1',
        [subjectHash]
      );
      await connection.query(
        'DELETE FROM sb_auto_coupon_push_devices_v1 WHERE subject_hash=$1',
        [subjectHash]
      );
      await connection.query(
        'DELETE FROM sb_on_demand_coupon_jobs_v1 WHERE subject_hash=$1',
        [subjectHash]
      );
      await connection.query(
        `UPDATE sb_learning_clients_v1 SET revoked_at=now()
         WHERE client_id=$1 AND revoked_at IS NULL`, [clientId]
      );
      await connection.query('COMMIT');
      return deleted.rowCount + removedHistorical.rowCount;
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
