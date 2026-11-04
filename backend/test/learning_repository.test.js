'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {LearningRepository} = require('../learning/learning_repository');

test('pending resolver rotates by last_checked_at, and writes a new check timestamp', async () => {
  const calls=[];
  const pool={async query(sql,params) {
    calls.push({sql,params});
    if (/SELECT fixture_id/.test(sql)) return {rows:[{fixture_id:'101'},{fixture_id:'102'}]};
    return {rowCount:2};
  }};
  const repo=new LearningRepository(pool);
  const now=new Date('2026-11-04T12:00:00Z');
  assert.deepEqual(await repo.pendingFixtureIds(20,now),[101,102]);
  assert.match(calls[0].sql,/ORDER BY MIN\(last_checked_at\) NULLS FIRST/);
  assert.match(calls[0].sql,/last_checked_at <= \$1::timestamptz - INTERVAL '30 minutes'/);
  assert.deepEqual(calls[0].params,[now,20]);
  await repo.markChecked(101,now);
  assert.match(calls[1].sql,/SET last_checked_at=\$2/);
  assert.match(calls[1].sql,/status='pending'/);
  assert.deepEqual(calls[1].params,[101,now]);
});

test('schema upgrades existing installations without erasing predictions', () => {
  const sql=fs.readFileSync(path.join(__dirname,'../learning/learning_schema.sql'),'utf8');
  assert.match(sql,/CREATE TABLE IF NOT EXISTS sb_learning_predictions_v1/);
  assert.match(sql,/ALTER TABLE sb_learning_predictions_v1\s+ADD COLUMN IF NOT EXISTS last_checked_at TIMESTAMPTZ/);
  assert.doesNotMatch(sql,/DROP TABLE|TRUNCATE TABLE|DELETE FROM/i);
});
