'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {Pool} = require('pg');
const {LearningRepository} = require('../learning/learning_repository');
const {localClock} = require('../auto_coupon/daily_schedule');

// Only runs against an ephemeral PostgreSQL CI service. No production Neon
// credentials or external Render services are needed for this test.
test('B47 PostgreSQL: durable tenant queue, unique active job and fenced restart', {
  skip: !process.env.ON_DEMAND_TEST_DATABASE_URL,
}, async () => {
  const pool = new Pool({
    connectionString: process.env.ON_DEMAND_TEST_DATABASE_URL,
    connectionTimeoutMillis: 5000,
    max: 4,
  });
  const repo = new LearningRepository(pool);
  const owner = '1'.repeat(64), other = '2'.repeat(64);
  const dayKey = localClock(new Date()).dayKey;
  const preferences = {
    requested: true, hour: 0, minute: 0, events: 3,
    minimumMarketProbability: 65, market: 'MULTI', notifyChanges: false,
    systemMode: 'THREE_SAME_FIXTURES', windowDays: 1,
  };
  try {
    await repo.initialize();
    const requestId = randomUUID();
    const first = await repo.enqueueOnDemandCoupon({
      subjectHash: owner, requestId, dayKey, preferences,
    });
    assert.ok(first.jobId);
    assert.equal(first.status, 'queued');
    const duplicate = await repo.enqueueOnDemandCoupon({
      subjectHash: owner, requestId, dayKey, preferences,
    });
    assert.equal(duplicate.jobId, first.jobId);
    const conflict = await repo.enqueueOnDemandCoupon({
      subjectHash: owner, requestId: randomUUID(), dayKey, preferences,
    });
    assert.equal(conflict.conflict, true);
    assert.equal(await repo.readOnDemandCoupon({
      subjectHash: other, jobId: first.jobId,
    }), null);

    const simultaneous = await Promise.all([
      repo.claimOnDemandCoupon(), repo.claimOnDemandCoupon(),
    ]);
    assert.equal(simultaneous.filter(Boolean).length, 1);
    const lease = simultaneous.find(Boolean);
    assert.equal(lease.jobId, first.jobId);
    assert.equal(lease.attempts, 1);
    assert.equal(await repo.renewOnDemandCouponLease({
      ...lease, leaseToken: randomUUID(),
    }), false);
    assert.equal(await repo.renewOnDemandCouponLease(lease), true);

    // Simulate a crashed Render instance: old process must not publish READY.
    await pool.query(
      `UPDATE sb_on_demand_coupon_jobs_v1
       SET lease_expires_at = clock_timestamp() - INTERVAL '1 minute'
       WHERE job_id=$1::uuid`, [first.jobId]
    );
    const reclaimed = await repo.claimOnDemandCoupon();
    assert.equal(reclaimed.jobId, first.jobId);
    assert.equal(reclaimed.attempts, 2);
    assert.notEqual(reclaimed.leaseToken, lease.leaseToken);
    const stale = await repo.finishOnDemandCoupon({
      ...lease, outcome: 'ready',
      coupon: {events: [{fixtureId: 1, odds: 1.50}]},
    });
    assert.equal(stale, false);
    const saved = await repo.finishOnDemandCoupon({
      ...reclaimed, outcome: 'no_coupon',
    });
    assert.equal(saved, true);
    assert.equal((await repo.readOnDemandCoupon({
      subjectHash: owner, jobId: first.jobId,
    })).status, 'no_coupon');

    // A terminal request frees the slot for a new explicit user action.
    const later = await repo.enqueueOnDemandCoupon({
      subjectHash: owner, requestId: randomUUID(), dayKey, preferences,
    });
    assert.ok(later.jobId);
    assert.notEqual(later.jobId, first.jobId);
    await repo.eraseClient({clientId: randomUUID(), subjectHash: owner});
    assert.equal(await repo.readOnDemandCoupon({
      subjectHash: owner, jobId: later.jobId,
    }), null);
  } finally {
    await pool.end();
  }
});
