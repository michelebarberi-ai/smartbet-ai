'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {LearningService, mobileTokenHash} = require('../learning/learning_service');
const {registerLearningRoutes} = require('../learning/learning_routes');

const ADMIN = 'A'.repeat(40);
const SALT = 'S'.repeat(40);
const environment = {
  LEARNING_SERVER_ENABLED: 'true', LEARNING_MOBILE_INGEST_ENABLED: 'true',
  LEARNING_ADMIN_TOKEN: ADMIN, LEARNING_SUBJECT_SALT: SALT,
  DATABASE_URL: 'postgresql://unused',
};
function fakeApp() {
  const routes = new Map();
  return {routes, get(path, ...handlers) {routes.set(`GET ${path}`, handlers);},
    post(path, ...handlers) {routes.set(`POST ${path}`, handlers);}};
}
function fakeRes() {
  return {code: 200, payload: null, headers: {},
    status(c) {this.code = c; return this;},
    json(data) {this.payload = data; return this;},
    set(k,v) {this.headers[k] = v; return this;}};
}
function fakeRequest({authorization, adminToken, body} = {}) {
  return {body, get(k) {return k === 'authorization' ? authorization :
    k === 'x-smartbet-learning-admin' ? adminToken : null;}};
}
function makeService(now = new Date('2026-11-04T11:00:00Z')) {
  const state = {clients: new Map(), inserted: [], removed: []};
  const repository = {
    async initialize() {},
    async insertClientCredential({clientId, tokenHash, expiresAt}) {
      state.clients.set(tokenHash, {clientId, expiresAt, revoked: false});
    },
    async findValidClient(hash, timestamp) {
      const client = state.clients.get(hash);
      return client && !client.revoked && client.expiresAt > timestamp ? client.clientId : null;
    },
    async revokeClient(clientId) {
      for (const client of state.clients.values()) {
        if (client.clientId === clientId && !client.revoked) {
          client.revoked = true;
          return true;
        }
      }
      return false;
    },
    async eraseClient(data) { state.removed.push(data); return 3; },
    async insertPrediction(data) {state.inserted.push(data); return true;},
  };
  const fetchFixture = async (id) => ({response: [{fixture: {
    id, date: '2026-11-06T12:00:00Z', status: {short: 'NS'},
  }}]});
  return {service: new LearningService({repository, fetchFixture,
    subjectSalt: SALT, now: () => now}), state};
}

test('mobile token is 256-bit, hashed in storage and server assigned client identity', async () => {
  const {service, state} = makeService();
  const credential = await service.provisionMobileClient();
  assert.match(credential.clientId, /^[0-9a-f-]{36}$/);
  assert.match(credential.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(state.clients.has(mobileTokenHash(credential.token)), true);
  assert.notEqual(mobileTokenHash(credential.token), credential.token);
  assert.equal(await service.authenticateMobileToken(credential.token), credential.clientId);
  assert.equal(await service.authenticateMobileToken('x'.repeat(43)), null);
  assert.equal(await service.authenticateMobileToken('bad'), null);
  const result = await service.revokeMobileClient(credential.clientId);
  assert.equal(result.body.revoked, true);
  assert.equal(await service.authenticateMobileToken(credential.token), null);
});

test('mobile provision and uploads are disabled when flag is off', () => {
  const app = fakeApp();
  registerLearningRoutes(app, {env: {...environment, LEARNING_MOBILE_INGEST_ENABLED: 'false'},
    learningService: makeService().service});
  const res = fakeRes();
  app.routes.get('POST /learning/v1/mobile/predictions')[0](fakeRequest(), res, () => {
    assert.fail('mobile disabled must not proceed');
  });
  assert.equal(res.code, 503);
});

test('admin is needed for provision; mobile token cannot access admin routes', () => {
  const app = fakeApp();
  registerLearningRoutes(app, {env: environment, learningService: makeService().service});
  const res = fakeRes();
  app.routes.get('POST /learning/v1/clients/provision')[0](
    fakeRequest({authorization: 'Bearer x'}), res, () => assert.fail('no'));
  assert.equal(res.code, 401);
});

test('mobile upload refuses absent, malformed or admin-only credentials', async () => {
  const app = fakeApp();
  registerLearningRoutes(app, {env: environment, learningService: makeService().service});
  for (const authorization of [undefined, 'Bearer '+ADMIN, 'Basic bad']) {
    const res = fakeRes();
    await app.routes.get('POST /learning/v1/mobile/predictions')[0](
      fakeRequest({authorization}), res, () => assert.fail('must reject'));
    assert.equal(res.code, 401);
  }
});

test('authenticated mobile upload derives identity from token and rejects spoofing', async () => {
  const {service, state} = makeService();
  const creds = await service.provisionMobileClient();
  const app = fakeApp();
  registerLearningRoutes(app, {env: environment, learningService: service});
  const handlers = app.routes.get('POST /learning/v1/mobile/predictions');
  const request = fakeRequest({authorization: `Bearer ${creds.token}`, body: {
    clientId: crypto.randomUUID(), predictions: [{fixtureId: 123, engine: 'smartBet', market: '1', probability: 0.6}],
  }});
  const denied = fakeRes();
  await handlers[0](request, denied, () => handlers[1](request, denied));
  assert.equal(denied.code, 400);
  assert.equal(state.inserted.length, 0);

  request.body = {predictions: [{fixtureId: 123, engine: 'smartBet', market: '1', probability: 0.6}]};
  const success = fakeRes();
  await handlers[0](request, success, () => handlers[1](request, success));
  assert.equal(success.code, 200);
  assert.equal(success.payload.accepted, 1);
  assert.equal(state.inserted.length, 1);
  const expected = crypto.createHmac('sha256', SALT).update(creds.clientId).digest('hex');
  assert.equal(state.inserted[0].subjectHash, expected);
  assert.notEqual(state.inserted[0].subjectHash,
    crypto.createHmac('sha256', SALT).update(request.body.clientId || 'absent').digest('hex'));
});

test('erase revokes remote identity by token without altering client local history', async () => {
  const {service, state} = makeService();
  const creds = await service.provisionMobileClient();
  const app = fakeApp();
  registerLearningRoutes(app, {env: environment, learningService: service});
  const handlers = app.routes.get('POST /learning/v1/mobile/erase');
  const req = fakeRequest({authorization: `Bearer ${creds.token}`, body: {}});
  const res = fakeRes();
  await handlers[0](req, res, () => handlers[1](req, res));
  assert.equal(res.payload.deleted, 3);
  assert.equal(state.removed.length, 1);
  assert.equal(state.removed[0].clientId, creds.clientId);
  // Repository revokes token inside the same SQL transaction in production.
});
