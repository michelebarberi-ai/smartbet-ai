'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {registerLearningRoutes} = require('../learning/learning_routes');

function fakeApp() {
  const routes = new Map();
  return {
    routes,
    get(path, ...handlers) {routes.set(`GET ${path}`, handlers);},
    post(path, ...handlers) {routes.set(`POST ${path}`, handlers);},
  };
}
function fakeRes() {
  return {code:200, payload:null, status(c) {this.code=c;return this;},
    json(data) {this.payload=data;return this;}};
}

test('learning endpoints are registered but fail closed by default', () => {
  const app=fakeApp();
  registerLearningRoutes(app,{env:{},requestApiFootball:async()=>{throw Error('must not call provider')}});
  const status=fakeRes();
  app.routes.get('GET /learning/v1/status')[0]({}, status);
  assert.equal(status.payload.enabled,false);
  const result=fakeRes();
  app.routes.get('POST /learning/v1/predictions')[0]({get:()=>null},result,()=>{throw Error('not allowed')});
  assert.equal(result.code,503);
});

test('learning endpoints refuse wrong admin token even when configured', () => {
  const app=fakeApp();
  registerLearningRoutes(app,{env:{LEARNING_SERVER_ENABLED:'true',DATABASE_URL:'postgresql://fake',
    LEARNING_ADMIN_TOKEN:'a'.repeat(32),LEARNING_SUBJECT_SALT:'b'.repeat(32)},
    requestApiFootball:async()=>{throw Error('must not call provider')}});
  const result=fakeRes();
  app.routes.get('POST /learning/v1/predictions')[0]({get:()=> 'not-the-token'},result,
    ()=>{throw Error('not allowed')});
  assert.equal(result.code,401);
});
