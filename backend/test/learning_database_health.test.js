'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createLearningOnlyApp, probeLearningDatabase} = require('../learning_only_server');

async function httpGet(app, path) {
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`);
    return {status: response.status, body: await response.json()};
  } finally {
    await new Promise((resolve, reject) => server.close(err => err ? reject(err) : resolve()));
  }
}

test('health database is disabled safely without DATABASE_URL', async () => {
  let accessed = false;
  const app = createLearningOnlyApp({env: {}, poolFactory: () => {
    accessed = true;
    throw new Error('should not access pool');
  }});
  const result = await httpGet(app, '/health/database');
  assert.equal(result.status, 503);
  assert.equal(result.body.databaseChecked, false);
  assert.equal(result.body.databaseReachable, false);
  assert.equal(result.body.schemaReady, false);
  assert.equal(accessed, false);
});

test('health database checks both tables read only while ingestion remains off', async () => {
  let queries = 0;
  let closed = 0;
  const env = {DATABASE_URL: 'postgresql://private:secret@localhost:5432/neondb',
    LEARNING_SERVER_ENABLED: 'false', LEARNING_MOBILE_INGEST_ENABLED: 'false'};
  const app = createLearningOnlyApp({env, poolFactory: options => {
    assert.equal(options.max, 1);
    assert.equal(options.connectionString, env.DATABASE_URL);
    return {
      query: async statement => {
        queries++;
        assert.match(statement, /to_regclass/);
        assert.doesNotMatch(statement, /INSERT|UPDATE|DELETE|DROP|TRUNCATE/i);
        return {rows: [{predictions_present: true, clients_present: true}]};
      },
      end: async () => {closed++;},
    };
  }});
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const first = await fetch(base + '/health/database');
    assert.equal(first.status, 200);
    const body = await first.json();
    assert.equal(body.databaseChecked, true);
    assert.equal(body.databaseReachable, true);
    assert.equal(body.schemaReady, true);
    assert.equal(JSON.stringify(body).includes('secret'), false);
    const second = await fetch(base + '/health/database');
    assert.equal(second.status, 200);
    assert.equal(queries, 1);  // 60-second cache
    assert.equal(closed, 1);
    const status = await (await fetch(base + '/learning/v1/status')).json();
    assert.equal(status.enabled, false);
    assert.equal(status.mobileIngestEnabled, false);
    const upload = await fetch(base + '/learning/v1/mobile/predictions', {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: '{}'});
    assert.equal(upload.status, 503);
  } finally {
    await new Promise((resolve, reject) => server.close(err => err ? reject(err) : resolve()));
  }
});

test('health database refuses missing schema without exposing details', async () => {
  const result = await probeLearningDatabase({
    env: {DATABASE_URL: 'postgresql://private:secret@localhost/test'},
    poolFactory: () => ({query: async () => ({rows: [{predictions_present: true,
      clients_present: false}]}), end: async () => {}}),
  });
  assert.deepEqual(result, {databaseChecked: true, databaseReachable: true, schemaReady: false});
  assert.equal(JSON.stringify(result).includes('secret'), false);
});

test('health database fails closed when PostgreSQL is unreachable', async () => {
  let closed = false;
  const result = await probeLearningDatabase({
    env: {DATABASE_URL: 'postgresql://private:secret@localhost/test'},
    poolFactory: () => ({query: async () => {throw new Error('secret DNS details');},
      end: async () => {closed = true;}}),
  });
  assert.deepEqual(result, {databaseChecked: true, databaseReachable: false, schemaReady: false});
  assert.equal(closed, true);
});
