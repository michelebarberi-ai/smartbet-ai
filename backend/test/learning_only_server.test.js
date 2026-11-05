'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createLearningOnlyApp, requestFixture} = require('../learning_only_server');

function fakeFixture(id) {
  return {response: [{fixture: {id, date: '2026-12-01T18:00:00Z', status: {short: 'NS'}}}], errors: []};
}

test('learning-only server starts without OPENAI_API_KEY and denies learning writes by default', async () => {
  const app = createLearningOnlyApp({env: {}, fetchImpl: async () => {
    throw new Error('Should not contact provider with disabled learning');
  }});
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const health = await fetch(`${base}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), {
      service: 'GoalVdLine Central Learning', running: true, databaseChecked: false,
    });
    const status = await fetch(`${base}/learning/v1/status`);
    assert.equal(status.status, 200);
    const info = await status.json();
    assert.equal(info.enabled, false);
    assert.equal(info.mobileIngestEnabled, false);
    assert.equal((await fetch(`${base}/analyze`, {method: 'POST'})).status, 404);
    const upload = await fetch(`${base}/learning/v1/mobile/predictions`, {
      method: 'POST', headers: {'Content-Type':'application/json'}, body: '{}',
    });
    assert.equal(upload.status, 503);
  } finally {
    await new Promise((resolve, reject) => server.close(e => e ? reject(e) : resolve()));
  }
});

test('provider verification requests only the requested fixture without leaking credentials', async () => {
  let observed;
  const payload = await requestFixture({path:'/fixtures', query:{id:123}}, {
    env:{FOOTBALL_API_KEY:'private-test-key'},
    fetchImpl: async (url, options) => {
      observed = {url:url.toString(), options};
      return {ok:true, json: async () => fakeFixture(123)};
    },
  });
  assert.equal(payload.data.response[0].fixture.id, 123);
  assert.equal(new URL(observed.url).searchParams.get('id'), '123');
  assert.equal(new URL(observed.url).host, 'v3.football.api-sports.io');
  assert.equal(observed.options.headers['x-apisports-key'], 'private-test-key');
  assert.equal(observed.options.redirect, 'error');
  assert.equal(observed.url.includes('private-test-key'), false);
});

test('provider fails closed on invalid identity, missing token or non-matching fixture', async () => {
  await assert.rejects(requestFixture({path:'/fixtures', query:{id:'garbage'}},
    {env:{FOOTBALL_API_KEY:'fake'}}), /Invalid fixture/);
  await assert.rejects(requestFixture({path:'/fixtures', query:{id:123}}, {env:{}}),
    /not configured/);
  await assert.rejects(requestFixture({path:'/fixtures', query:{id:123}}, {
    env:{FOOTBALL_API_KEY:'fake'}, fetchImpl: async () => ({ok:true,json:async()=>fakeFixture(456)}),
  }), /not verifiable/);
  await assert.rejects(requestFixture({path:'/fixtures', query:{id:123}}, {
    env:{FOOTBALL_API_KEY:'fake'}, fetchImpl: async () => ({ok:false}),
  }), /unavailable/);
});
